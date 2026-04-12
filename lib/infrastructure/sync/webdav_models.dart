import '../../features/auth/domain/sync_account_credentials.dart';

class WebDavDirectoryListing {
  const WebDavDirectoryListing({
    required this.entries,
    this.collectionTag,
  });

  final List<WebDavFileEntry> entries;
  final String? collectionTag;
}

class WebDavWriteResult {
  const WebDavWriteResult({
    this.etag,
  });

  final String? etag;
}

class WebDavFileEntry {
  const WebDavFileEntry({
    required this.href,
    required this.path,
    this.etag,
  });

  final String href;
  final String path;
  final String? etag;
}

class WebDavConnectionContext {
  const WebDavConnectionContext({
    required this.credentials,
    required this.rootCollectionUri,
  });

  final SyncAccountCredentials credentials;
  final Uri rootCollectionUri;

  Uri childUri(String relativePath) {
    final normalizedRoot = rootCollectionUri.path.endsWith('/')
        ? rootCollectionUri.path
        : '${rootCollectionUri.path}/';
    final normalizedChild =
        relativePath.startsWith('/') ? relativePath.substring(1) : relativePath;
    return rootCollectionUri.replace(path: '$normalizedRoot$normalizedChild');
  }
}
