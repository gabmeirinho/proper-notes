import 'package:flutter_test/flutter_test.dart';
import 'package:proper_notes/core/utils/content_hash.dart';
import 'package:proper_notes/features/notes/application/create_note.dart';
import 'package:proper_notes/features/notes/application/delete_note.dart';
import 'package:proper_notes/features/notes/application/restore_note.dart';
import 'package:proper_notes/features/notes/application/search_notes.dart';
import 'package:proper_notes/features/notes/application/update_note.dart';
import 'package:proper_notes/features/notes/domain/note.dart';
import 'package:proper_notes/features/notes/domain/note_repository.dart';
import 'package:proper_notes/features/notes/domain/sync_status.dart';
import 'package:proper_notes/features/sync/domain/remote_note.dart';
import 'package:uuid/data.dart';
import 'package:uuid/uuid.dart';

void main() {
  group('CreateNote', () {
    test('creates a pending-upload note and preserves markdown content',
        () async {
      final repository = _FakeNoteRepository();
      final useCase = CreateNote(
        repository: repository,
        deviceId: 'device-a',
        uuid: const _FixedUuid('note-123'),
      );

      const markdown = '# Heading\n\n- item 1\n- item 2';
      final created = await useCase(
        title: 'Markdown note',
        content: markdown,
      );

      expect(created.id, 'note-123');
      expect(created.title, 'Markdown note');
      expect(created.content, markdown);
      expect(created.syncStatus, SyncStatus.pendingUpload);
      expect(created.deviceId, 'device-a');
      expect(created.contentHash, computeContentHash(markdown));
      expect(created.createdAt.isUtc, isTrue);
      expect(created.updatedAt.isUtc, isTrue);
      expect(repository.createdNotes.single.id, 'note-123');
    });
  });

  group('UpdateNote', () {
    test('updates title, markdown content, sync status and device id', () async {
      final repository = _FakeNoteRepository();
      final useCase = UpdateNote(
        repository: repository,
        deviceId: 'device-b',
      );
      final original = _buildNote(
        id: 'note-1',
        title: 'Old title',
        content: 'old body',
        syncStatus: SyncStatus.synced,
        deviceId: 'device-a',
      );

      const markdown = '## Updated\n\n```dart\nprint("hi");\n```';
      final updated = await useCase(
        original: original,
        title: 'New title',
        content: markdown,
      );

      expect(updated.id, original.id);
      expect(updated.title, 'New title');
      expect(updated.content, markdown);
      expect(updated.contentHash, computeContentHash(markdown));
      expect(updated.syncStatus, SyncStatus.pendingUpload);
      expect(updated.deviceId, 'device-b');
      expect(updated.updatedAt.isAfter(original.updatedAt), isTrue);
      expect(repository.updatedNotes.single.content, markdown);
    });
  });

  group('DeleteNote', () {
    test('delegates to repository soft delete with a UTC timestamp', () async {
      final repository = _FakeNoteRepository();
      final useCase = DeleteNote(repository: repository);

      await useCase('note-delete');

      expect(repository.softDeletedIds.single, 'note-delete');
      expect(repository.softDeleteTimestamps.single.isUtc, isTrue);
    });
  });

  group('RestoreNote', () {
    test('delegates restore to repository', () async {
      final repository = _FakeNoteRepository();
      final useCase = RestoreNote(repository: repository);

      await useCase('note-restore');

      expect(repository.restoredIds, ['note-restore']);
    });
  });

  group('SearchNotes', () {
    test('returns repository results for a query', () async {
      final repository = _FakeNoteRepository(
        searchResults: [
          _buildNote(
            id: 'note-search',
            title: 'Search target',
            content: 'content',
            syncStatus: SyncStatus.pendingUpload,
            deviceId: 'device-a',
          ),
        ],
      );
      final useCase = SearchNotes(repository: repository);

      final results = await useCase('target');

      expect(repository.searchQueries, ['target']);
      expect(results.map((note) => note.id), ['note-search']);
    });
  });
}

class _FakeNoteRepository implements NoteRepository {
  _FakeNoteRepository({
    List<Note>? searchResults,
  }) : _searchResults = searchResults ?? <Note>[];

  final List<Note> createdNotes = [];
  final List<Note> updatedNotes = [];
  final List<String> restoredIds = [];
  final List<String> softDeletedIds = [];
  final List<DateTime> softDeleteTimestamps = [];
  final List<String> searchQueries = [];
  final List<Note> _searchResults;

  @override
  Future<void> create(Note note) async {
    createdNotes.add(note);
  }

  @override
  Future<Note?> getById(String id) async => null;

  @override
  Future<List<Note>> getActiveNotesForSync() async => const [];

  @override
  Future<List<Note>> getDeletedNotesForSync() async => const [];

  @override
  Future<void> applyRemoteDeletion(RemoteNote remoteNote) async {}

  @override
  Future<void> markConflict(String id) async {}

  @override
  Future<void> markSynced({
    required String id,
    required DateTime syncedAt,
    required String baseContentHash,
    String? remoteFileId,
  }) async {}

  @override
  Future<void> restore(String id) async {
    restoredIds.add(id);
  }

  @override
  Future<List<Note>> searchNotes(String query) async {
    searchQueries.add(query);
    return _searchResults;
  }

  @override
  Future<void> softDelete(String id, DateTime deletedAt) async {
    softDeletedIds.add(id);
    softDeleteTimestamps.add(deletedAt);
  }

  @override
  Future<void> update(Note note) async {
    updatedNotes.add(note);
  }

  @override
  Future<void> upsertRemoteNote(RemoteNote remoteNote) async {}

  @override
  Stream<List<Note>> watchActiveNotes() => const Stream.empty();

  @override
  Stream<List<Note>> watchDeletedNotes() => const Stream.empty();
}

class _FixedUuid extends Uuid {
  const _FixedUuid(this.value);

  final String value;

  @override
  String v4({
    V4Options? config,
    Map<String, dynamic>? options,
  }) =>
      value;
}

Note _buildNote({
  required String id,
  required String title,
  required String content,
  required SyncStatus syncStatus,
  required String deviceId,
}) {
  final timestamp = DateTime.utc(2026, 3, 24, 12);

  return Note(
    id: id,
    title: title,
    content: content,
    createdAt: timestamp,
    updatedAt: timestamp,
    syncStatus: syncStatus,
    contentHash: computeContentHash(content),
    deviceId: deviceId,
  );
}
