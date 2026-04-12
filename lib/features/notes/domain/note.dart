import '../../../core/utils/note_document.dart';
import 'sync_status.dart';

class Note {
  const Note({
    required this.id,
    required this.title,
    required this.content,
    this.documentJson = '',
    required this.createdAt,
    required this.updatedAt,
    required this.syncStatus,
    required this.contentHash,
    required this.deviceId,
    this.folderPath,
    this.deletedAt,
    this.lastSyncedAt,
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
  final DateTime? lastSyncedAt;
  final SyncStatus syncStatus;
  final String contentHash;
  final String? baseContentHash;
  final String deviceId;
  final String? folderPath;
  final String? remoteFileId;
  final String? remoteEtag;

  bool get isDeleted => deletedAt != null;

  NoteDocument get document {
    return documentJson.isEmpty
        ? NoteDocument.legacyParagraph(content)
        : NoteDocument.fromJsonString(documentJson);
  }

  Note copyWith({
    String? id,
    String? title,
    String? content,
    String? documentJson,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    DateTime? lastSyncedAt,
    bool clearLastSyncedAt = false,
    SyncStatus? syncStatus,
    String? contentHash,
    String? baseContentHash,
    bool clearBaseContentHash = false,
    String? deviceId,
    String? folderPath,
    bool clearFolderPath = false,
    String? remoteFileId,
    bool clearRemoteFileId = false,
    String? remoteEtag,
    bool clearRemoteEtag = false,
  }) {
    return Note(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      documentJson: documentJson ?? this.documentJson,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
      lastSyncedAt:
          clearLastSyncedAt ? null : (lastSyncedAt ?? this.lastSyncedAt),
      syncStatus: syncStatus ?? this.syncStatus,
      contentHash: contentHash ?? this.contentHash,
      baseContentHash: clearBaseContentHash
          ? null
          : (baseContentHash ?? this.baseContentHash),
      deviceId: deviceId ?? this.deviceId,
      folderPath: clearFolderPath ? null : (folderPath ?? this.folderPath),
      remoteFileId:
          clearRemoteFileId ? null : (remoteFileId ?? this.remoteFileId),
      remoteEtag: clearRemoteEtag ? null : (remoteEtag ?? this.remoteEtag),
    );
  }
}
