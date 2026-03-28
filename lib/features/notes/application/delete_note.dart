import '../domain/note_repository.dart';

class DeleteNote {
  DeleteNote({
    required NoteRepository repository,
  }) : _repository = repository;

  final NoteRepository _repository;

  Future<void> call(String id) {
    return _repository.softDelete(id, DateTime.now().toUtc());
  }
}
