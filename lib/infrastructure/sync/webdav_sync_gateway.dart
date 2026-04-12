import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../core/utils/attachments.dart';
import '../../core/utils/content_hash.dart';
import '../../core/utils/note_document.dart';
import '../../features/auth/domain/sync_account_credentials.dart';
import '../../features/notes/domain/note.dart';
import '../../features/sync/domain/remote_note.dart';
import '../../features/sync/domain/sync_gateway.dart';
import '../auth/webdav_account_store.dart';
import 'webdav_client.dart';
import 'webdav_models.dart';

class WebDavSyncGateway implements SyncGateway {
  WebDavSyncGateway({
    required WebDavAccountStore accountStore,
    WebDavClient? webDavClient,
  })  : _accountStore = accountStore,
        _webDavClient = webDavClient ?? WebDavClient();

  static const _schemaVersion = 1;

  final WebDavAccountStore _accountStore;
  final WebDavClient _webDavClient;
  bool _hasEnsuredBootstrapLayout = false;

  @override
  Future<RemoteSyncBatch> bootstrap() async {
    final context = await _loadContext();
    await _ensureBootstrapLayout(context);
    final listings = await _fetchRemoteListings(context);
    final remoteNotes = await _fetchRemoteSnapshot(
      context,
      noteListing: listings.noteListing,
      tombstoneListing: listings.tombstoneListing,
      cursor: listings.cursor,
      knownRemoteEtags: const <String, String?>{},
      changedOnly: false,
    );
    return RemoteSyncBatch(
      notes: remoteNotes.notes,
      nextToken: remoteNotes.cursor,
      isFullSnapshot: true,
    );
  }

  @override
  Future<RemoteSyncBatch> fetchChangesSince(
    String token, {
    Map<String, String?> knownRemoteEtags = const <String, String?>{},
  }) async {
    final context = await _loadContext();
    await _ensureBootstrapLayout(context);
    final listings = await _fetchRemoteListings(context);
    if (listings.cursor == token) {
      return RemoteSyncBatch(
        notes: const <RemoteNote>[],
        nextToken: token,
        isFullSnapshot: false,
      );
    }

    final remoteNotes = await _fetchRemoteSnapshot(
      context,
      noteListing: listings.noteListing,
      tombstoneListing: listings.tombstoneListing,
      cursor: listings.cursor,
      knownRemoteEtags: knownRemoteEtags,
      changedOnly: true,
    );
    return RemoteSyncBatch(
      notes: remoteNotes.notes,
      nextToken: remoteNotes.cursor,
      isFullSnapshot: false,
    );
  }

  @override
  Future<List<RemoteNote>> fetchAllNotes() async {
    final batch = await bootstrap();
    return batch.notes;
  }

  @override
  Future<RemoteNote> upsertNote(Note note) async {
    final context = await _loadContext();
    await _ensureBootstrapLayout(context);

    final payload = <String, dynamic>{
      'id': note.id,
      'title': note.title,
      'content': note.content,
      'document_json': note.documentJson.isEmpty
          ? legacyDocumentFromContent(note.content)
          : note.documentJson,
      'created_at': note.createdAt.millisecondsSinceEpoch,
      'updated_at': note.updatedAt.millisecondsSinceEpoch,
      'deleted_at': note.deletedAt?.millisecondsSinceEpoch,
      'content_hash': note.contentHash,
      'base_content_hash': note.baseContentHash,
      'device_id': note.deviceId,
      'folder_path': note.folderPath,
      'schema_version': _schemaVersion,
    };

    final noteWrite =
        await _webDavClient.putJson(context, 'notes/${note.id}.json', payload);

    if (note.deletedAt != null) {
      final tombstoneWrite = await _webDavClient.putJson(
        context,
        'tombstones/${note.id}.json',
        <String, dynamic>{
          'id': note.id,
          'deleted_at': note.deletedAt!.millisecondsSinceEpoch,
          'last_content_hash': note.contentHash,
          'device_id': note.deviceId,
          'schema_version': _schemaVersion,
        },
      );
      final remotePath = 'tombstones/${note.id}.json';
      return RemoteNote(
        id: note.id,
        title: note.title,
        content: note.content,
        documentJson: payload['document_json'] as String,
        createdAt: note.createdAt,
        updatedAt: note.updatedAt,
        deletedAt: note.deletedAt,
        contentHash: note.contentHash,
        baseContentHash: note.baseContentHash,
        deviceId: note.deviceId,
        folderPath: note.folderPath,
        remoteFileId: remotePath,
        remoteEtag: tombstoneWrite.etag,
      );
    } else {
      await _webDavClient.deleteIfExists(context, 'tombstones/${note.id}.json');
    }

    final remotePath = 'notes/${note.id}.json';
    return RemoteNote(
      id: note.id,
      title: note.title,
      content: note.content,
      documentJson: payload['document_json'] as String,
      createdAt: note.createdAt,
      updatedAt: note.updatedAt,
      deletedAt: note.deletedAt,
      contentHash: note.contentHash,
      baseContentHash: note.baseContentHash,
      deviceId: note.deviceId,
      folderPath: note.folderPath,
      remoteFileId: remotePath,
      remoteEtag: noteWrite.etag,
    );
  }

  @override
  Future<void> syncNoteAttachments(Note note) async {
    final attachmentUris = extractAttachmentUrisFromText(note.content);
    if (attachmentUris.isEmpty) {
      return;
    }

    final context = await _loadContext();
    await _ensureBootstrapLayout(context);
    final attachmentListing =
        await _webDavClient.propfindDirectory(context, 'attachments');
    final remoteAttachmentNames =
        attachmentListing.entries.map((entry) => entry.path).toSet();

    for (final attachmentUri in attachmentUris) {
      final localFile = await resolveAttachmentFile(attachmentUri);
      if (localFile == null || !await localFile.exists()) {
        continue;
      }

      final remoteName = _attachmentRemoteNameForUri(attachmentUri);
      if (remoteAttachmentNames.contains(remoteName)) {
        continue;
      }
      final bytes = await localFile.readAsBytes();
      await _webDavClient.putBytes(context, 'attachments/$remoteName', bytes);
    }
  }

  @override
  Future<void> ensureRemoteAttachmentsAvailable(List<RemoteNote> notes) async {
    final attachmentUris = <String>{
      for (final note in notes) ...extractAttachmentUrisFromText(note.content),
    };
    if (attachmentUris.isEmpty) {
      return;
    }

    final context = await _loadContext();
    await _ensureBootstrapLayout(context);
    final attachmentListing =
        await _webDavClient.propfindDirectory(context, 'attachments');
    final remoteAttachmentNames =
        attachmentListing.entries.map((entry) => entry.path).toSet();

    for (final attachmentUri in attachmentUris) {
      final localFile = await resolveAttachmentFile(attachmentUri);
      if (localFile != null && await localFile.exists()) {
        continue;
      }

      final fileName = attachmentFileNameFromUri(attachmentUri);
      if (fileName == null) {
        continue;
      }

      final remoteName = _attachmentRemoteNameForUri(attachmentUri);
      if (!remoteAttachmentNames.contains(remoteName)) {
        continue;
      }
      final bytes =
          await _webDavClient.getBytes(context, 'attachments/$remoteName');
      final output = await resolveAttachmentFile(attachmentUri);
      if (output == null) {
        continue;
      }
      await output.create(recursive: true);
      await output.writeAsBytes(bytes, flush: true);
    }
  }

  Future<WebDavConnectionContext> _loadContext() async {
    final account = await _accountStore.read();
    if (account == null) {
      throw Exception('A sync account must be configured before sync can run.');
    }

    return _webDavClient.resolveContext(
      SyncAccountCredentials(
        serverUrl: account.serverUrl,
        username: account.username,
        password: account.password,
        remoteRoot: account.remoteRoot,
      ),
    );
  }

  Future<void> _ensureBootstrapLayout(WebDavConnectionContext context) async {
    if (_hasEnsuredBootstrapLayout) {
      return;
    }
    await _webDavClient.ensureCollection(context, '');
    await _webDavClient.ensureCollection(context, 'meta');
    await _webDavClient.ensureCollection(context, 'notes');
    await _webDavClient.ensureCollection(context, 'tombstones');
    await _webDavClient.ensureCollection(context, 'attachments');
    await _webDavClient.putJson(
      context,
      'meta/schema.json',
      <String, dynamic>{
        'schema_version': _schemaVersion,
      },
    );
    _hasEnsuredBootstrapLayout = true;
  }

  Future<_RemoteListings> _fetchRemoteListings(
    WebDavConnectionContext context,
  ) async {
    final noteListing = await _webDavClient.propfindDirectory(context, 'notes');
    final tombstoneListing =
        await _webDavClient.propfindDirectory(context, 'tombstones');
    final fingerprintParts = <String>[];

    for (final entry in noteListing.entries) {
      if (entry.path.endsWith('.json')) {
        fingerprintParts.add('${entry.path}:${entry.etag ?? ''}');
      }
    }
    for (final entry in tombstoneListing.entries) {
      if (entry.path.endsWith('.json')) {
        fingerprintParts.add('${entry.path}:${entry.etag ?? ''}');
      }
    }

    final cursorSeed = <String>[
      noteListing.collectionTag ?? '',
      tombstoneListing.collectionTag ?? '',
      ...fingerprintParts..sort(),
    ].join('|');

    return _RemoteListings(
      noteListing: noteListing,
      tombstoneListing: tombstoneListing,
      cursor: sha256.convert(utf8.encode(cursorSeed)).toString(),
    );
  }

  Future<_RemoteSnapshot> _fetchRemoteSnapshot(
    WebDavConnectionContext context, {
    required WebDavDirectoryListing noteListing,
    required WebDavDirectoryListing tombstoneListing,
    required String cursor,
    required Map<String, String?> knownRemoteEtags,
    required bool changedOnly,
  }) async {
    final remoteById = <String, RemoteNote>{};
    final tombstoneIds = tombstoneListing.entries
        .where((entry) => entry.path.endsWith('.json'))
        .map((entry) => entry.path.replaceFirst('.json', ''))
        .toSet();

    for (final entry in noteListing.entries) {
      if (!entry.path.endsWith('.json')) {
        continue;
      }
      final noteId = entry.path.replaceFirst('.json', '');
      if (tombstoneIds.contains(noteId)) {
        continue;
      }
      final remotePath = 'notes/${entry.path}';
      if (changedOnly &&
          _remoteEtagsMatch(knownRemoteEtags[remotePath], entry.etag)) {
        continue;
      }
      final payload = await _webDavClient.getJson(context, remotePath);
      final remoteNote = _remoteNoteFromPayload(
        payload,
        remoteFileId: remotePath,
        remoteEtag: entry.etag,
      );
      remoteById[remoteNote.id] = remoteNote;
    }

    for (final entry in tombstoneListing.entries) {
      if (!entry.path.endsWith('.json')) {
        continue;
      }
      final remotePath = 'tombstones/${entry.path}';
      if (changedOnly &&
          _remoteEtagsMatch(knownRemoteEtags[remotePath], entry.etag)) {
        continue;
      }
      final noteId = entry.path.replaceFirst('.json', '');
      if (remoteById.containsKey(noteId)) {
        continue;
      }
      final payload = await _webDavClient.getJson(context, remotePath);
      remoteById[noteId] = _remoteDeletionFromPayload(
        payload,
        remoteFileId: remotePath,
        remoteEtag: entry.etag,
      );
    }

    return _RemoteSnapshot(
      notes: remoteById.values.toList(growable: false),
      cursor: cursor,
    );
  }

  RemoteNote _remoteNoteFromPayload(
    Map<String, dynamic> payload, {
    required String remoteFileId,
    required String? remoteEtag,
  }) {
    final content = payload['content'] as String? ?? '';
    final documentJson = payload['document_json'] as String? ??
        legacyDocumentFromContent(content);
    return RemoteNote(
      id: payload['id'] as String,
      title: payload['title'] as String? ?? '',
      content: content,
      documentJson: documentJson,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (payload['created_at'] as num?)?.toInt() ?? 0,
        isUtc: true,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (payload['updated_at'] as num?)?.toInt() ?? 0,
        isUtc: true,
      ),
      deletedAt: (payload['deleted_at'] as num?) == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              (payload['deleted_at'] as num).toInt(),
              isUtc: true,
            ),
      contentHash:
          payload['content_hash'] as String? ?? computeContentHash(content),
      baseContentHash: payload['base_content_hash'] as String?,
      deviceId: payload['device_id'] as String? ?? '',
      folderPath: payload['folder_path'] as String?,
      remoteFileId: remoteFileId,
      remoteEtag: remoteEtag,
    );
  }

  RemoteNote _remoteDeletionFromPayload(
    Map<String, dynamic> payload, {
    required String remoteFileId,
    required String? remoteEtag,
  }) {
    final deletedAtMillis = (payload['deleted_at'] as num?)?.toInt() ?? 0;
    return RemoteNote(
      id: payload['id'] as String,
      title: '',
      content: '',
      documentJson: legacyDocumentFromContent(''),
      createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      updatedAt:
          DateTime.fromMillisecondsSinceEpoch(deletedAtMillis, isUtc: true),
      deletedAt:
          DateTime.fromMillisecondsSinceEpoch(deletedAtMillis, isUtc: true),
      contentHash:
          payload['last_content_hash'] as String? ?? computeContentHash(''),
      baseContentHash: payload['last_content_hash'] as String?,
      deviceId: payload['device_id'] as String? ?? '',
      remoteFileId: remoteFileId,
      remoteEtag: remoteEtag,
    );
  }

  String _attachmentRemoteNameForUri(String attachmentUri) {
    final fileName =
        attachmentFileNameFromUri(attachmentUri) ?? 'attachment.bin';
    final extension = fileName.contains('.') ? fileName.split('.').last : 'bin';
    final digest = sha256.convert(utf8.encode(attachmentUri)).toString();
    return '$digest.$extension';
  }

  bool _remoteEtagsMatch(String? known, String? current) {
    return _normalizeEtag(known) == _normalizeEtag(current);
  }

  String? _normalizeEtag(String? value) {
    if (value == null) {
      return null;
    }

    var normalized = value.trim();
    if (normalized.isEmpty) {
      return null;
    }
    if (normalized.startsWith('W/')) {
      normalized = normalized.substring(2).trimLeft();
    }
    return normalized;
  }
}

class _RemoteSnapshot {
  const _RemoteSnapshot({
    required this.notes,
    required this.cursor,
  });

  final List<RemoteNote> notes;
  final String cursor;
}

class _RemoteListings {
  const _RemoteListings({
    required this.noteListing,
    required this.tombstoneListing,
    required this.cursor,
  });

  final WebDavDirectoryListing noteListing;
  final WebDavDirectoryListing tombstoneListing;
  final String cursor;
}
