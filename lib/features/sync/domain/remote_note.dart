class RemoteNote {
  const RemoteNote({
    required this.id,
    required this.title,
    required this.content,
    this.documentJson = '',
    required this.createdAt,
    required this.updatedAt,
    required this.contentHash,
    required this.deviceId,
    this.folderPath,
    this.deletedAt,
    this.baseContentHash,
    this.remoteFileId,
    this.remoteEtag,
  });

  final String id;
  final String title;
  final String content;
  final String documentJson;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String contentHash;
  final String? baseContentHash;
  final String deviceId;
  final String? folderPath;
  final String? remoteFileId;
  final String? remoteEtag;
}
