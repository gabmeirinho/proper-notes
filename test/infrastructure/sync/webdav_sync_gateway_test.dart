import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:proper_notes/core/utils/attachments.dart';
import 'package:proper_notes/core/utils/content_hash.dart';
import 'package:proper_notes/features/auth/domain/sync_account_credentials.dart';
import 'package:proper_notes/features/notes/domain/note.dart';
import 'package:proper_notes/features/notes/domain/sync_status.dart';
import 'package:proper_notes/features/sync/domain/remote_note.dart';
import 'package:proper_notes/infrastructure/auth/secret_store.dart';
import 'package:proper_notes/infrastructure/auth/webdav_account_store.dart';
import 'package:proper_notes/infrastructure/sync/webdav_client.dart';
import 'package:proper_notes/infrastructure/sync/webdav_sync_gateway.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('proper_notes_attach_');
    debugAttachmentDirectoryOverride = tempDir;
  });

  tearDown(() async {
    debugAttachmentDirectoryOverride = null;
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('bootstrap reads notes and tombstones from the deterministic layout',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = WebDavAccountStore(
      secretStore: _FakeSecretStore(),
    );
    await store.write(
      const _CredentialsBuilder().build(),
    );

    final requests = <String>[];
    final gateway = WebDavSyncGateway(
      accountStore: store,
      webDavClient: WebDavClient(
        httpClient: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          if (request.method == 'MKCOL') {
            return http.Response('', 405);
          }
          if (request.method == 'PUT' &&
              request.url.path.endsWith('/meta/schema.json')) {
            return http.Response('', 201);
          }
          if (request.method == 'PROPFIND' &&
              request.url.path.endsWith('/notes')) {
            return http.Response(
                _multistatus(<String>[
                  '/remote.php/dav/files/user/ProperNotes/notes/',
                  '/remote.php/dav/files/user/ProperNotes/notes/note-1.json',
                ]),
                207);
          }
          if (request.method == 'PROPFIND' &&
              request.url.path.endsWith('/tombstones')) {
            return http.Response(
                _multistatus(<String>[
                  '/remote.php/dav/files/user/ProperNotes/tombstones/',
                  '/remote.php/dav/files/user/ProperNotes/tombstones/note-2.json',
                ]),
                207);
          }
          if (request.method == 'GET' &&
              request.url.path.endsWith('/notes/note-1.json')) {
            return http.Response(
              json.encode(<String, dynamic>{
                'id': 'note-1',
                'title': 'Remote note',
                'content': 'hello',
                'document_json': '{"type":"doc"}',
                'created_at': DateTime.utc(2026, 4, 1).millisecondsSinceEpoch,
                'updated_at': DateTime.utc(2026, 4, 2).millisecondsSinceEpoch,
                'content_hash': computeContentHash('hello'),
                'device_id': 'device-a',
                'schema_version': 1,
              }),
              200,
            );
          }
          if (request.method == 'GET' &&
              request.url.path.endsWith('/tombstones/note-2.json')) {
            return http.Response(
              json.encode(<String, dynamic>{
                'id': 'note-2',
                'deleted_at': DateTime.utc(2026, 4, 3).millisecondsSinceEpoch,
                'last_content_hash': computeContentHash(''),
                'device_id': 'device-b',
                'schema_version': 1,
              }),
              200,
            );
          }
          return http.Response('unexpected', 500);
        }),
      ),
    );

    final batch = await gateway.bootstrap();

    expect(batch.isFullSnapshot, isTrue);
    expect(batch.notes.map((note) => note.id).toSet(), {'note-1', 'note-2'});
    expect(batch.notes.firstWhere((note) => note.id == 'note-1').title,
        'Remote note');
    expect(
      batch.notes.firstWhere((note) => note.id == 'note-2').deletedAt,
      isNotNull,
    );
    expect(requests,
        contains('PROPFIND /remote.php/dav/files/user/ProperNotes/notes'));
    expect(
      requests,
      contains('PROPFIND /remote.php/dav/files/user/ProperNotes/tombstones'),
    );
  });

  test('upsertNote writes note payloads to notes/<id>.json', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final requests = <String>[];
    final store = WebDavAccountStore(
      secretStore: _FakeSecretStore(),
    );
    await store.write(
      const _CredentialsBuilder().build(),
    );

    final gateway = WebDavSyncGateway(
      accountStore: store,
      webDavClient: WebDavClient(
        httpClient: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          if (request.method == 'MKCOL') {
            return http.Response('', 405);
          }
          if (request.method == 'PUT') {
            return http.Response('', 201);
          }
          if (request.method == 'DELETE') {
            return http.Response('', 204);
          }
          return http.Response('unexpected', 500);
        }),
      ),
    );

    await gateway.upsertNote(
      Note(
        id: 'note-7',
        title: 'Uploaded note',
        content: 'body',
        createdAt: DateTime.utc(2026, 4, 10),
        updatedAt: DateTime.utc(2026, 4, 10, 1),
        syncStatus: SyncStatus.pendingUpload,
        contentHash: computeContentHash('body'),
        deviceId: 'device-a',
      ),
    );

    expect(
        requests,
        contains(
            'PUT /remote.php/dav/files/user/ProperNotes/notes/note-7.json'));
  });

  test('upsertNote returns tombstone path and etag for deleted notes',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = WebDavAccountStore(
      secretStore: _FakeSecretStore(),
    );
    await store.write(
      const _CredentialsBuilder().build(),
    );

    final gateway = WebDavSyncGateway(
      accountStore: store,
      webDavClient: WebDavClient(
        httpClient: MockClient((request) async {
          if (request.method == 'MKCOL') {
            return http.Response('', 405);
          }
          if (request.method == 'PUT' &&
              request.url.path.endsWith('/meta/schema.json')) {
            return http.Response('', 201);
          }
          if (request.method == 'PUT' &&
              request.url.path.endsWith('/notes/note-9.json')) {
            return http.Response('', 201, headers: <String, String>{
              'etag': '"note-etag"',
            });
          }
          if (request.method == 'PUT' &&
              request.url.path.endsWith('/tombstones/note-9.json')) {
            return http.Response('', 201, headers: <String, String>{
              'etag': '"tombstone-etag"',
            });
          }
          return http.Response('unexpected', 500);
        }),
      ),
    );

    final remote = await gateway.upsertNote(
      Note(
        id: 'note-9',
        title: 'Deleted note',
        content: 'body',
        createdAt: DateTime.utc(2026, 4, 10),
        updatedAt: DateTime.utc(2026, 4, 10, 1),
        deletedAt: DateTime.utc(2026, 4, 10, 2),
        syncStatus: SyncStatus.pendingDelete,
        contentHash: computeContentHash('body'),
        deviceId: 'device-a',
      ),
    );

    expect(remote.remoteFileId, 'tombstones/note-9.json');
    expect(remote.remoteEtag, '"tombstone-etag"');
  });

  test(
      'fetchChangesSince skips note downloads when the remote cursor is unchanged',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final requests = <String>[];
    final store = WebDavAccountStore(
      secretStore: _FakeSecretStore(),
    );
    await store.write(
      const _CredentialsBuilder().build(),
    );

    final notesListing = _multistatus(<String>[
      '/remote.php/dav/files/user/ProperNotes/notes/',
      '/remote.php/dav/files/user/ProperNotes/notes/note-1.json',
    ]);
    final tombstonesListing = _multistatus(<String>[
      '/remote.php/dav/files/user/ProperNotes/tombstones/',
    ]);

    final gateway = WebDavSyncGateway(
      accountStore: store,
      webDavClient: WebDavClient(
        httpClient: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          if (request.method == 'MKCOL') {
            return http.Response('', 405);
          }
          if (request.method == 'PUT' &&
              request.url.path.endsWith('/meta/schema.json')) {
            return http.Response('', 201);
          }
          if (request.method == 'PROPFIND' &&
              request.url.path.endsWith('/notes')) {
            return http.Response(notesListing, 207);
          }
          if (request.method == 'PROPFIND' &&
              request.url.path.endsWith('/tombstones')) {
            return http.Response(tombstonesListing, 207);
          }
          if (request.method == 'GET' &&
              request.url.path.endsWith('/notes/note-1.json')) {
            return http.Response(
              json.encode(<String, dynamic>{
                'id': 'note-1',
                'title': 'Remote note',
                'content': 'hello',
                'document_json': '{"type":"doc"}',
                'created_at': DateTime.utc(2026, 4, 1).millisecondsSinceEpoch,
                'updated_at': DateTime.utc(2026, 4, 2).millisecondsSinceEpoch,
                'content_hash': computeContentHash('hello'),
                'device_id': 'device-a',
              }),
              200,
            );
          }
          return http.Response('unexpected', 500);
        }),
      ),
    );

    final initialBatch = await gateway.bootstrap();
    requests.clear();

    final deltaBatch = await gateway.fetchChangesSince(initialBatch.nextToken);

    expect(deltaBatch.isFullSnapshot, isFalse);
    expect(deltaBatch.notes, isEmpty);
    expect(
      requests,
      isNot(contains(
          'GET /remote.php/dav/files/user/ProperNotes/notes/note-1.json')),
    );
    expect(
      requests.where((request) => request.startsWith('MKCOL ')),
      isEmpty,
    );
  });

  test(
      'fetchChangesSince skips tombstone downloads when the tombstone etag is already known',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final requests = <String>[];
    final store = WebDavAccountStore(
      secretStore: _FakeSecretStore(),
    );
    await store.write(
      const _CredentialsBuilder().build(),
    );

    final initialNotesListing = _multistatus(<String>[
      '/remote.php/dav/files/user/ProperNotes/notes/',
    ]);
    final initialTombstonesListing = _multistatus(<String>[
      '/remote.php/dav/files/user/ProperNotes/tombstones/',
      '/remote.php/dav/files/user/ProperNotes/tombstones/note-2.json',
    ]);
    final changedNotesListing = _multistatus(<String>[
      '/remote.php/dav/files/user/ProperNotes/notes/',
      '/remote.php/dav/files/user/ProperNotes/notes/note-3.json',
    ]);

    var stage = 0;
    final gateway = WebDavSyncGateway(
      accountStore: store,
      webDavClient: WebDavClient(
        httpClient: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          if (request.method == 'MKCOL') {
            return http.Response('', 405);
          }
          if (request.method == 'PUT' &&
              request.url.path.endsWith('/meta/schema.json')) {
            return http.Response('', 201);
          }
          if (request.method == 'PROPFIND' &&
              request.url.path.endsWith('/notes')) {
            return http.Response(
              stage == 0 ? initialNotesListing : changedNotesListing,
              207,
            );
          }
          if (request.method == 'PROPFIND' &&
              request.url.path.endsWith('/tombstones')) {
            return http.Response(initialTombstonesListing, 207);
          }
          if (request.method == 'GET' &&
              request.url.path.endsWith('/tombstones/note-2.json')) {
            return http.Response(
              json.encode(<String, dynamic>{
                'id': 'note-2',
                'deleted_at': DateTime.utc(2026, 4, 3).millisecondsSinceEpoch,
                'last_content_hash': computeContentHash(''),
                'device_id': 'device-b',
                'schema_version': 1,
              }),
              200,
            );
          }
          if (request.method == 'GET' &&
              request.url.path.endsWith('/notes/note-3.json')) {
            return http.Response(
              json.encode(<String, dynamic>{
                'id': 'note-3',
                'title': 'Remote note',
                'content': 'hello',
                'document_json': '{"type":"doc"}',
                'created_at': DateTime.utc(2026, 4, 1).millisecondsSinceEpoch,
                'updated_at': DateTime.utc(2026, 4, 2).millisecondsSinceEpoch,
                'content_hash': computeContentHash('hello'),
                'device_id': 'device-a',
              }),
              200,
            );
          }
          return http.Response('unexpected', 500);
        }),
      ),
    );

    final initialBatch = await gateway.bootstrap();
    stage = 1;
    requests.clear();

    final deltaBatch = await gateway.fetchChangesSince(
      initialBatch.nextToken,
      knownRemoteEtags: const <String, String?>{
        'tombstones/note-2.json':
            '"etag-/remote.php/dav/files/user/ProperNotes/tombstones/note-2.json"',
      },
    );

    expect(deltaBatch.notes.map((note) => note.id), ['note-3']);
    expect(
      requests,
      isNot(contains(
        'GET /remote.php/dav/files/user/ProperNotes/tombstones/note-2.json',
      )),
    );
  });

  test(
      'fetchChangesSince treats weak and strong etag variants as the same file',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final requests = <String>[];
    final store = WebDavAccountStore(
      secretStore: _FakeSecretStore(),
    );
    await store.write(
      const _CredentialsBuilder().build(),
    );

    final notesListing = _multistatus(<String>[
      '/remote.php/dav/files/user/ProperNotes/notes/',
    ]);
    const weakTombstonesListing =
        '<?xml version="1.0"?><d:multistatus xmlns:d="DAV:">'
        '<d:response><d:href>/remote.php/dav/files/user/ProperNotes/tombstones/</d:href>'
        '<d:propstat><d:prop><d:getetag>"etag-dir"</d:getetag></d:prop></d:propstat></d:response>'
        '<d:response><d:href>/remote.php/dav/files/user/ProperNotes/tombstones/note-2.json</d:href>'
        '<d:propstat><d:prop><d:getetag>W/"same-etag"</d:getetag></d:prop></d:propstat></d:response>'
        '</d:multistatus>';

    final gateway = WebDavSyncGateway(
      accountStore: store,
      webDavClient: WebDavClient(
        httpClient: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          if (request.method == 'MKCOL') {
            return http.Response('', 405);
          }
          if (request.method == 'PUT' &&
              request.url.path.endsWith('/meta/schema.json')) {
            return http.Response('', 201);
          }
          if (request.method == 'PROPFIND' &&
              request.url.path.endsWith('/notes')) {
            return http.Response(notesListing, 207);
          }
          if (request.method == 'PROPFIND' &&
              request.url.path.endsWith('/tombstones')) {
            return http.Response(weakTombstonesListing, 207);
          }
          if (request.method == 'GET' &&
              request.url.path.endsWith('/tombstones/note-2.json')) {
            return http.Response(
              json.encode(<String, dynamic>{
                'id': 'note-2',
                'deleted_at': DateTime.utc(2026, 4, 3).millisecondsSinceEpoch,
                'last_content_hash': computeContentHash(''),
                'device_id': 'device-b',
                'schema_version': 1,
              }),
              200,
            );
          }
          return http.Response('unexpected', 500);
        }),
      ),
    );

    final initialBatch = await gateway.bootstrap();
    requests.clear();

    final deltaBatch = await gateway.fetchChangesSince(
      initialBatch.nextToken,
      knownRemoteEtags: const <String, String?>{
        'tombstones/note-2.json': '"same-etag"',
      },
    );

    expect(deltaBatch.notes, isEmpty);
    expect(
      requests,
      isNot(contains(
        'GET /remote.php/dav/files/user/ProperNotes/tombstones/note-2.json',
      )),
    );
  });

  test('bootstrap prefers tombstones over note files for the same note id',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final requests = <String>[];
    final store = WebDavAccountStore(
      secretStore: _FakeSecretStore(),
    );
    await store.write(
      const _CredentialsBuilder().build(),
    );

    final gateway = WebDavSyncGateway(
      accountStore: store,
      webDavClient: WebDavClient(
        httpClient: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          if (request.method == 'MKCOL') {
            return http.Response('', 405);
          }
          if (request.method == 'PUT' &&
              request.url.path.endsWith('/meta/schema.json')) {
            return http.Response('', 201);
          }
          if (request.method == 'PROPFIND' &&
              request.url.path.endsWith('/notes')) {
            return http.Response(
                _multistatus(<String>[
                  '/remote.php/dav/files/user/ProperNotes/notes/',
                  '/remote.php/dav/files/user/ProperNotes/notes/note-2.json',
                ]),
                207);
          }
          if (request.method == 'PROPFIND' &&
              request.url.path.endsWith('/tombstones')) {
            return http.Response(
                _multistatus(<String>[
                  '/remote.php/dav/files/user/ProperNotes/tombstones/',
                  '/remote.php/dav/files/user/ProperNotes/tombstones/note-2.json',
                ]),
                207);
          }
          if (request.method == 'GET' &&
              request.url.path.endsWith('/tombstones/note-2.json')) {
            return http.Response(
              json.encode(<String, dynamic>{
                'id': 'note-2',
                'deleted_at': DateTime.utc(2026, 4, 3).millisecondsSinceEpoch,
                'last_content_hash': computeContentHash(''),
                'device_id': 'device-b',
                'schema_version': 1,
              }),
              200,
            );
          }
          if (request.method == 'GET' &&
              request.url.path.endsWith('/notes/note-2.json')) {
            return http.Response('unexpected note fetch', 500);
          }
          return http.Response('unexpected', 500);
        }),
      ),
    );

    final batch = await gateway.bootstrap();

    expect(batch.notes, hasLength(1));
    expect(batch.notes.single.id, 'note-2');
    expect(batch.notes.single.deletedAt, isNotNull);
    expect(
      requests,
      isNot(contains(
        'GET /remote.php/dav/files/user/ProperNotes/notes/note-2.json',
      )),
    );
    expect(
      requests,
      contains(
        'GET /remote.php/dav/files/user/ProperNotes/tombstones/note-2.json',
      ),
    );
  });

  test(
      'syncNoteAttachments skips uploads for attachments already present remotely',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final requests = <String>[];
    final store = WebDavAccountStore(
      secretStore: _FakeSecretStore(),
    );
    await store.write(
      const _CredentialsBuilder().build(),
    );
    final attachmentUri = await _createAttachment('shot.png', 'image-bytes');

    final gateway = WebDavSyncGateway(
      accountStore: store,
      webDavClient: WebDavClient(
        httpClient: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          if (request.method == 'MKCOL') {
            return http.Response('', 405);
          }
          if (request.method == 'PUT' &&
              request.url.path.endsWith('/meta/schema.json')) {
            return http.Response('', 201);
          }
          if (request.method == 'PROPFIND' &&
              request.url.path.endsWith('/attachments')) {
            return http.Response(
              _multistatus(<String>[
                '/remote.php/dav/files/user/ProperNotes/attachments/',
                '/remote.php/dav/files/user/ProperNotes/attachments/${_remoteAttachmentName(attachmentUri)}',
              ]),
              207,
            );
          }
          return http.Response('unexpected', 500);
        }),
      ),
    );

    await gateway.syncNoteAttachments(
      Note(
        id: 'note-1',
        title: 'Title',
        content: '![Shot]($attachmentUri)',
        createdAt: DateTime.utc(2026, 4, 10),
        updatedAt: DateTime.utc(2026, 4, 10),
        syncStatus: SyncStatus.pendingUpload,
        contentHash: computeContentHash('![Shot]($attachmentUri)'),
        deviceId: 'device-a',
      ),
    );

    expect(
      requests.where((request) =>
          request.startsWith('PUT ') && request.contains('/attachments/')),
      isEmpty,
    );
  });

  test(
      'ensureRemoteAttachmentsAvailable skips downloads for attachments missing remotely',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final requests = <String>[];
    final store = WebDavAccountStore(
      secretStore: _FakeSecretStore(),
    );
    await store.write(
      const _CredentialsBuilder().build(),
    );
    const attachmentUri = 'attachment://missing.png';

    final gateway = WebDavSyncGateway(
      accountStore: store,
      webDavClient: WebDavClient(
        httpClient: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          if (request.method == 'MKCOL') {
            return http.Response('', 405);
          }
          if (request.method == 'PUT' &&
              request.url.path.endsWith('/meta/schema.json')) {
            return http.Response('', 201);
          }
          if (request.method == 'PROPFIND' &&
              request.url.path.endsWith('/attachments')) {
            return http.Response(
              _multistatus(<String>[
                '/remote.php/dav/files/user/ProperNotes/attachments/',
              ]),
              207,
            );
          }
          return http.Response('unexpected', 500);
        }),
      ),
    );

    await gateway.ensureRemoteAttachmentsAvailable(<RemoteNote>[
      RemoteNote(
        id: 'remote-1',
        title: 'Remote',
        content: '![Attachment]($attachmentUri)',
        createdAt: DateTime.utc(2026, 4, 1),
        updatedAt: DateTime.utc(2026, 4, 1),
        contentHash: computeContentHash('![Attachment]($attachmentUri)'),
        deviceId: 'device-a',
      ),
    ]);

    expect(
      requests.where((request) =>
          request.startsWith('GET ') && request.contains('/attachments/')),
      isEmpty,
    );
  });
}

String _multistatus(List<String> hrefs) {
  final buffer = StringBuffer(
    '<?xml version="1.0"?><d:multistatus xmlns:d="DAV:">',
  );
  for (final href in hrefs) {
    buffer.write(
      '<d:response>'
      '<d:href>$href</d:href>'
      '<d:propstat><d:prop><d:getetag>"etag-$href"</d:getetag></d:prop></d:propstat>'
      '</d:response>',
    );
  }
  buffer.write('</d:multistatus>');
  return buffer.toString();
}

class _FakeSecretStore implements SecretStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write({
    required String key,
    required String value,
  }) async {
    values[key] = value;
  }
}

class _CredentialsBuilder {
  const _CredentialsBuilder();

  SyncAccountCredentials build() {
    return const SyncAccountCredentials(
      serverUrl: 'https://cloud.example.com/remote.php/dav/files/user',
      username: 'user',
      password: 'app-password',
      remoteRoot: 'ProperNotes',
    );
  }
}

Future<String> _createAttachment(String name, String contents) async {
  final file = File('${debugAttachmentDirectoryOverride!.path}/$name');
  await file.writeAsString(contents, flush: true);
  return 'attachment://$name';
}

String _remoteAttachmentName(String attachmentUri) {
  final fileName = attachmentFileNameFromUri(attachmentUri) ?? 'attachment.bin';
  final extension = fileName.contains('.') ? fileName.split('.').last : 'bin';
  final digest = sha256.convert(utf8.encode(attachmentUri)).toString();
  return '$digest.$extension';
}
