import '../domain/folder_repository.dart';

class DeleteFolder {
  const DeleteFolder({
    required FolderRepository repository,
  }) : _repository = repository;

  final FolderRepository _repository;

  Future<FolderDeleteImpact?> getDeleteImpact(String path) {
    return _repository.getDeleteImpact(path);
  }

  Future<DeleteFolderResult> call(String path, {bool recursive = false}) {
    return _repository.deleteFolder(path, recursive: recursive);
  }
}
