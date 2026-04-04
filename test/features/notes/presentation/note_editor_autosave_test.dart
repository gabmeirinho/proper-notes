import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proper_notes/features/notes/application/create_note.dart';
import 'package:proper_notes/features/notes/application/update_note.dart';
import 'package:proper_notes/features/notes/domain/note.dart';
import 'package:proper_notes/features/notes/domain/note_repository.dart';
import 'package:proper_notes/features/notes/domain/sync_status.dart';
import 'package:proper_notes/features/notes/presentation/note_editor_page.dart';
import 'package:proper_notes/features/sync/domain/remote_note.dart';

void main() {
  testWidgets(
    'autosaves a new note after debounce and updates it on later edits',
    (tester) async {
      final repository = _RecordingNoteRepository();

      await tester.pumpWidget(
        _buildEditor(
          repository: repository,
          embedded: true,
          onClose: () {},
        ),
      );

      await tester.enterText(find.byType(TextField).at(1), '# Hello');
      await tester.pump(const Duration(milliseconds: 799));
      expect(repository.createdNotes, isEmpty);

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();

      expect(repository.createdNotes, hasLength(1));
      expect(repository.updatedNotes, isEmpty);
      expect(find.text('All changes saved'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(1), '# Hello\nWorld');
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();

      expect(repository.createdNotes, hasLength(1));
      expect(repository.updatedNotes, hasLength(1));
      expect(
          repository.updatedNotes.single.id, repository.createdNotes.single.id);
      expect(repository.updatedNotes.single.content, '# Hello\nWorld');
    },
  );

  testWidgets(
    'closing a blank embedded draft does not create an empty note',
    (tester) async {
      final repository = _RecordingNoteRepository();
      var closed = false;

      await tester.pumpWidget(
        _buildEditor(
          repository: repository,
          embedded: true,
          onClose: () {
            closed = true;
          },
        ),
      );

      await tester.tap(find.byTooltip('Close editor'));
      await tester.pumpAndSettle();

      expect(closed, isTrue);
      expect(repository.createdNotes, isEmpty);
      expect(repository.updatedNotes, isEmpty);
    },
  );

  testWidgets(
    'closing an embedded editor flushes pending changes before dismissing it',
    (tester) async {
      final repository = _RecordingNoteRepository(
        createDelay: const Duration(milliseconds: 50),
      );
      var closed = false;

      await tester.pumpWidget(
        _buildEditor(
          repository: repository,
          embedded: true,
          onClose: () {
            closed = true;
          },
        ),
      );

      await tester.enterText(find.byType(TextField).at(1), 'Draft body');
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byTooltip('Close editor'));
      await tester.pump();

      expect(closed, isFalse);

      await tester.pumpAndSettle();

      expect(closed, isTrue);
      expect(repository.createdNotes, hasLength(1));
      expect(repository.createdNotes.single.content, 'Draft body');
    },
  );

  testWidgets(
    'lifecycle pause flushes pending changes immediately',
    (tester) async {
      final repository = _RecordingNoteRepository();

      await tester.pumpWidget(
        _buildEditor(
          repository: repository,
        ),
      );

      await tester.enterText(find.byType(TextField).at(1), 'Persist me');
      await tester.pump(const Duration(milliseconds: 100));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();

      expect(repository.createdNotes, hasLength(1));
      expect(repository.createdNotes.single.content, 'Persist me');
    },
  );
}

Widget _buildEditor({
  required _RecordingNoteRepository repository,
  bool embedded = false,
  VoidCallback? onClose,
}) {
  return MaterialApp(
    home: Scaffold(
      body: NoteEditorPage(
        createNote: CreateNote(
          repository: repository,
          deviceId: 'device-1',
        ),
        updateNote: UpdateNote(
          repository: repository,
          deviceId: 'device-1',
        ),
        embedded: embedded,
        onClose: onClose,
      ),
    ),
  );
}

class _RecordingNoteRepository implements NoteRepository {
  _RecordingNoteRepository({
    this.createDelay = Duration.zero,
    this.updateDelay = Duration.zero,
  });

  final Duration createDelay;
  final Duration updateDelay;
  final List<Note> createdNotes = <Note>[];
  final List<Note> updatedNotes = <Note>[];
  final List<Note> _activeNotes = <Note>[];
  final StreamController<List<Note>> _activeController =
      StreamController<List<Note>>.broadcast();

  @override
  Future<void> applyRemoteDeletion(RemoteNote remoteNote) async {}

  @override
  Future<void> create(Note note) async {
    if (createDelay > Duration.zero) {
      await Future<void>.delayed(createDelay);
    }

    createdNotes.add(note);
    _activeNotes.add(note);
    _activeController.add(List<Note>.unmodifiable(_activeNotes));
  }

  @override
  Future<Note?> getById(String id) async {
    for (final note in _activeNotes) {
      if (note.id == id) {
        return note;
      }
    }
    return null;
  }

  @override
  Future<List<Note>> getActiveNotesForSync() async =>
      List<Note>.unmodifiable(_activeNotes);

  @override
  Future<List<Note>> getDeletedNotesForSync() async => const <Note>[];

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
  Future<void> restore(String id) async {}

  @override
  Future<List<Note>> searchNotes(String query, {String? folderPath}) async =>
      List<Note>.unmodifiable(_activeNotes);

  @override
  Future<void> softDelete(String id, DateTime deletedAt) async {}

  @override
  Future<void> update(Note note) async {
    if (updateDelay > Duration.zero) {
      await Future<void>.delayed(updateDelay);
    }

    updatedNotes.add(note);
    final index = _activeNotes.indexWhere((existing) => existing.id == note.id);
    if (index != -1) {
      _activeNotes[index] = note;
    }
    _activeController.add(List<Note>.unmodifiable(_activeNotes));
  }

  @override
  Future<void> upsertRemoteNote(RemoteNote remoteNote) async {}

  @override
  Stream<List<Note>> watchActiveNotes({String? folderPath}) =>
      _activeController.stream;

  @override
  Stream<List<Note>> watchDeletedNotes({String? folderPath}) =>
      const Stream<List<Note>>.empty();
}
