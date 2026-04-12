import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../../features/auth/domain/sync_account_credentials.dart';
import 'webdav_models.dart';

class WebDavClient {
  WebDavClient({
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  Future<WebDavConnectionContext> resolveContext(
    SyncAccountCredentials credentials,
  ) async {
    final serverUri = Uri.parse(credentials.serverUrl.trim());
    final rootPath = credentials.remoteRoot.trim().isEmpty
        ? 'ProperNotes'
        : credentials.remoteRoot.trim();
    final normalizedBasePath =
        serverUri.path.endsWith('/') ? serverUri.path : '${serverUri.path}/';
    final normalizedRootPath =
        rootPath.startsWith('/') ? rootPath.substring(1) : rootPath;
    return WebDavConnectionContext(
      credentials: credentials,
      rootCollectionUri: serverUri.replace(
        path: '$normalizedBasePath$normalizedRootPath',
      ),
    );
  }

  Future<void> testConnection(SyncAccountCredentials credentials) async {
    final context = await resolveContext(credentials);
    final response = await _send(
      'PROPFIND',
      context.rootCollectionUri,
      headers: <String, String>{'Depth': '0'},
      credentials: credentials,
      allowMissingCollection: true,
    );

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw Exception('WebDAV authentication failed.');
    }
    if (response.statusCode >= 400 && response.statusCode != 404) {
      throw Exception(
        'WebDAV connection test failed: ${response.statusCode}',
      );
    }
  }

  Future<void> ensureCollection(
    WebDavConnectionContext context,
    String relativePath,
  ) async {
    final segments = relativePath
        .split('/')
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty);
    var current = context.rootCollectionUri;
    await _mkcol(current, credentials: context.credentials);
    for (final segment in segments) {
      current = current.replace(
        path:
            '${current.path.endsWith('/') ? current.path : '${current.path}/'}$segment',
      );
      await _mkcol(current, credentials: context.credentials);
    }
  }

  Future<WebDavDirectoryListing> propfindDirectory(
    WebDavConnectionContext context,
    String relativePath,
  ) async {
    final uri = context.childUri(relativePath);
    final response = await _send(
      'PROPFIND',
      uri,
      headers: <String, String>{'Depth': '1'},
      credentials: context.credentials,
    );

    if (response.statusCode >= 400) {
      throw Exception(
        'WebDAV PROPFIND failed for $relativePath: ${response.statusCode}',
      );
    }

    final document = XmlDocument.parse(utf8.decode(response.bodyBytes));
    final responses = document.descendants
        .whereType<XmlElement>()
        .where((node) => node.name.local.toLowerCase() == 'response');
    final entries = <WebDavFileEntry>[];
    String? collectionTag;

    for (final item in responses) {
      final href = item.childElements
          .where((node) => node.name.local.toLowerCase() == 'href')
          .map((node) => node.innerText.trim())
          .firstWhere((value) => value.isNotEmpty, orElse: () => '');
      if (href.isEmpty) {
        continue;
      }

      final decodedHref = Uri.decodeFull(href);
      if (decodedHref == uri.path || decodedHref == '${uri.path}/') {
        collectionTag = item.descendants
            .whereType<XmlElement>()
            .where((node) => node.name.local.toLowerCase() == 'getctag')
            .map((node) => node.innerText.trim())
            .firstWhere((value) => value.isNotEmpty,
                orElse: () => collectionTag ?? '');
        continue;
      }

      final etag = item.descendants
          .whereType<XmlElement>()
          .where((node) => node.name.local.toLowerCase() == 'getetag')
          .map((node) => node.innerText.trim())
          .firstWhere((value) => value.isNotEmpty, orElse: () => '');
      entries.add(
        WebDavFileEntry(
          href: decodedHref,
          path: decodedHref.split('/').where((part) => part.isNotEmpty).last,
          etag: etag.isEmpty ? null : etag,
        ),
      );
    }

    return WebDavDirectoryListing(
      entries: entries,
      collectionTag: collectionTag,
    );
  }

  Future<Map<String, dynamic>> getJson(
    WebDavConnectionContext context,
    String relativePath,
  ) async {
    final response = await _send(
      'GET',
      context.childUri(relativePath),
      credentials: context.credentials,
    );
    if (response.statusCode >= 400) {
      throw Exception(
        'WebDAV GET failed for $relativePath: ${response.statusCode}',
      );
    }
    return json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  Future<WebDavWriteResult> putJson(
    WebDavConnectionContext context,
    String relativePath,
    Map<String, dynamic> payload,
  ) async {
    final response = await _send(
      'PUT',
      context.childUri(relativePath),
      credentials: context.credentials,
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8'
      },
      body: json.encode(payload),
    );
    if (response.statusCode >= 400) {
      throw Exception(
        'WebDAV PUT failed for $relativePath: ${response.statusCode}',
      );
    }
    return WebDavWriteResult(
      etag: _responseHeader(response, 'etag'),
    );
  }

  Future<void> putBytes(
    WebDavConnectionContext context,
    String relativePath,
    List<int> bytes,
  ) async {
    final response = await _send(
      'PUT',
      context.childUri(relativePath),
      credentials: context.credentials,
      bodyBytes: bytes,
    );
    if (response.statusCode >= 400) {
      throw Exception(
        'WebDAV attachment upload failed for $relativePath: ${response.statusCode}',
      );
    }
  }

  Future<List<int>> getBytes(
    WebDavConnectionContext context,
    String relativePath,
  ) async {
    final response = await _send(
      'GET',
      context.childUri(relativePath),
      credentials: context.credentials,
    );
    if (response.statusCode >= 400) {
      throw Exception(
        'WebDAV attachment download failed for $relativePath: ${response.statusCode}',
      );
    }
    return response.bodyBytes;
  }

  Future<void> deleteIfExists(
    WebDavConnectionContext context,
    String relativePath,
  ) async {
    final response = await _send(
      'DELETE',
      context.childUri(relativePath),
      credentials: context.credentials,
      allowMissingCollection: true,
    );
    if (response.statusCode >= 400 && response.statusCode != 404) {
      throw Exception(
        'WebDAV DELETE failed for $relativePath: ${response.statusCode}',
      );
    }
  }

  Future<void> _mkcol(
    Uri uri, {
    required SyncAccountCredentials credentials,
  }) async {
    final response = await _send(
      'MKCOL',
      uri,
      credentials: credentials,
      allowMissingCollection: true,
    );
    if (response.statusCode == 201 ||
        response.statusCode == 405 ||
        response.statusCode == 301 ||
        response.statusCode == 302) {
      return;
    }
    if (response.statusCode >= 400 && response.statusCode != 409) {
      throw Exception('WebDAV MKCOL failed: ${response.statusCode}');
    }
  }

  Future<http.Response> _send(
    String method,
    Uri uri, {
    required SyncAccountCredentials credentials,
    Map<String, String>? headers,
    String? body,
    List<int>? bodyBytes,
    bool allowMissingCollection = false,
  }) async {
    final stopwatch = Stopwatch()..start();
    final request = http.Request(method, uri);
    request.headers.addAll(<String, String>{
      'Authorization': _basicAuth(credentials),
      if (headers != null) ...headers,
    });
    if (bodyBytes != null) {
      request.bodyBytes = bodyBytes;
    } else if (body != null) {
      request.body = body;
    }
    try {
      final streamed = await _httpClient.send(request);
      final response = await http.Response.fromStream(streamed);
      _logRequest(
        method: method,
        uri: uri,
        statusCode: response.statusCode,
        elapsed: stopwatch.elapsed,
      );
      if (!allowMissingCollection &&
          (response.statusCode == 401 || response.statusCode == 403)) {
        throw Exception('WebDAV authentication failed.');
      }
      return response;
    } catch (error) {
      _logRequest(
        method: method,
        uri: uri,
        statusCode: null,
        elapsed: stopwatch.elapsed,
        error: error,
      );
      rethrow;
    }
  }

  String _basicAuth(SyncAccountCredentials credentials) {
    final raw = '${credentials.username}:${credentials.password}';
    return 'Basic ${base64.encode(utf8.encode(raw))}';
  }

  String? _responseHeader(http.Response response, String name) {
    for (final entry in response.headers.entries) {
      if (entry.key.toLowerCase() == name.toLowerCase()) {
        return entry.value;
      }
    }
    return null;
  }

  void _logRequest({
    required String method,
    required Uri uri,
    required Duration elapsed,
    int? statusCode,
    Object? error,
  }) {
    if (!kDebugMode) {
      return;
    }

    final elapsedMs = elapsed.inMilliseconds;
    final path = uri.path;
    if (error != null) {
      debugPrint('[WebDAV] $method $path failed in ${elapsedMs}ms: $error');
      return;
    }

    debugPrint('[WebDAV] $method $path -> $statusCode in ${elapsedMs}ms');
  }
}
