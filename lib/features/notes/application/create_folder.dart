import '../domain/folder_repository.dart';

class CreateFolder {
  const CreateFolder({
    required FolderRepository repository,
  }) : _repository = repository;

  final FolderRepository _repository;

  Future<void> call(String path) async {
    await _repository.createFolder(path);
  }
}
