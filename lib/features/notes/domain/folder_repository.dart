import 'folder.dart';

class FolderDeleteImpact {
  const FolderDeleteImpact({
    required this.noteCount,
    required this.childFolderCount,
  });

  final int noteCount;
  final int childFolderCount;

  bool get isEmpty => noteCount == 0 && childFolderCount == 0;
}

enum RenameFolderResult {
  renamed,
  notFound,
  invalidDestination,
  destinationExists,
}

enum DeleteFolderResult {
  deleted,
  notFound,
}

abstract interface class FolderRepository {
  Stream<List<Folder>> watchFolders();
  Future<void> createFolder(String path);
  Future<void> ensureFolderExists(String path);
  Future<RenameFolderResult> renameFolder(String oldPath, String newPath);
  Future<FolderDeleteImpact?> getDeleteImpact(String path);
  Future<DeleteFolderResult> deleteFolder(String path,
      {bool recursive = false});
}
