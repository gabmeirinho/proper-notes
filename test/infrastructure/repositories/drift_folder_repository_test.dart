import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proper_notes/core/utils/content_hash.dart';
import 'package:proper_notes/features/notes/domain/note.dart';
import 'package:proper_notes/features/notes/domain/folder_repository.dart';
import 'package:proper_notes/features/notes/domain/sync_status.dart';
import 'package:proper_notes/infrastructure/database/app_database.dart';
import 'package:proper_notes/infrastructure/repositories/drift_folder_repository.dart';
import 'package:proper_notes/infrastructure/repositories/drift_note_repository.dart';

void main() {
  late AppDatabase database;
  late DriftFolderRepository repository;
  late DriftNoteRepository noteRepository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = DriftFolderRepository(database);
    noteRepository = DriftNoteRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('createFolder persists nested folder segments', () async {
    await repository.createFolder('Projects/Proper Notes');

    final folders = await repository.watchFolders().first;

    expect(folders.map((folder) => folder.path), [
      'Projects',
      'Projects/Proper Notes',
    ]);
    expect(folders.last.parentPath, 'Projects');
  });

  test('deleteFolder removes an empty folder', () async {
    await repository.createFolder('Projects');

    final result = await repository.deleteFolder('Projects');
    final folders = await repository.watchFolders().first;

    expect(result, DeleteFolderResult.deleted);
    expect(folders, isEmpty);
  });

  test('getDeleteImpact reports nested folders', () async {
    await repository.createFolder('Projects/Proper Notes');

    final impact = await repository.getDeleteImpact('Projects');

    expect(impact?.childFolderCount, 1);
    expect(impact?.noteCount, 0);
  });

  test('getDeleteImpact reports notes in a folder subtree', () async {
    await noteRepository.create(
      _buildNote(
        id: 'note-1',
        title: 'Folder note',
        content: 'Inside Projects',
        folderPath: 'Projects',
      ),
    );

    final impact = await repository.getDeleteImpact('Projects');

    expect(impact?.noteCount, 1);
    expect(impact?.childFolderCount, 0);
  });

  test('recursive delete removes folder tree and soft-deletes contained notes',
      () async {
    await repository.createFolder('Projects/Proper Notes');
    await noteRepository.create(
      _buildNote(
        id: 'note-2',
        title: 'Nested note',
        content: 'Inside Projects/Proper Notes',
        folderPath: 'Projects/Proper Notes',
      ),
    );

    final result = await repository.deleteFolder('Projects', recursive: true);
    final folders = await repository.watchFolders().first;
    final deletedNotes =
        await noteRepository.watchDeletedNotes(folderPath: 'Projects').first;

    expect(result, DeleteFolderResult.deleted);
    expect(folders, isEmpty);
    expect(deletedNotes.map((note) => note.id), ['note-2']);
    expect(deletedNotes.single.syncStatus, SyncStatus.pendingDelete);
  });

  test('renameFolder moves the subtree and updates contained notes', () async {
    await repository.createFolder('Projects/Proper Notes');
    await noteRepository.create(
      _buildNote(
        id: 'note-3',
        title: 'Nested note',
        content: 'Inside Projects/Proper Notes',
        folderPath: 'Projects/Proper Notes',
      ),
    );

    final result =
        await repository.renameFolder('Projects', 'Archive/Projects');
    final folders = await repository.watchFolders().first;
    final movedNotes =
        await noteRepository.watchActiveNotes(folderPath: 'Archive').first;

    expect(result, RenameFolderResult.renamed);
    expect(
      folders.map((folder) => folder.path),
      ['Archive', 'Archive/Projects', 'Archive/Projects/Proper Notes'],
    );
    expect(movedNotes.single.folderPath, 'Archive/Projects/Proper Notes');
    expect(movedNotes.single.syncStatus, SyncStatus.pendingUpload);
  });

  test('renameFolder can move a folder into an existing parent folder',
      () async {
    await repository.createFolder('Archive');
    await repository.createFolder('Projects/Proper Notes');

    final result =
        await repository.renameFolder('Projects', 'Archive/Projects');
    final folders = await repository.watchFolders().first;
    final movedFolder = folders.singleWhere(
      (folder) => folder.path == 'Archive/Projects',
    );

    expect(result, RenameFolderResult.renamed);
    expect(
      folders.map((folder) => folder.path),
      ['Archive', 'Archive/Projects', 'Archive/Projects/Proper Notes'],
    );
    expect(movedFolder.parentPath, 'Archive');
  });

  test('renameFolder can move a nested folder to a different sibling branch',
      () async {
    await repository.createFolder('Main/as/adasdad');
    await repository.createFolder('Main/yo');

    final result = await repository.renameFolder(
      'Main/as/adasdad',
      'Main/yo/adasdad',
    );
    final folders = await repository.watchFolders().first;
    final movedFolder = folders.singleWhere(
      (folder) => folder.path == 'Main/yo/adasdad',
    );

    expect(result, RenameFolderResult.renamed);
    expect(
      folders.map((folder) => folder.path),
      ['Main', 'Main/as', 'Main/yo', 'Main/yo/adasdad'],
    );
    expect(movedFolder.parentPath, 'Main/yo');
  });
}

Note _buildNote({
  required String id,
  required String title,
  required String content,
  required String folderPath,
}) {
  final timestamp = DateTime.utc(2026, 3, 30, 10);

  return Note(
    id: id,
    title: title,
    content: content,
    createdAt: timestamp,
    updatedAt: timestamp,
    syncStatus: SyncStatus.pendingUpload,
    contentHash: computeContentHash(content),
    deviceId: 'test-device',
    folderPath: folderPath,
  );
}
