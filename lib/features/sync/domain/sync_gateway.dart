import '../../notes/domain/note.dart';
import 'remote_note.dart';

abstract interface class SyncGateway {
  Future<RemoteSyncBatch> bootstrap();
  Future<RemoteSyncBatch> fetchChangesSince(String token);
  Future<List<RemoteNote>> fetchAllNotes();
  Future<RemoteNote> upsertNote(Note note);
}

class RemoteSyncBatch {
  const RemoteSyncBatch({
    required this.notes,
    required this.nextToken,
    required this.isFullSnapshot,
  });

  final List<RemoteNote> notes;
  final String nextToken;
  final bool isFullSnapshot;
}
