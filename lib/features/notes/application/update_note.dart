import '../../../core/utils/content_hash.dart';
import '../../../core/utils/note_document.dart';
import '../domain/note.dart';
import '../domain/note_repository.dart';
import '../domain/sync_status.dart';

class UpdateNote {
  UpdateNote({
    required NoteRepository repository,
    required String deviceId,
  })  : _repository = repository,
        _deviceId = deviceId;

  final NoteRepository _repository;
  final String _deviceId;

  Future<Note> call({
    required Note original,
    required String title,
    required String content,
    String? folderPath,
  }) async {
    final now = DateTime.now().toUtc();
    final updatedNote = original.copyWith(
      title: title,
      content: content,
      documentJson: documentJsonFromEditableText(content),
      updatedAt: now,
      contentHash: computeContentHash(content),
      syncStatus: SyncStatus.pendingUpload,
      deviceId: _deviceId,
      folderPath: folderPath ?? original.folderPath,
      clearDeletedAt: true,
    );

    await _repository.update(updatedNote);
    return updatedNote;
  }
}
