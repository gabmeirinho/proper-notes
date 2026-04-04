import '../domain/folder_repository.dart';

class RenameFolder {
  const RenameFolder({
    required FolderRepository repository,
  }) : _repository = repository;

  final FolderRepository _repository;

  Future<RenameFolderResult> call(String oldPath, String newPath) {
    return _repository.renameFolder(oldPath, newPath);
  }
}
