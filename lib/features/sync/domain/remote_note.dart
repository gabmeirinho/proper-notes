class RemoteNote {
  const RemoteNote({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    required this.contentHash,
    required this.deviceId,
    this.deletedAt,
    this.remoteFileId,
  });

  final String id;
  final String title;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String contentHash;
  final String deviceId;
  final String? remoteFileId;
}
