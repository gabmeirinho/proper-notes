import '../domain/note.dart';
import '../domain/note_repository.dart';

class SearchNotes {
  SearchNotes({
    required NoteRepository repository,
  }) : _repository = repository;

  final NoteRepository _repository;

  Future<List<Note>> call(String query, {String? folderPath}) {
    return _repository.searchNotes(query, folderPath: folderPath);
  }
}
