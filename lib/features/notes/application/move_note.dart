import '../domain/note.dart';
import '../domain/note_repository.dart';
import '../domain/sync_status.dart';

class MoveNote {
  MoveNote({
    required NoteRepository repository,
    required String deviceId,
  })  : _repository = repository,
        _deviceId = deviceId;

  final NoteRepository _repository;
  final String _deviceId;

  Future<Note> call({
    required Note original,
    required String? folderPath,
  }) async {
    final now = DateTime.now().toUtc();
    final preservedBaseContentHash =
        original.baseContentHash ??
        (original.syncStatus == SyncStatus.synced ? original.contentHash : null);
    final movedNote = original.copyWith(
      updatedAt: now,
      baseContentHash: preservedBaseContentHash,
      deviceId: _deviceId,
      folderPath: folderPath,
      clearFolderPath: folderPath == null,
      syncStatus: original.syncStatus == SyncStatus.pendingDelete
          ? SyncStatus.pendingDelete
          : SyncStatus.pendingUpload,
    );

    await _repository.update(movedNote);
    return movedNote;
  }
}
