import 'package:drift/drift.dart';

import '../../features/notes/domain/folder.dart';
import '../../features/notes/domain/folder_repository.dart';
import '../../features/notes/domain/sync_status.dart';
import '../database/app_database.dart';

class DriftFolderRepository implements FolderRepository {
  DriftFolderRepository(this._database);

  final AppDatabase _database;

  @override
  Future<void> createFolder(String path) async {
    final normalizedPath = _normalizePath(path);
    if (normalizedPath.isEmpty) {
      return;
    }

    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final segments = normalizedPath.split('/');

    for (var depth = 0; depth < segments.length; depth++) {
      final currentPath = segments.take(depth + 1).join('/');
      final parentPath = depth == 0 ? null : segments.take(depth).join('/');

      await _database.into(_database.foldersTable).insertOnConflictUpdate(
            FoldersTableCompanion(
              path: Value(currentPath),
              parentPath: Value(parentPath),
              createdAt: Value(now),
            ),
          );
    }
  }

  @override
  Future<void> ensureFolderExists(String path) async {
    await createFolder(path);
  }

  @override
  Future<RenameFolderResult> renameFolder(
      String oldPath, String newPath) async {
    final normalizedOldPath = _normalizePath(oldPath);
    final normalizedNewPath = _normalizePath(newPath);
    if (normalizedOldPath.isEmpty || normalizedNewPath.isEmpty) {
      return RenameFolderResult.invalidDestination;
    }

    if (normalizedOldPath == normalizedNewPath) {
      return RenameFolderResult.renamed;
    }

    if (normalizedNewPath.startsWith('$normalizedOldPath/')) {
      return RenameFolderResult.invalidDestination;
    }

    final existingFolder = await (_database.select(_database.foldersTable)
          ..where((tbl) => tbl.path.equals(normalizedOldPath)))
        .getSingleOrNull();
    if (existingFolder == null) {
      return RenameFolderResult.notFound;
    }

    final destinationConflict = await (_database.select(_database.foldersTable)
          ..where(
            (tbl) =>
                tbl.path.equals(normalizedNewPath) |
                tbl.path.like('$normalizedNewPath/%'),
          ))
        .getSingleOrNull();
    if (destinationConflict != null) {
      return RenameFolderResult.destinationExists;
    }

    await _database.transaction(() async {
      await _ensureAncestorFoldersExist(normalizedNewPath);

      final subtreeRows = await (_database.select(_database.foldersTable)
            ..where(
              (tbl) =>
                  tbl.path.equals(normalizedOldPath) |
                  tbl.path.like('$normalizedOldPath/%'),
            ))
          .get();

      final mappedFolders = subtreeRows
          .map(
            (row) => FoldersTableCompanion(
              path: Value(_remapFolderPath(
                row.path,
                oldPrefix: normalizedOldPath,
                newPrefix: normalizedNewPath,
              )),
              parentPath: Value(
                row.path == normalizedOldPath || row.parentPath == null
                    ? _parentPathFor(normalizedNewPath)
                    : _remapFolderPath(
                        row.parentPath!,
                        oldPrefix: normalizedOldPath,
                        newPrefix: normalizedNewPath,
                      ),
              ),
              createdAt: Value(row.createdAt),
            ),
          )
          .toList(growable: false);

      final affectedNotes = await (_database.select(_database.notesTable)
            ..where(
              (tbl) =>
                  tbl.folderPath.equals(normalizedOldPath) |
                  tbl.folderPath.like('$normalizedOldPath/%'),
            ))
          .get();
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      for (final note in affectedNotes) {
        final nextFolderPath = _remapFolderPath(
          note.folderPath!,
          oldPrefix: normalizedOldPath,
          newPrefix: normalizedNewPath,
        );
        final nextSyncStatus = note.syncStatus == SyncStatus.pendingDelete.name
            ? SyncStatus.pendingDelete.name
            : SyncStatus.pendingUpload.name;
        await (_database.update(_database.notesTable)
              ..where((tbl) => tbl.id.equals(note.id)))
            .write(
          NotesTableCompanion(
            folderPath: Value(nextFolderPath),
            updatedAt: Value(now),
            deviceId: Value(note.deviceId),
            syncStatus: Value(nextSyncStatus),
          ),
        );
      }

      await (_database.delete(_database.foldersTable)
            ..where(
              (tbl) =>
                  tbl.path.equals(normalizedOldPath) |
                  tbl.path.like('$normalizedOldPath/%'),
            ))
          .go();

      for (final folder in mappedFolders) {
        await _database
            .into(_database.foldersTable)
            .insertOnConflictUpdate(folder);
      }
    });

    return RenameFolderResult.renamed;
  }

  @override
  Future<FolderDeleteImpact?> getDeleteImpact(String path) async {
    final normalizedPath = _normalizePath(path);
    if (normalizedPath.isEmpty) {
      return null;
    }

    final existingFolder = await (_database.select(_database.foldersTable)
          ..where((tbl) => tbl.path.equals(normalizedPath)))
        .getSingleOrNull();
    if (existingFolder == null) {
      return null;
    }

    final childFolderCount = await (_database.selectOnly(_database.foldersTable)
          ..addColumns([_database.foldersTable.path.count()])
          ..where(_database.foldersTable.path.like('$normalizedPath/%')))
        .map((row) => row.read(_database.foldersTable.path.count()) ?? 0)
        .getSingle();

    final noteCount = await (_database.selectOnly(_database.notesTable)
          ..addColumns([_database.notesTable.id.count()])
          ..where(
            _database.notesTable.folderPath.equals(normalizedPath) |
                _database.notesTable.folderPath.like('$normalizedPath/%'),
          ))
        .map((row) => row.read(_database.notesTable.id.count()) ?? 0)
        .getSingle();

    return FolderDeleteImpact(
      noteCount: noteCount,
      childFolderCount: childFolderCount,
    );
  }

  @override
  Future<DeleteFolderResult> deleteFolder(
    String path, {
    bool recursive = false,
  }) async {
    final normalizedPath = _normalizePath(path);
    if (normalizedPath.isEmpty) {
      return DeleteFolderResult.notFound;
    }

    final impact = await getDeleteImpact(normalizedPath);
    if (impact == null) {
      return DeleteFolderResult.notFound;
    }

    if (!recursive && !impact.isEmpty) {
      return DeleteFolderResult.notFound;
    }

    await _database.transaction(() async {
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;

      await (_database.update(_database.notesTable)
            ..where(
              (tbl) =>
                  tbl.deletedAt.isNull() &
                  (tbl.folderPath.equals(normalizedPath) |
                      tbl.folderPath.like('$normalizedPath/%')),
            ))
          .write(
        NotesTableCompanion(
          deletedAt: Value(now),
          syncStatus: Value(SyncStatus.pendingDelete.name),
        ),
      );

      await (_database.delete(_database.foldersTable)
            ..where(
              (tbl) =>
                  tbl.path.equals(normalizedPath) |
                  tbl.path.like('$normalizedPath/%'),
            ))
          .go();
    });

    return DeleteFolderResult.deleted;
  }

  @override
  Stream<List<Folder>> watchFolders() {
    final query = _database.select(_database.foldersTable)
      ..orderBy([
        (tbl) => OrderingTerm.asc(tbl.path),
      ]);

    return query.watch().map(
          (rows) => rows.map(_fromRow).toList(growable: false),
        );
  }

  Folder _fromRow(FoldersTableData row) {
    return Folder(
      path: row.path,
      parentPath: row.parentPath,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(row.createdAt, isUtc: true),
    );
  }

  String _normalizePath(String rawPath) {
    final segments = rawPath
        .split('/')
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);

    return segments.join('/');
  }

  Future<void> _ensureAncestorFoldersExist(String path) async {
    final segments = path.split('/');
    if (segments.length <= 1) {
      return;
    }

    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    for (var depth = 0; depth < segments.length - 1; depth++) {
      final currentPath = segments.take(depth + 1).join('/');
      final parentPath = depth == 0 ? null : segments.take(depth).join('/');
      await _database.into(_database.foldersTable).insertOnConflictUpdate(
            FoldersTableCompanion(
              path: Value(currentPath),
              parentPath: Value(parentPath),
              createdAt: Value(now),
            ),
          );
    }
  }

  String? _parentPathFor(String path) {
    final segments = path.split('/');
    if (segments.length <= 1) {
      return null;
    }

    return segments.take(segments.length - 1).join('/');
  }

  String _remapFolderPath(
    String source, {
    required String oldPrefix,
    required String newPrefix,
  }) {
    if (source == oldPrefix) {
      return newPrefix;
    }

    final suffix = source.substring(oldPrefix.length);
    return '$newPrefix$suffix';
  }
}
