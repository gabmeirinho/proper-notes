import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../../core/utils/attachments.dart';
import '../../core/utils/note_document.dart';
import '../../features/notes/domain/note.dart';
import '../../features/sync/domain/remote_note.dart';
import '../../features/sync/domain/sync_gateway.dart';
import '../auth/google_auth_config.dart';
import '../auth/google_oauth_token_client.dart';
import '../auth/oauth_session_store.dart';

class GoogleDriveSyncGateway implements SyncGateway {
  GoogleDriveSyncGateway({
    required GoogleAuthConfig config,
    required GoogleOAuthTokenClient tokenClient,
    OAuthSessionStore? sessionStore,
    http.Client? httpClient,
  })  : _config = config,
        _sessionStore = sessionStore ?? SharedPreferencesOAuthSessionStore(),
        _tokenClient = tokenClient,
        _httpClient = httpClient ?? http.Client();

  static const _remoteNoteMimeType = 'application/vnd.proper-notes.note+json';
  static const _legacyRemoteNoteMimeType = 'application/json';
  static const _remoteAttachmentPrefix = 'attachment_';
  static const _remoteFetchBatchSize = 8;
  static const _desktopAccessTokenExpirySkew = Duration(minutes: 1);
  static const _androidAccessTokenExpirySkew = Duration(minutes: 1);

  final GoogleAuthConfig _config;
  final OAuthSessionStore _sessionStore;
  final GoogleOAuthTokenClient _tokenClient;
  final http.Client _httpClient;
  Future<Map<String, String>>? _androidAuthHeadersFuture;
  String? _desktopAccessToken;
  DateTime? _desktopAccessTokenExpiresAt;

  @override
  Future<RemoteSyncBatch> bootstrap() async {
    final authHeaders = await _getAuthHeaders();
    final notes = await _fetchAllNotes(authHeaders: authHeaders);
    final token = await _getStartPageToken(authHeaders: authHeaders);
    return RemoteSyncBatch(
      notes: notes,
      nextToken: token,
      isFullSnapshot: true,
    );
  }

  @override
  Future<RemoteSyncBatch> fetchChangesSince(
    String token, {
    Map<String, String?> knownRemoteEtags = const <String, String?>{},
  }) async {
    final authHeaders = await _getAuthHeaders();
    String pageToken = token;
    final notesById = <String, RemoteNote>{};
    final seenPageTokens = <String>{};
    String? nextToken;

    do {
      if (!seenPageTokens.add(pageToken)) {
        break;
      }

      final response = await _httpClient.get(
        Uri.https('www.googleapis.com', '/drive/v3/changes', {
          'pageToken': pageToken,
          'spaces': 'appDataFolder',
          'fields':
              'changes(fileId,removed,file(id,name,mimeType)),nextPageToken,newStartPageToken',
        }),
        headers: authHeaders,
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to list Drive changes: ${response.body}');
      }

      final payload = _decodeJsonResponse(response);
      final changes =
          (payload['changes'] as List<dynamic>? ?? const <dynamic>[])
              .cast<Map<String, dynamic>>();
      final changedFileIds = <String>[];

      for (final change in changes) {
        final removed = change['removed'] as bool? ?? false;
        if (removed) {
          continue;
        }

        final file = change['file'] as Map<String, dynamic>?;
        final fileId =
            (change['fileId'] as String?) ?? (file?['id'] as String?);
        if (fileId == null || fileId.isEmpty) {
          continue;
        }
        if (!_isSupportedRemoteFile(file)) {
          continue;
        }
        changedFileIds.add(fileId);
      }

      final changedNotes = await _fetchRemoteNotesByFileIds(
        fileIds: changedFileIds,
        authHeaders: authHeaders,
      );
      for (final note in changedNotes) {
        notesById[note.id] = note;
      }

      final nextPageToken = payload['nextPageToken'] as String? ?? '';
      pageToken = nextPageToken == pageToken ? '' : nextPageToken;
      nextToken = payload['newStartPageToken'] as String? ?? nextToken;
    } while (pageToken.isNotEmpty);

    return RemoteSyncBatch(
      notes: notesById.values.toList(growable: false),
      nextToken: nextToken ?? token,
      isFullSnapshot: false,
    );
  }

  @override
  Future<List<RemoteNote>> fetchAllNotes() async {
    final authHeaders = await _getAuthHeaders();
    return _fetchAllNotes(authHeaders: authHeaders);
  }

  Future<List<RemoteNote>> _fetchAllNotes({
    required Map<String, String> authHeaders,
  }) async {
    final listResponse = await _httpClient.get(
      Uri.https('www.googleapis.com', '/drive/v3/files', {
        'spaces': 'appDataFolder',
        'fields': 'files(id,name,mimeType)',
      }),
      headers: authHeaders,
    );

    if (listResponse.statusCode != 200) {
      throw Exception(
          'Failed to list Drive app data files: ${listResponse.body}');
    }

    final payload = _decodeJsonResponse(listResponse);
    final files = (payload['files'] as List<dynamic>? ?? const <dynamic>[])
        .cast<Map<String, dynamic>>();

    final fileIds = <String>[];
    for (final file in files) {
      final id = file['id'] as String?;
      if (id == null || id.isEmpty) {
        continue;
      }
      if (!_isSupportedRemoteFile(file)) {
        continue;
      }
      fileIds.add(id);
    }

    return _fetchRemoteNotesByFileIds(
      fileIds: fileIds,
      authHeaders: authHeaders,
    );
  }

  @override
  Future<RemoteNote> upsertNote(Note note) async {
    final authHeaders = await _getAuthHeaders();
    final fileName = 'note_${note.id}.json';
    final metadata = <String, dynamic>{
      'name': fileName,
      'mimeType': _remoteNoteMimeType,
      if (note.remoteFileId == null) 'parents': ['appDataFolder'],
    };
    final payload = json.encode(<String, dynamic>{
      'id': note.id,
      'title': note.title,
      'content': note.content,
      'created_at': note.createdAt.millisecondsSinceEpoch,
      'updated_at': note.updatedAt.millisecondsSinceEpoch,
      'deleted_at': note.deletedAt?.millisecondsSinceEpoch,
      'device_id': note.deviceId,
      'folder_path': note.folderPath,
      'content_hash': note.contentHash,
    });

    final boundary =
        'proper_notes_boundary_${DateTime.now().microsecondsSinceEpoch}';
    final body = [
      '--$boundary',
      'Content-Type: application/json; charset=UTF-8',
      '',
      json.encode(metadata),
      '--$boundary',
      'Content-Type: application/json; charset=UTF-8',
      '',
      payload,
      '--$boundary--',
      '',
    ].join('\r\n');

    final uri = note.remoteFileId == null
        ? Uri.parse(
            'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart',
          )
        : Uri.parse(
            'https://www.googleapis.com/upload/drive/v3/files/${note.remoteFileId}?uploadType=multipart',
          );
    final response = await (note.remoteFileId == null
        ? _httpClient.post(
            uri,
            headers: {
              ...authHeaders,
              'Content-Type': 'multipart/related; boundary=$boundary',
            },
            body: body,
          )
        : _httpClient.patch(
            uri,
            headers: {
              ...authHeaders,
              'Content-Type': 'multipart/related; boundary=$boundary',
            },
            body: body,
          ));

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Failed to upload Drive note: ${response.body}');
    }

    final responsePayload = _decodeJsonResponse(response);
    return RemoteNote(
      id: note.id,
      title: note.title,
      content: note.content,
      documentJson: note.documentJson.isEmpty
          ? legacyDocumentFromContent(note.content)
          : note.documentJson,
      createdAt: note.createdAt,
      updatedAt: note.updatedAt,
      deletedAt: note.deletedAt,
      contentHash: note.contentHash,
      deviceId: note.deviceId,
      folderPath: note.folderPath,
      remoteFileId: responsePayload['id'] as String?,
    );
  }

  @override
  Future<void> syncNoteAttachments(Note note) async {
    final authHeaders = await _getAuthHeaders();
    final attachmentUris = extractAttachmentUrisFromText(note.content);
    for (final attachmentUri in attachmentUris) {
      final file = await resolveAttachmentFile(attachmentUri);
      if (file == null || !await file.exists()) {
        continue;
      }

      final fileName = attachmentFileNameFromUri(attachmentUri);
      if (fileName == null || fileName.isEmpty) {
        continue;
      }

      await _upsertAttachmentFile(
        remoteName: '$_remoteAttachmentPrefix$fileName',
        file: file,
        authHeaders: authHeaders,
      );
    }
  }

  @override
  Future<void> ensureRemoteAttachmentsAvailable(List<RemoteNote> notes) async {
    final authHeaders = await _getAuthHeaders();
    final attachmentUris = <String>{};
    for (final note in notes) {
      attachmentUris.addAll(extractAttachmentUrisFromText(note.content));
    }

    for (final attachmentUri in attachmentUris) {
      final localFile = await resolveAttachmentFile(attachmentUri);
      if (localFile == null) {
        continue;
      }
      if (await localFile.exists()) {
        continue;
      }

      final fileName = attachmentFileNameFromUri(attachmentUri);
      if (fileName == null || fileName.isEmpty) {
        continue;
      }

      final remoteFileId = await _findRemoteFileIdByName(
        '$_remoteAttachmentPrefix$fileName',
        authHeaders: authHeaders,
      );
      if (remoteFileId == null) {
        continue;
      }

      final response = await _httpClient.get(
        Uri.https(
          'www.googleapis.com',
          '/drive/v3/files/$remoteFileId',
          {'alt': 'media'},
        ),
        headers: authHeaders,
      );
      if (response.statusCode != 200) {
        continue;
      }

      await localFile.parent.create(recursive: true);
      await localFile.writeAsBytes(response.bodyBytes, flush: true);
    }
  }

  Future<Map<String, String>> _getAuthHeaders() async {
    if (!kIsWeb && Platform.isAndroid) {
      return _getAndroidAuthHeaders();
    }

    final accessToken = await _getDesktopAccessToken();
    return _authHeaders(accessToken);
  }

  Future<Map<String, String>> _getAndroidAuthHeaders() async {
    return _androidAuthHeadersFuture ??= _resolveAndroidAuthHeaders();
  }

  Future<Map<String, String>> _resolveAndroidAuthHeaders() async {
    try {
      final storedSession = await _sessionStore.read();
      final cachedAccessToken = storedSession?.accessToken;
      final cachedAccessTokenExpiresAt = storedSession?.accessTokenExpiresAt;
      final now = DateTime.now().toUtc();
      if (cachedAccessToken != null &&
          cachedAccessToken.isNotEmpty &&
          cachedAccessTokenExpiresAt != null &&
          now.isBefore(cachedAccessTokenExpiresAt
              .subtract(_androidAccessTokenExpirySkew))) {
        return _authHeaders(cachedAccessToken);
      }

      final headers =
          await GoogleSignIn.instance.authorizationClient.authorizationHeaders(
        const ['https://www.googleapis.com/auth/drive.appdata'],
        promptIfNecessary: false,
      );
      if (headers == null || headers.isEmpty) {
        throw Exception(
          'Google Drive access was not granted. Sign in again and approve Drive access.',
        );
      }

      final accessToken = _extractBearerToken(headers);
      if (storedSession != null &&
          accessToken != null &&
          accessToken.isNotEmpty) {
        await _sessionStore.write(
          session: storedSession.session,
          refreshToken: storedSession.refreshToken,
          accessToken: accessToken,
          accessTokenExpiresAt: now.add(const Duration(minutes: 50)),
        );
      }

      return headers;
    } catch (_) {
      _androidAuthHeadersFuture = null;
      rethrow;
    }
  }

  Future<void> _upsertAttachmentFile({
    required String remoteName,
    required File file,
    required Map<String, String> authHeaders,
  }) async {
    final remoteFileId = await _findRemoteFileIdByName(
      remoteName,
      authHeaders: authHeaders,
    );
    final metadata = <String, dynamic>{
      'name': remoteName,
      if (remoteFileId == null) 'parents': ['appDataFolder'],
    };
    final bytes = await file.readAsBytes();
    final mimeType = _guessAttachmentMimeType(file.path);
    final boundary =
        'proper_notes_attachment_${DateTime.now().microsecondsSinceEpoch}';
    final body = _buildMultipartRelatedBody(
      boundary: boundary,
      metadataJson: json.encode(metadata),
      mediaMimeType: mimeType,
      mediaBytes: bytes,
    );
    final uri = remoteFileId == null
        ? Uri.parse(
            'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart',
          )
        : Uri.parse(
            'https://www.googleapis.com/upload/drive/v3/files/$remoteFileId?uploadType=multipart',
          );
    final response = await (remoteFileId == null
        ? _httpClient.post(
            uri,
            headers: {
              ...authHeaders,
              'Content-Type': 'multipart/related; boundary=$boundary',
            },
            body: body,
          )
        : _httpClient.patch(
            uri,
            headers: {
              ...authHeaders,
              'Content-Type': 'multipart/related; boundary=$boundary',
            },
            body: body,
          ));

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Failed to upload Drive attachment: ${response.body}');
    }
  }

  Future<String?> _findRemoteFileIdByName(
    String remoteName, {
    required Map<String, String> authHeaders,
  }) async {
    final response = await _httpClient.get(
      Uri.https('www.googleapis.com', '/drive/v3/files', {
        'spaces': 'appDataFolder',
        'q': "name = '${_escapeDriveQueryLiteral(remoteName)}'",
        'fields': 'files(id,name)',
        'pageSize': '1',
      }),
      headers: authHeaders,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to query Drive file: ${response.body}');
    }

    final payload = _decodeJsonResponse(response);
    final files = (payload['files'] as List<dynamic>? ?? const <dynamic>[])
        .cast<Map<String, dynamic>>();
    if (files.isEmpty) {
      return null;
    }

    return files.first['id'] as String?;
  }

  String _escapeDriveQueryLiteral(String value) {
    return value.replaceAll("'", "\\'");
  }

  String _guessAttachmentMimeType(String path) {
    final lowerPath = path.toLowerCase();
    if (lowerPath.endsWith('.png')) {
      return 'image/png';
    }
    if (lowerPath.endsWith('.jpg') || lowerPath.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lowerPath.endsWith('.gif')) {
      return 'image/gif';
    }
    if (lowerPath.endsWith('.webp')) {
      return 'image/webp';
    }
    return 'application/octet-stream';
  }

  Uint8List _buildMultipartRelatedBody({
    required String boundary,
    required String metadataJson,
    required String mediaMimeType,
    required Uint8List mediaBytes,
  }) {
    final builder = BytesBuilder();
    builder.add(utf8.encode('--$boundary\r\n'));
    builder.add(
        utf8.encode('Content-Type: application/json; charset=UTF-8\r\n\r\n'));
    builder.add(utf8.encode(metadataJson));
    builder.add(utf8.encode('\r\n--$boundary\r\n'));
    builder.add(utf8.encode('Content-Type: $mediaMimeType\r\n\r\n'));
    builder.add(mediaBytes);
    builder.add(utf8.encode('\r\n--$boundary--\r\n'));
    return builder.toBytes();
  }

  Future<String> _getDesktopAccessToken() async {
    final now = DateTime.now().toUtc();
    if (_desktopAccessToken != null &&
        _desktopAccessTokenExpiresAt != null &&
        now.isBefore(_desktopAccessTokenExpiresAt!)) {
      return _desktopAccessToken!;
    }

    final storedSession = await _sessionStore.read();
    final refreshToken = storedSession?.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      throw Exception('Sign in is required before sync can run.');
    }

    final tokenResponse = await _tokenClient.refreshAccessToken(
      clientId: _config.desktopClientId,
      clientSecret:
          _config.hasDesktopClientSecret ? _config.desktopClientSecret : null,
      refreshToken: refreshToken,
    );
    final accessToken = tokenResponse.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      throw Exception('Google token refresh did not return an access token.');
    }

    _desktopAccessToken = accessToken;
    _desktopAccessTokenExpiresAt = now
        .add(
          Duration(
            seconds: tokenResponse.expiresInSeconds ?? 3600,
          ),
        )
        .subtract(_desktopAccessTokenExpirySkew);

    return accessToken;
  }

  Future<String> _getStartPageToken({
    required Map<String, String> authHeaders,
  }) async {
    final response = await _httpClient.get(
      Uri.https('www.googleapis.com', '/drive/v3/changes/startPageToken', {
        'spaces': 'appDataFolder',
      }),
      headers: authHeaders,
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to get Drive start page token: ${response.body}',
      );
    }

    final payload = _decodeJsonResponse(response);
    final token = payload['startPageToken'] as String?;
    if (token == null || token.isEmpty) {
      throw Exception('Drive did not return a startPageToken.');
    }

    return token;
  }

  Future<RemoteNote> _fetchRemoteNoteByFileId({
    required String fileId,
    required Map<String, String> authHeaders,
  }) async {
    final contentResponse = await _httpClient.get(
      Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId?alt=media'),
      headers: authHeaders,
    );

    if (contentResponse.statusCode != 200) {
      throw Exception(
          'Failed to download Drive note $fileId: ${contentResponse.body}');
    }

    final jsonPayload = _decodeJsonResponse(contentResponse);
    return RemoteNote(
      id: jsonPayload['id'] as String,
      title: jsonPayload['title'] as String? ?? '',
      content: jsonPayload['content'] as String? ?? '',
      documentJson:
          legacyDocumentFromContent(jsonPayload['content'] as String? ?? ''),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        jsonPayload['created_at'] as int,
        isUtc: true,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        jsonPayload['updated_at'] as int,
        isUtc: true,
      ),
      deletedAt: (jsonPayload['deleted_at'] as int?) == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              jsonPayload['deleted_at'] as int,
              isUtc: true,
            ),
      contentHash: jsonPayload['content_hash'] as String,
      deviceId: jsonPayload['device_id'] as String,
      folderPath: jsonPayload['folder_path'] as String?,
      remoteFileId: fileId,
    );
  }

  Future<List<RemoteNote>> _fetchRemoteNotesByFileIds({
    required List<String> fileIds,
    required Map<String, String> authHeaders,
  }) async {
    final notes = <RemoteNote>[];

    for (var start = 0;
        start < fileIds.length;
        start += _remoteFetchBatchSize) {
      final end = (start + _remoteFetchBatchSize < fileIds.length)
          ? start + _remoteFetchBatchSize
          : fileIds.length;
      final batch = await Future.wait(
        fileIds.sublist(start, end).map(
              (fileId) => _fetchRemoteNoteByFileId(
                fileId: fileId,
                authHeaders: authHeaders,
              ),
            ),
      );
      notes.addAll(batch);
    }

    return notes;
  }

  Map<String, String> _authHeaders(String accessToken) {
    return <String, String>{
      'Authorization': 'Bearer $accessToken',
    };
  }

  Map<String, dynamic> _decodeJsonResponse(http.Response response) {
    final decodedBody = utf8.decode(response.bodyBytes);
    return json.decode(decodedBody) as Map<String, dynamic>;
  }

  String? _extractBearerToken(Map<String, String>? authHeaders) {
    final authorization = authHeaders?['Authorization'];
    if (authorization == null || !authorization.startsWith('Bearer ')) {
      return null;
    }

    return authorization.substring('Bearer '.length);
  }

  bool _isSupportedRemoteFile(Map<String, dynamic>? file) {
    final mimeType = file?['mimeType'] as String?;
    final name = file?['name'] as String?;

    if (mimeType == _remoteNoteMimeType ||
        mimeType == _legacyRemoteNoteMimeType) {
      return true;
    }

    if (name != null && name.startsWith('note_') && name.endsWith('.json')) {
      return true;
    }

    return false;
  }
}
