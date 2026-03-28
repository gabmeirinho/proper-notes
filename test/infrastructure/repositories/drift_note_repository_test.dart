import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proper_notes/core/utils/content_hash.dart';
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
      updatedAt: DateTime.utc(2026, 3, 24, 12),
      contentHash: computeContentHash('Updated content'),
    );

    await repository.update(updated);

    final stored = await repository.getById(updated.id);

    expect(stored, isNotNull);
    expect(stored!.title, 'Final');
    expect(stored.content, 'Updated content');
    expect(stored.updatedAt, DateTime.utc(2026, 3, 24, 12));
    expect(stored.contentHash, computeContentHash('Updated content'));
  });

  test('softDelete removes note from active list and exposes it in deleted list',
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
}

Note _buildNote({
  required String id,
  required String title,
  required String content,
  required DateTime updatedAt,
}) {
  final createdAt = DateTime.utc(2026, 3, 24, 8);

  return Note(
    id: id,
    title: title,
    content: content,
    createdAt: createdAt,
    updatedAt: updatedAt,
    syncStatus: SyncStatus.pendingUpload,
    contentHash: computeContentHash(content),
    deviceId: 'test-device',
  );
}
