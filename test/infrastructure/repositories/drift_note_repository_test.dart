import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proper_notes/core/utils/content_hash.dart';
import 'package:proper_notes/core/utils/note_document.dart';
import 'package:proper_notes/features/notes/domain/note.dart';
import 'package:proper_notes/features/notes/domain/sync_status.dart';
import 'package:proper_notes/infrastructure/database/app_database.dart';
import 'package:proper_notes/infrastructure/repositories/drift_note_repository.dart';

void main() {
  late AppDatabase database;
  late DriftNoteRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = DriftNoteRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('create and getById persist a note', () async {
    final note = _buildNote(
      id: 'note-1',
      title: 'First note',
      content: 'Hello local-first world',
      updatedAt: DateTime.utc(2026, 3, 24, 10),
    );

    await repository.create(note);

    final stored = await repository.getById(note.id);

    expect(stored, isNotNull);
    expect(stored!.id, note.id);
    expect(stored.title, 'First note');
    expect(stored.content, 'Hello local-first world');
    expect(
      stored.documentJson,
      legacyDocumentFromContent('Hello local-first world'),
    );
    expect(stored.syncStatus, SyncStatus.pendingUpload);
    expect(stored.contentHash, computeContentHash('Hello local-first world'));
  });

  test('watchActiveNotes orders notes by updatedAt descending', () async {
    final older = _buildNote(
      id: 'note-older',
      title: 'Older',
      content: 'old content',
      updatedAt: DateTime.utc(2026, 3, 24, 9),
    );
    final newer = _buildNote(
      id: 'note-newer',
      title: 'Newer',
      content: 'new content',
      updatedAt: DateTime.utc(2026, 3, 24, 11),
    );

    await repository.create(older);
    await repository.create(newer);

    final notes = await repository.watchActiveNotes().first;

    expect(notes.map((note) => note.id), ['note-newer', 'note-older']);
  });

  test('update changes persisted note fields', () async {
    final original = _buildNote(
      id: 'note-2',
      title: 'Draft',
      content: 'Initial content',
      updatedAt: DateTime.utc(2026, 3, 24, 10),
    );
    await repository.create(original);

    final updated = original.copyWith(
      title: 'Final',
      content: 'Updated content',
      documentJson: legacyDocumentFromContent('Updated content'),
      updatedAt: DateTime.utc(2026, 3, 24, 12),
      contentHash: computeContentHash('Updated content'),
    );

    await repository.update(updated);

    final stored = await repository.getById(updated.id);

    expect(stored, isNotNull);
    expect(stored!.title, 'Final');
    expect(stored.content, 'Updated content');
    expect(stored.documentJson, legacyDocumentFromContent('Updated content'));
    expect(stored.updatedAt, DateTime.utc(2026, 3, 24, 12));
    expect(stored.contentHash, computeContentHash('Updated content'));
  });

  test(
      'softDelete removes note from active list and exposes it in deleted list',
      () async {
    final note = _buildNote(
      id: 'note-3',
      title: 'Trash me',
      content: 'Disposable',
      updatedAt: DateTime.utc(2026, 3, 24, 10),
    );
    final deletedAt = DateTime.utc(2026, 3, 24, 13);

    await repository.create(note);
    await repository.softDelete(note.id, deletedAt);

    final activeNotes = await repository.watchActiveNotes().first;
    final deletedNotes = await repository.watchDeletedNotes().first;
    final stored = await repository.getById(note.id);

    expect(activeNotes, isEmpty);
    expect(deletedNotes.map((item) => item.id), [note.id]);
    expect(stored, isNotNull);
    expect(stored!.deletedAt, deletedAt);
    expect(stored.syncStatus, SyncStatus.pendingDelete);
  });

  test('restore moves note back to active list and clears deletedAt', () async {
    final note = _buildNote(
      id: 'note-4',
      title: 'Bring me back',
      content: 'Recoverable',
      updatedAt: DateTime.utc(2026, 3, 24, 10),
    );

    await repository.create(note);
    await repository.softDelete(note.id, DateTime.utc(2026, 3, 24, 13));
    await repository.restore(note.id);

    final activeNotes = await repository.watchActiveNotes().first;
    final deletedNotes = await repository.watchDeletedNotes().first;
    final stored = await repository.getById(note.id);

    expect(activeNotes.map((item) => item.id), [note.id]);
    expect(deletedNotes, isEmpty);
    expect(stored, isNotNull);
    expect(stored!.deletedAt, isNull);
    expect(stored.syncStatus, SyncStatus.pendingUpload);
  });

  test('searchNotes matches active notes and excludes deleted notes', () async {
    final matching = _buildNote(
      id: 'note-5',
      title: 'Project ideas',
      content: 'Sync engine details',
      updatedAt: DateTime.utc(2026, 3, 24, 10),
    );
    final deleted = _buildNote(
      id: 'note-6',
      title: 'Old project ideas',
      content: 'Archived draft',
      updatedAt: DateTime.utc(2026, 3, 24, 11),
    );

    await repository.create(matching);
    await repository.create(deleted);
    await repository.softDelete(deleted.id, DateTime.utc(2026, 3, 24, 14));

    final results = await repository.searchNotes('Project');

    expect(results.map((note) => note.id), ['note-5']);
  });

  test('folder-filtered active notes include notes in nested folders',
      () async {
    final parent = _buildNote(
      id: 'note-parent',
      title: 'Parent',
      content: 'folder root',
      updatedAt: DateTime.utc(2026, 3, 24, 10),
      folderPath: 'Projects',
    );
    final child = _buildNote(
      id: 'note-child',
      title: 'Child',
      content: 'folder child',
      updatedAt: DateTime.utc(2026, 3, 24, 11),
      folderPath: 'Projects/Proper Notes',
    );
    final elsewhere = _buildNote(
      id: 'note-elsewhere',
      title: 'Elsewhere',
      content: 'other folder',
      updatedAt: DateTime.utc(2026, 3, 24, 12),
      folderPath: 'Ideas',
    );

    await repository.create(parent);
    await repository.create(child);
    await repository.create(elsewhere);

    final results =
        await repository.watchActiveNotes(folderPath: 'Projects').first;

    expect(results.map((note) => note.id), ['note-child', 'note-parent']);
  });

  test('create persists the folder path', () async {
    final note = _buildNote(
      id: 'note-foldered',
      title: 'Foldered',
      content: 'Inside a folder',
      updatedAt: DateTime.utc(2026, 3, 24, 10),
      folderPath: 'Projects/Proper Notes',
    );

    await repository.create(note);
    final stored = await repository.getById(note.id);

    expect(stored?.folderPath, 'Projects/Proper Notes');
  });

  test(
      'countAttachmentReferences counts matches across active and deleted notes',
      () async {
    final active = _buildNote(
      id: 'note-attachment-active',
      title: 'Active',
      content:
          '![one](attachment://figure.png)\n![two](attachment://figure.png)',
      updatedAt: DateTime.utc(2026, 3, 24, 10),
    );
    final deleted = _buildNote(
      id: 'note-attachment-deleted',
      title: 'Deleted',
      content: '![three](attachment://figure.png)',
      updatedAt: DateTime.utc(2026, 3, 24, 11),
    );

    await repository.create(active);
    await repository.create(deleted);
    await repository.softDelete(
      deleted.id,
      DateTime.utc(2026, 3, 24, 12),
    );

    final count =
        await repository.countAttachmentReferences('attachment://figure.png');

    expect(count, 3);
  });
}

Note _buildNote({
  required String id,
  required String title,
  required String content,
  required DateTime updatedAt,
  String? folderPath,
}) {
  final createdAt = DateTime.utc(2026, 3, 24, 8);

  return Note(
    id: id,
    title: title,
    content: content,
    documentJson: legacyDocumentFromContent(content),
    createdAt: createdAt,
    updatedAt: updatedAt,
    syncStatus: SyncStatus.pendingUpload,
    contentHash: computeContentHash(content),
    deviceId: 'test-device',
    folderPath: folderPath,
  );
}
