import '../domain/note_repository.dart';

class RestoreNote {
  RestoreNote({
    required NoteRepository repository,
  }) : _repository = repository;

  final NoteRepository _repository;

  Future<void> call(String id) {
    return _repository.restore(id);
  }
}
