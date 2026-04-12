import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:proper_notes/core/utils/attachments.dart';
import 'package:proper_notes/features/auth/domain/auth_session.dart';
import 'package:proper_notes/features/notes/domain/note.dart';
import 'package:proper_notes/features/notes/domain/sync_status.dart';
import 'package:proper_notes/features/sync/domain/remote_note.dart';
import 'package:proper_notes/infrastructure/auth/google_auth_config.dart';
import 'package:proper_notes/infrastructure/auth/google_oauth_token_client.dart';
import 'package:proper_notes/infrastructure/auth/oauth_session_store.dart';
import 'package:proper_notes/infrastructure/sync/google_drive_sync_gateway.dart';

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory =
        await Directory.systemTemp.createTemp('drive_sync_gateway_test_');
    debugAttachmentDirectoryOverride = tempDirectory;
  });

  tearDown(() async {
    debugAttachmentDirectoryOverride = null;
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('desktop sync reuses a refreshed access token across requests',
      () async {
    var refreshCalls = 0;

    final tokenHttpClient = MockClient((request) async {
      refreshCalls += 1;
      return http.Response(
        json.encode(<String, dynamic>{
          'access_token': 'access-token-1',
          'expires_in': 3600,
        }),
        200,
      );
    });

    final driveHttpClient = MockClient((request) async {
      final authHeader = request.headers['Authorization'];
      expect(authHeader, 'Bearer access-token-1');

      if (request.url.path == '/drive/v3/files' &&
          request.url.queryParameters['spaces'] == 'appDataFolder') {
        return http.Response(
          json.encode(<String, dynamic>{
            'files': <Map<String, dynamic>>[],
          }),
          200,
        );
      }

      if (request.url.path == '/drive/v3/changes/startPageToken') {
        return http.Response(
          json.encode(<String, dynamic>{
            'startPageToken': 'start-token-1',
          }),
          200,
        );
      }

      if (request.url.host == 'www.googleapis.com' &&
          request.url.path == '/upload/drive/v3/files' &&
          request.method == 'POST') {
        return http.Response(
          json.encode(<String, dynamic>{
            'id': 'remote-note-1',
          }),
          201,
        );
      }

      fail('Unexpected request: ${request.method} ${request.url}');
    });

    final gateway = GoogleDriveSyncGateway(
      config: const GoogleAuthConfig(
        desktopClientId: 'desktop-client-id',
        desktopClientSecret: 'desktop-secret',
        androidServerClientId: '',
      ),
      tokenClient: GoogleOAuthTokenClient(httpClient: tokenHttpClient),
      sessionStore: _FakeOAuthSessionStore(
        storedSession: const StoredOAuthSession(
          session: AuthSession(
            email: 'user@example.com',
            displayName: 'User',
          ),
          refreshToken: 'refresh-token-1',
        ),
      ),
      httpClient: driveHttpClient,
    );

    final bootstrap = await gateway.bootstrap();
    expect(bootstrap.nextToken, 'start-token-1');

    await gateway.upsertNote(
      Note(
        id: 'note-1',
        title: 'Note 1',
        content: 'Hello',
        createdAt: DateTime.utc(2026, 3, 26, 10),
        updatedAt: DateTime.utc(2026, 3, 26, 10),
        lastSyncedAt: null,
        syncStatus: SyncStatus.pendingUpload,
        contentHash: 'hash-1',
        baseContentHash: null,
        deviceId: 'device-1',
      ),
    );

    expect(refreshCalls, 1);
  });

  test('delta sync stops if Drive repeats the same nextPageToken', () async {
    var changeRequests = 0;

    final tokenHttpClient = MockClient((request) async {
      return http.Response(
        json.encode(<String, dynamic>{
          'access_token': 'access-token-1',
          'expires_in': 3600,
        }),
        200,
      );
    });

    final driveHttpClient = MockClient((request) async {
      if (request.url.path == '/drive/v3/changes') {
        changeRequests += 1;
        return http.Response(
          json.encode(<String, dynamic>{
            'changes': <Map<String, dynamic>>[],
            'nextPageToken': 'loop-token',
            'newStartPageToken': 'next-token',
          }),
          200,
        );
      }

      fail('Unexpected request: ${request.method} ${request.url}');
    });

    final gateway = GoogleDriveSyncGateway(
      config: const GoogleAuthConfig(
        desktopClientId: 'desktop-client-id',
        desktopClientSecret: 'desktop-secret',
        androidServerClientId: '',
      ),
      tokenClient: GoogleOAuthTokenClient(httpClient: tokenHttpClient),
      sessionStore: _FakeOAuthSessionStore(
        storedSession: const StoredOAuthSession(
          session: AuthSession(
            email: 'user@example.com',
            displayName: 'User',
          ),
          refreshToken: 'refresh-token-1',
        ),
      ),
      httpClient: driveHttpClient,
    );

    final batch = await gateway.fetchChangesSince('loop-token');

    expect(batch.notes, isEmpty);
    expect(batch.nextToken, 'next-token');
    expect(batch.isFullSnapshot, isFalse);
    expect(changeRequests, 1);
  });

  test(
      'syncNoteAttachments uploads local attachment blobs referenced by a note',
      () async {
    final savedImage = await saveAttachmentImageBytes(
      Uint8List.fromList(const <int>[1, 2, 3, 4]),
      extension: 'png',
    );
    final note = Note(
      id: 'note-with-attachment',
      title: 'Attachment note',
      content: '![Diagram](${savedImage.attachmentUri})',
      createdAt: DateTime.utc(2026, 3, 26, 10),
      updatedAt: DateTime.utc(2026, 3, 26, 10),
      syncStatus: SyncStatus.pendingUpload,
      contentHash: 'hash-1',
      deviceId: 'device-1',
    );

    final tokenHttpClient = MockClient((request) async {
      return http.Response(
        json.encode(<String, dynamic>{
          'access_token': 'access-token-1',
          'expires_in': 3600,
        }),
        200,
      );
    });

    var querySawAttachmentName = false;
    var uploadedAttachment = false;
    final driveHttpClient = MockClient((request) async {
      if (request.url.path == '/drive/v3/files' &&
          request.url.queryParameters['q'] != null) {
        querySawAttachmentName =
            request.url.queryParameters['q']!.contains('attachment_');
        return http.Response(json.encode({'files': []}), 200);
      }

      if (request.url.host == 'www.googleapis.com' &&
          request.url.path == '/upload/drive/v3/files' &&
          request.method == 'POST') {
        uploadedAttachment = true;
        return http.Response(json.encode({'id': 'remote-attachment-1'}), 201);
      }

      fail('Unexpected request: ${request.method} ${request.url}');
    });

    final gateway = GoogleDriveSyncGateway(
      config: const GoogleAuthConfig(
        desktopClientId: 'desktop-client-id',
        desktopClientSecret: 'desktop-secret',
        androidServerClientId: '',
      ),
      tokenClient: GoogleOAuthTokenClient(httpClient: tokenHttpClient),
      sessionStore: _FakeOAuthSessionStore(
        storedSession: const StoredOAuthSession(
          session: AuthSession(
            email: 'user@example.com',
            displayName: 'User',
          ),
          refreshToken: 'refresh-token-1',
        ),
      ),
      httpClient: driveHttpClient,
    );

    await gateway.syncNoteAttachments(note);

    expect(querySawAttachmentName, isTrue);
    expect(uploadedAttachment, isTrue);
  });

  test('ensureRemoteAttachmentsAvailable downloads missing attachment blobs',
      () async {
    final tokenHttpClient = MockClient((request) async {
      return http.Response(
        json.encode(<String, dynamic>{
          'access_token': 'access-token-1',
          'expires_in': 3600,
        }),
        200,
      );
    });

    final driveHttpClient = MockClient((request) async {
      if (request.url.path == '/drive/v3/files' &&
          request.url.queryParameters['q'] != null) {
        return http.Response(
          json.encode({
            'files': [
              {'id': 'remote-attachment-1', 'name': 'attachment_shot.png'}
            ],
          }),
          200,
        );
      }

      if (request.url.path == '/drive/v3/files/remote-attachment-1' &&
          request.url.queryParameters['alt'] == 'media') {
        return http.Response.bytes(
          Uint8List.fromList(const <int>[9, 8, 7, 6]),
          200,
        );
      }

      fail('Unexpected request: ${request.method} ${request.url}');
    });

    final gateway = GoogleDriveSyncGateway(
      config: const GoogleAuthConfig(
        desktopClientId: 'desktop-client-id',
        desktopClientSecret: 'desktop-secret',
        androidServerClientId: '',
      ),
      tokenClient: GoogleOAuthTokenClient(httpClient: tokenHttpClient),
      sessionStore: _FakeOAuthSessionStore(
        storedSession: const StoredOAuthSession(
          session: AuthSession(
            email: 'user@example.com',
            displayName: 'User',
          ),
          refreshToken: 'refresh-token-1',
        ),
      ),
      httpClient: driveHttpClient,
    );

    await gateway.ensureRemoteAttachmentsAvailable([
      RemoteNote(
        id: 'remote-1',
        title: 'Remote note',
        content: '![Screenshot](attachment://shot.png)',
        createdAt: DateTime.utc(2026, 3, 26, 10),
        updatedAt: DateTime.utc(2026, 3, 26, 10),
        contentHash: 'hash-1',
        deviceId: 'device-1',
      ),
    ]);

    final file = await resolveAttachmentFile('attachment://shot.png');
    expect(file, isNotNull);
    expect(await file!.exists(), isTrue);
    expect(
        await file.readAsBytes(), Uint8List.fromList(const <int>[9, 8, 7, 6]));
  });

  test('fetchAllNotes preserves UTF-8 note text from Drive downloads',
      () async {
    final tokenHttpClient = MockClient((request) async {
      return http.Response(
        json.encode(<String, dynamic>{
          'access_token': 'access-token-1',
          'expires_in': 3600,
        }),
        200,
      );
    });

    final accentedPayload = utf8.encode(
      json.encode(<String, dynamic>{
        'id': 'remote-utf8',
        'title': 'Organização',
        'content': 'FOCA-TE\nGeração\nação com ç e ~',
        'created_at': DateTime.utc(2026, 3, 26, 10).millisecondsSinceEpoch,
        'updated_at': DateTime.utc(2026, 3, 26, 11).millisecondsSinceEpoch,
        'content_hash': 'hash-utf8',
        'device_id': 'device-1',
      }),
    );

    final driveHttpClient = MockClient((request) async {
      if (request.url.path == '/drive/v3/files' &&
          request.url.queryParameters['spaces'] == 'appDataFolder') {
        return http.Response(
          json.encode(<String, dynamic>{
            'files': [
              {
                'id': 'remote-file-1',
                'name': 'note_remote-utf8.json',
                'mimeType': 'application/vnd.proper-notes.note+json',
              },
            ],
          }),
          200,
        );
      }

      if (request.url.path == '/drive/v3/files/remote-file-1' &&
          request.url.queryParameters['alt'] == 'media') {
        return http.Response.bytes(
          accentedPayload,
          200,
          headers: const {'content-type': 'application/json'},
        );
      }

      fail('Unexpected request: ${request.method} ${request.url}');
    });

    final gateway = GoogleDriveSyncGateway(
      config: const GoogleAuthConfig(
        desktopClientId: 'desktop-client-id',
        desktopClientSecret: 'desktop-secret',
        androidServerClientId: '',
      ),
      tokenClient: GoogleOAuthTokenClient(httpClient: tokenHttpClient),
      sessionStore: _FakeOAuthSessionStore(
        storedSession: const StoredOAuthSession(
          session: AuthSession(
            email: 'user@example.com',
            displayName: 'User',
          ),
          refreshToken: 'refresh-token-1',
        ),
      ),
      httpClient: driveHttpClient,
    );

    final notes = await gateway.fetchAllNotes();

    expect(notes, hasLength(1));
    expect(notes.single.title, 'Organização');
    expect(notes.single.content, 'FOCA-TE\nGeração\nação com ç e ~');
  });
}

class _FakeOAuthSessionStore implements OAuthSessionStore {
  _FakeOAuthSessionStore({
    this.storedSession,
  });

  final StoredOAuthSession? storedSession;

  @override
  Future<void> clear() async {}

  @override
  Future<StoredOAuthSession?> read() async => storedSession;

  @override
  Future<void> write({
    required AuthSession session,
    String? refreshToken,
    String? accessToken,
    DateTime? accessTokenExpiresAt,
  }) async {}
}
