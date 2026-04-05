import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proper_notes/core/utils/note_document.dart';
import 'package:proper_notes/features/notes/application/create_note.dart';
import 'package:proper_notes/features/notes/application/update_note.dart';
import 'package:proper_notes/features/notes/domain/note.dart';
import 'package:proper_notes/features/notes/domain/note_repository.dart';
import 'package:proper_notes/features/notes/domain/sync_status.dart';
import 'package:proper_notes/features/notes/presentation/note_editor_page.dart';
import 'package:proper_notes/features/sync/domain/remote_note.dart';

void main() {
  const colorScheme = ColorScheme.light();
  const baseStyle = TextStyle(fontSize: 16, height: 1.6);

  test('renders inactive bullet markers as bullets', () {
    final spans = buildInactiveMarkdownLineSpans(
      '- List item',
      baseStyle: baseStyle,
      colorScheme: colorScheme,
    );

    expect(spans.length, 2);

    final visibleBullet = spans[0] as TextSpan;
    final content = spans[1] as TextSpan;

    expect(visibleBullet.text, '• ');
    expect(visibleBullet.style?.fontWeight, FontWeight.w700);
    expect(content.text, 'List item');
  });

  test('keeps non-list lines unchanged in inactive rendering', () {
    final spans = buildInactiveMarkdownLineSpans(
      'Plain text',
      baseStyle: baseStyle,
      colorScheme: colorScheme,
    );

    expect(spans.length, 1);

    final content = spans.single as TextSpan;
    expect(content.text, 'Plain text');
    expect(content.style?.color, colorScheme.onSurface);
  });

  test('renders inactive quote markers as quote bars', () {
    final spans = buildInactiveMarkdownLineSpans(
      '> Quoted text',
      baseStyle: baseStyle,
      colorScheme: colorScheme,
    );

    expect(spans.length, 2);

    final quoteMarker = spans[0] as TextSpan;
    final content = spans[1] as TextSpan;

    expect(quoteMarker.text, '│ ');
    expect(quoteMarker.style?.color, colorScheme.primary);
    expect(content.text, 'Quoted text');
    expect(content.style?.fontStyle, FontStyle.italic);
  });

  test('keeps code snippet tags and body as plain inactive text by default',
      () {
    final tagSpans = buildInactiveMarkdownLineSpans(
      '[code:dart]',
      baseStyle: baseStyle,
      colorScheme: colorScheme,
    );
    final codeLineSpans = buildInactiveMarkdownLineSpans(
      'print("hi");',
      baseStyle: baseStyle,
      colorScheme: colorScheme,
    );

    expect(tagSpans.length, 1);
    expect((tagSpans.single as TextSpan).text, '[code:dart]');

    expect(codeLineSpans.length, 1);
    expect((codeLineSpans.single as TextSpan).text, 'print("hi");');
    expect((codeLineSpans.single as TextSpan).style?.fontFamily,
        isNot('monospace'));
  });

  test('renders inactive code snippet regions with code styling', () {
    final openingSpans = buildInactiveMarkdownLineSpans(
      '[code:dart]',
      baseStyle: baseStyle,
      colorScheme: colorScheme,
      isCodeSnippetOpeningTag: true,
      codeSnippetLanguage: 'dart',
    );
    final bodySpans = buildInactiveMarkdownLineSpans(
      'final value = 42;',
      baseStyle: baseStyle,
      colorScheme: colorScheme,
      isInsideCodeSnippet: true,
    );
    final closingSpans = buildInactiveMarkdownLineSpans(
      '[/code]',
      baseStyle: baseStyle,
      colorScheme: colorScheme,
      isCodeSnippetClosingTag: true,
    );

    expect((openingSpans.single as TextSpan).text, '[DART]');
    expect((openingSpans.single as TextSpan).style?.color, colorScheme.primary);

    expect((bodySpans.single as TextSpan).text, 'final value = 42;');
    expect((bodySpans.single as TextSpan).style?.fontFamily, 'monospace');

    expect((closingSpans.single as TextSpan).text, '[/CODE]');
    expect((closingSpans.single as TextSpan).style?.color, colorScheme.primary);
  });

  test('renders task-like markdown as plain bullet text', () {
    final spans = buildInactiveMarkdownLineSpans(
      '- [x] Done task',
      baseStyle: baseStyle,
      colorScheme: colorScheme,
    );

    expect(spans.length, 2);
    expect((spans[0] as TextSpan).text, '• ');
    expect((spans[1] as TextSpan).text, '[x] Done task');
  });

  test('continues bullet lists on newline', () {
    final updated = applyMarkdownListEditBehavior(
      const TextEditingValue(
        text: '- First item',
        selection: TextSelection.collapsed(offset: 12),
      ),
      const TextEditingValue(
        text: '- First item\n',
        selection: TextSelection.collapsed(offset: 13),
      ),
    );

    expect(updated.text, '- First item\n- ');
    expect(updated.selection.baseOffset, 15);
  });

  test('continues task-like markdown as a normal bullet list', () {
    final updated = applyMarkdownListEditBehavior(
      const TextEditingValue(
        text: '- [x] Done',
        selection: TextSelection.collapsed(offset: 10),
      ),
      const TextEditingValue(
        text: '- [x] Done\n',
        selection: TextSelection.collapsed(offset: 11),
      ),
    );

    expect(updated.text, '- [x] Done\n- ');
    expect(updated.selection.baseOffset, 13);
  });

  test('backspace on an empty bullet marker returns to normal text', () {
    final updated = applyMarkdownListEditBehavior(
      const TextEditingValue(
        text: '- ',
        selection: TextSelection.collapsed(offset: 2),
      ),
      const TextEditingValue(
        text: '-',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );

    expect(updated.text, '');
    expect(updated.selection.baseOffset, 0);
  });

  testWidgets('code button inserts snippet delimiters', (tester) async {
    final repository = _StubNoteRepository();

    await tester.pumpWidget(
      MaterialApp(
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
          ),
        ),
      ),
    );

    await tester.tap(find.text('Code'));
    await tester.pumpAndSettle();

    final contentField =
        tester.widgetList<TextField>(find.byType(TextField)).last;
    expect(contentField.controller?.text, '');
  });

  testWidgets('embedded editor shows code controls and code block copy button',
      (tester) async {
    final repository = _StubNoteRepository();
    String? clipboardText;

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(
      MaterialApp(
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
            embedded: true,
            onClose: () {},
          ),
        ),
      ),
    );

    expect(find.text('Code'), findsOneWidget);
    expect(find.text('Copy code'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField).last,
      '[code:dart]\nprint("hi");\n[/code]',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Copy'));
    await tester.pump();

    expect(clipboardText, 'print("hi");');
    expect(find.text('DART snippet copied'), findsOneWidget);
  });

  testWidgets('loads paragraph documents as separate editable blocks',
      (tester) async {
    final repository = _StubNoteRepository();
    final note = Note(
      id: 'note-1',
      title: 'Doc note',
      content: 'First paragraph\n\nSecond paragraph',
      documentJson: paragraphDocumentFromEditableText(
          'First paragraph\n\nSecond paragraph'),
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      syncStatus: SyncStatus.synced,
      contentHash: 'hash',
      deviceId: 'device-1',
    );

    await tester.pumpWidget(
      MaterialApp(
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
            note: note,
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('document-block-editor')), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(3));

    final textFields =
        tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(textFields[1].controller?.text, 'First paragraph');
    expect(textFields[2].controller?.text, 'Second paragraph');
  });

  testWidgets('editing a paragraph keeps the same text field controller',
      (tester) async {
    final repository = _StubNoteRepository();

    await tester.pumpWidget(
      MaterialApp(
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
          ),
        ),
      ),
    );

    final before =
        tester.widgetList<TextField>(find.byType(TextField)).last.controller;

    await tester.enterText(find.byType(TextField).last, 'Hello world');
    await tester.pumpAndSettle();

    final after =
        tester.widgetList<TextField>(find.byType(TextField)).last.controller;

    expect(identical(before, after), isTrue);
    expect(after?.text, 'Hello world');
  });

  testWidgets('loads code blocks as dedicated editor cards', (tester) async {
    final repository = _StubNoteRepository();
    final note = Note(
      id: 'note-2',
      title: 'Code note',
      content: 'Intro\n\n[code:dart]\nfinal value = 42;\n[/code]',
      documentJson: NoteDocument(
        version: 1,
        blocks: const <NoteBlock>[
          ParagraphBlock(id: 'p1', text: 'Intro'),
          CodeBlock(id: 'c1', language: 'dart', code: 'final value = 42;'),
        ],
      ).toJsonString(),
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      syncStatus: SyncStatus.synced,
      contentHash: 'hash',
      deviceId: 'device-1',
    );

    await tester.pumpWidget(
      MaterialApp(
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
            note: note,
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('document-block-editor')), findsOneWidget);
    expect(find.text('DART'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);

    final textFields =
        tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(textFields[1].controller?.text, 'Intro');
    expect(textFields[2].controller?.text, 'final value = 42;');
  });
}

class _StubNoteRepository implements NoteRepository {
  @override
  Future<void> applyRemoteDeletion(RemoteNote remoteNote) async {}

  @override
  Future<void> create(Note note) async {}

  @override
  Future<Note?> getById(String id) async => null;

  @override
  Future<List<Note>> getActiveNotesForSync() async => const <Note>[];

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
      const <Note>[];

  @override
  Future<void> softDelete(String id, DateTime deletedAt) async {}

  @override
  Future<void> update(Note note) async {}

  @override
  Future<void> upsertRemoteNote(RemoteNote remoteNote) async {}

  @override
  Stream<List<Note>> watchActiveNotes({String? folderPath}) =>
      const Stream<List<Note>>.empty();

  @override
  Stream<List<Note>> watchDeletedNotes({String? folderPath}) =>
      const Stream<List<Note>>.empty();
}
