import 'note.dart';
import '../../sync/domain/remote_note.dart';

abstract interface class NoteRepository {
  Stream<List<Note>> watchActiveNotes({String? folderPath});
  Stream<List<Note>> watchDeletedNotes({String? folderPath});
  Future<List<Note>> searchNotes(String query, {String? folderPath});
  Future<int> countAttachmentReferences(String attachmentUri);
  Future<List<Note>> getActiveNotesForSync();
  Future<List<Note>> getDeletedNotesForSync();
  Future<List<Note>> getPendingNotesForSync();
  Future<List<Note>> getByIds(Iterable<String> ids);
  Future<Map<String, String?>> getRemoteEtagsByPath();
  Future<Note?> getById(String id);
  Future<void> create(Note note);
  Future<void> update(Note note);
  Future<void> softDelete(String id, DateTime deletedAt);
  Future<void> restore(String id);
  Future<void> markSynced({
    required String id,
    required DateTime syncedAt,
    required String baseContentHash,
    String? remoteFileId,
    String? remoteEtag,
  });
  Future<void> upsertRemoteNote(RemoteNote remoteNote);
  Future<void> markConflict(String id);
  Future<void> applyRemoteDeletion(RemoteNote remoteNote);
}
