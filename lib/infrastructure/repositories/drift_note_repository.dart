import 'package:drift/drift.dart';

import '../../core/utils/note_document.dart';
import '../../features/notes/domain/note.dart';
import '../../features/notes/domain/note_repository.dart';
import '../../features/notes/domain/sync_status.dart';
import '../../features/sync/domain/remote_note.dart';
import '../database/app_database.dart';

class DriftNoteRepository implements NoteRepository {
  DriftNoteRepository(this._database);

  final AppDatabase _database;

  @override
  Future<void> create(Note note) async {
    await _ensureFolderPathExists(note.folderPath);
    await _database.into(_database.notesTable).insert(_toCompanion(note));
  }

  @override
  Future<Note?> getById(String id) async {
    final row = await (_database.select(_database.notesTable)
          ..where((tbl) => tbl.id.equals(id)))
        .getSingleOrNull();

    if (row == null) {
      return null;
    }

    return _fromRow(row);
  }

  @override
  Future<List<Note>> getActiveNotesForSync() async {
    final rows = await (_database.select(_database.notesTable)
          ..where((tbl) => tbl.deletedAt.isNull()))
        .get();

    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<List<Note>> getDeletedNotesForSync() async {
    final rows = await (_database.select(_database.notesTable)
          ..where((tbl) => tbl.deletedAt.isNotNull()))
        .get();

    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<void> applyRemoteDeletion(RemoteNote remoteNote) async {
    final existing = await getById(remoteNote.id);
    final deletedAt = remoteNote.deletedAt ?? DateTime.now().toUtc();
    final syncedAt = DateTime.now().toUtc();

    if (existing == null) {
      final tombstone = Note(
        id: remoteNote.id,
        title: remoteNote.title,
        content: remoteNote.content,
        documentJson: legacyDocumentFromContent(remoteNote.content),
        createdAt: remoteNote.createdAt,
        updatedAt: remoteNote.updatedAt,
        deletedAt: deletedAt,
        lastSyncedAt: syncedAt,
        syncStatus: SyncStatus.synced,
        contentHash: remoteNote.contentHash,
        baseContentHash: remoteNote.contentHash,
        deviceId: remoteNote.deviceId,
        folderPath: remoteNote.folderPath,
        remoteFileId: remoteNote.remoteFileId,
      );
      await create(tombstone);
      return;
    }

    final updated = existing.copyWith(
      title: remoteNote.title,
      content: remoteNote.content,
      updatedAt: remoteNote.updatedAt,
      deletedAt: deletedAt,
      lastSyncedAt: syncedAt,
      syncStatus: SyncStatus.synced,
      contentHash: remoteNote.contentHash,
      baseContentHash: remoteNote.contentHash,
      deviceId: remoteNote.deviceId,
      folderPath: remoteNote.folderPath,
      remoteFileId: remoteNote.remoteFileId,
    );
    await update(updated);
  }

  @override
  Future<void> markConflict(String id) async {
    await (_database.update(_database.notesTable)
          ..where((tbl) => tbl.id.equals(id)))
        .write(
      NotesTableCompanion(
        syncStatus: Value(SyncStatus.conflicted.name),
      ),
    );
  }

  @override
  Future<void> markSynced({
    required String id,
    required DateTime syncedAt,
    required String baseContentHash,
    String? remoteFileId,
  }) async {
    await (_database.update(_database.notesTable)
          ..where((tbl) => tbl.id.equals(id)))
        .write(
      NotesTableCompanion(
        lastSyncedAt: Value(syncedAt.millisecondsSinceEpoch),
        baseContentHash: Value(baseContentHash),
        remoteFileId: Value(remoteFileId),
        syncStatus: Value(SyncStatus.synced.name),
      ),
    );
  }

  @override
  Future<void> restore(String id) async {
    await (_database.update(_database.notesTable)
          ..where((tbl) => tbl.id.equals(id)))
        .write(
      NotesTableCompanion(
        deletedAt: const Value(null),
        syncStatus: Value(SyncStatus.pendingUpload.name),
      ),
    );
  }

  @override
  Future<List<Note>> searchNotes(String query, {String? folderPath}) async {
    final pattern = '%${query.trim()}%';

    final rows = await (_database.select(_database.notesTable)
          ..where(
            (tbl) =>
                tbl.deletedAt.isNull() &
                _folderFilter(tbl, folderPath) &
                (tbl.title.like(pattern) | tbl.content.like(pattern)),
          )
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.updatedAt)]))
        .get();

    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<void> softDelete(String id, DateTime deletedAt) async {
    await (_database.update(_database.notesTable)
          ..where((tbl) => tbl.id.equals(id)))
        .write(
      NotesTableCompanion(
        deletedAt: Value(deletedAt.millisecondsSinceEpoch),
        syncStatus: Value(SyncStatus.pendingDelete.name),
      ),
    );
  }

  @override
  Future<void> update(Note note) async {
    await _ensureFolderPathExists(note.folderPath);
    await (_database.update(_database.notesTable)
          ..where((tbl) => tbl.id.equals(note.id)))
        .write(_toCompanion(note));
  }

  @override
  Future<void> upsertRemoteNote(RemoteNote remoteNote) async {
    final syncedAt = DateTime.now().toUtc();
    final syncedNote = Note(
      id: remoteNote.id,
      title: remoteNote.title,
      content: remoteNote.content,
      documentJson: legacyDocumentFromContent(remoteNote.content),
      createdAt: remoteNote.createdAt,
      updatedAt: remoteNote.updatedAt,
      deletedAt: remoteNote.deletedAt,
      lastSyncedAt: syncedAt,
      syncStatus: SyncStatus.synced,
      contentHash: remoteNote.contentHash,
      baseContentHash: remoteNote.contentHash,
      deviceId: remoteNote.deviceId,
      folderPath: remoteNote.folderPath,
      remoteFileId: remoteNote.remoteFileId,
    );

    final existing = await getById(remoteNote.id);
    if (existing == null) {
      await create(syncedNote);
      return;
    }

    await update(syncedNote);
  }

  @override
  Stream<List<Note>> watchActiveNotes({String? folderPath}) {
    final query = _database.select(_database.notesTable)
      ..where((tbl) => tbl.deletedAt.isNull() & _folderFilter(tbl, folderPath))
      ..orderBy([(tbl) => OrderingTerm.desc(tbl.updatedAt)]);

    return query.watch().map(
          (rows) => rows.map(_fromRow).toList(growable: false),
        );
  }

  @override
  Stream<List<Note>> watchDeletedNotes({String? folderPath}) {
    final query = _database.select(_database.notesTable)
      ..where(
          (tbl) => tbl.deletedAt.isNotNull() & _folderFilter(tbl, folderPath))
      ..orderBy([(tbl) => OrderingTerm.desc(tbl.deletedAt)]);

    return query.watch().map(
          (rows) => rows.map(_fromRow).toList(growable: false),
        );
  }

  Note _fromRow(NotesTableData row) {
    return Note(
      id: row.id,
      title: row.title,
      content: row.content,
      documentJson: row.documentJson.isEmpty
          ? legacyDocumentFromContent(row.content)
          : row.documentJson,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(row.createdAt, isUtc: true),
      updatedAt:
          DateTime.fromMillisecondsSinceEpoch(row.updatedAt, isUtc: true),
      deletedAt: row.deletedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row.deletedAt!, isUtc: true),
      lastSyncedAt: row.lastSyncedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row.lastSyncedAt!, isUtc: true),
      syncStatus: SyncStatus.values.byName(row.syncStatus),
      contentHash: row.contentHash,
      baseContentHash: row.baseContentHash,
      deviceId: row.deviceId,
      folderPath: row.folderPath,
      remoteFileId: row.remoteFileId,
    );
  }

  NotesTableCompanion _toCompanion(Note note) {
    return NotesTableCompanion(
      id: Value(note.id),
      title: Value(note.title),
      content: Value(note.content),
      documentJson: Value(
        note.documentJson.isEmpty
            ? legacyDocumentFromContent(note.content)
            : note.documentJson,
      ),
      createdAt: Value(note.createdAt.millisecondsSinceEpoch),
      updatedAt: Value(note.updatedAt.millisecondsSinceEpoch),
      deletedAt: Value(note.deletedAt?.millisecondsSinceEpoch),
      lastSyncedAt: Value(note.lastSyncedAt?.millisecondsSinceEpoch),
      syncStatus: Value(note.syncStatus.name),
      contentHash: Value(note.contentHash),
      baseContentHash: Value(note.baseContentHash),
      deviceId: Value(note.deviceId),
      folderPath: Value(note.folderPath),
      remoteFileId: Value(note.remoteFileId),
    );
  }

  Expression<bool> _folderFilter($NotesTableTable tbl, String? folderPath) {
    if (folderPath == null) {
      return const Constant(true);
    }

    return tbl.folderPath.equals(folderPath) |
        tbl.folderPath.like('$folderPath/%');
  }

  Future<void> _ensureFolderPathExists(String? folderPath) async {
    if (folderPath == null || folderPath.trim().isEmpty) {
      return;
    }

    final normalizedSegments = folderPath
        .split('/')
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (normalizedSegments.isEmpty) {
      return;
    }

    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    for (var depth = 0; depth < normalizedSegments.length; depth++) {
      final currentPath = normalizedSegments.take(depth + 1).join('/');
      final parentPath =
          depth == 0 ? null : normalizedSegments.take(depth).join('/');
      await _database.into(_database.foldersTable).insertOnConflictUpdate(
            FoldersTableCompanion(
              path: Value(currentPath),
              parentPath: Value(parentPath),
              createdAt: Value(now),
            ),
          );
    }
  }
}
