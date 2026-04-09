import '../domain/note_repository.dart';
import '../domain/sync_status.dart';

class PrepareAllNotesForSync {
  PrepareAllNotesForSync({
    required NoteRepository repository,
  }) : _repository = repository;

  final NoteRepository _repository;

  Future<int> call() async {
    final notes = await _repository.getActiveNotesForSync();
    var preparedCount = 0;

    for (final note in notes) {
      if (note.syncStatus == SyncStatus.pendingUpload) {
        continue;
      }

      await _repository.update(
        note.copyWith(
          syncStatus: SyncStatus.pendingUpload,
        ),
      );
      preparedCount += 1;
    }

    return preparedCount;
  }
}
