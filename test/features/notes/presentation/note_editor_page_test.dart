import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proper_notes/core/utils/attachments.dart';
import 'package:proper_notes/core/utils/note_document.dart';
import 'package:proper_notes/features/notes/application/create_note.dart';
import 'package:proper_notes/features/notes/application/update_note.dart';
import 'package:proper_notes/features/notes/domain/note.dart';
import 'package:proper_notes/features/notes/domain/note_repository.dart';
import 'package:proper_notes/features/notes/domain/sync_status.dart';
import 'package:proper_notes/features/notes/presentation/attachment_image_preview.dart';
import 'package:proper_notes/features/notes/presentation/note_editor_page.dart';
import 'package:proper_notes/features/sync/domain/remote_note.dart';

void main() {
  const colorScheme = ColorScheme.light();
  const baseStyle = TextStyle(fontSize: 16, height: 1.6);
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory =
        await Directory.systemTemp.createTemp('note_editor_page_test_');
    debugAttachmentDirectoryOverride = tempDirectory;
  });

  tearDown(() async {
    debugAttachmentDirectoryOverride = null;
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

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

  test('renders inactive bold markdown without visible markers', () {
    final spans = buildInactiveMarkdownLineSpans(
      'Before **bold** after',
      baseStyle: baseStyle,
      colorScheme: colorScheme,
    );

    expect(spans.map((span) => (span as TextSpan).text).join(),
        'Before **bold** after');
    expect((spans[1] as TextSpan).style?.color, Colors.transparent);
    expect((spans[2] as TextSpan).text, 'bold');
    expect((spans[2] as TextSpan).style?.fontWeight, FontWeight.w700);
    expect((spans[3] as TextSpan).style?.color, Colors.transparent);
  });

  test('renders inactive italic markdown without visible markers', () {
    final spans = buildInactiveMarkdownLineSpans(
      'Before *italic* after',
      baseStyle: baseStyle,
      colorScheme: colorScheme,
    );

    expect(spans.map((span) => (span as TextSpan).text).join(),
        'Before *italic* after');
    expect((spans[1] as TextSpan).style?.color, Colors.transparent);
    expect((spans[2] as TextSpan).text, 'italic');
    expect((spans[2] as TextSpan).style?.fontStyle, FontStyle.italic);
    expect((spans[3] as TextSpan).style?.color, Colors.transparent);
  });

  test('renders inactive inline code markdown without visible markers', () {
    final spans = buildInactiveMarkdownLineSpans(
      'Before `code` after',
      baseStyle: baseStyle,
      colorScheme: colorScheme,
    );

    expect(spans.map((span) => (span as TextSpan).text).join(),
        'Before `code` after');
    expect((spans[1] as TextSpan).style?.color, Colors.transparent);
    expect((spans[2] as TextSpan).text, 'code');
    expect((spans[2] as TextSpan).style?.fontFamily, isNull);
    expect(
      (spans[2] as TextSpan).style?.backgroundColor,
      colorScheme.surfaceContainerHighest,
    );
    expect((spans[3] as TextSpan).style?.color, Colors.transparent);
  });

  test('snippet overlay bottom aligns to the middle of closing fence line', () {
    final bottom = snippetOverlayBottomForClosingFence(
      closingFenceBox:
          const TextBox.fromLTRBD(0, 20, 40, 36, TextDirection.ltr),
      contentPaddingTop: 18,
      scrollOffset: 4,
    );

    expect(bottom, 42);
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

  test('renders inactive headings without dropping markdown markers', () {
    final spans = buildInactiveMarkdownLineSpans(
      '# Heading',
      baseStyle: baseStyle,
      colorScheme: colorScheme,
    );

    expect(spans.length, 2);

    final marker = spans[0] as TextSpan;
    final content = spans[1] as TextSpan;
    expect(marker.text, '# ');
    expect(marker.style?.color, Colors.transparent);
    expect(marker.style?.fontSize, 0.1);
    expect(content.text, 'Heading');
    expect(content.style?.fontWeight, FontWeight.w800);
    expect(spans.map((span) => (span as TextSpan).text).join(), '# Heading');
  });

  test('keeps code snippet tags and body as plain inactive text by default',
      () {
    final tagSpans = buildInactiveMarkdownLineSpans(
      '```dart',
      baseStyle: baseStyle,
      colorScheme: colorScheme,
    );
    final codeLineSpans = buildInactiveMarkdownLineSpans(
      'print("hi");',
      baseStyle: baseStyle,
      colorScheme: colorScheme,
    );

    expect(tagSpans.length, 1);
    expect((tagSpans.single as TextSpan).text, '```dart');

    expect(codeLineSpans.length, 1);
    expect((codeLineSpans.single as TextSpan).text, 'print("hi");');
    expect((codeLineSpans.single as TextSpan).style?.fontFamily,
        isNot('monospace'));
  });

  test('renders inactive code snippet regions with code styling', () {
    final openingSpans = buildInactiveMarkdownLineSpans(
      '```dart',
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
      '```',
      baseStyle: baseStyle,
      colorScheme: colorScheme,
      isCodeSnippetClosingTag: true,
    );

    expect((openingSpans.single as TextSpan).text, '```dart');
    expect((openingSpans.single as TextSpan).style?.color, colorScheme.primary);

    expect((bodySpans.single as TextSpan).text, 'final value = 42;');
    expect(
        (bodySpans.single as TextSpan).style?.fontFamily, isNot('monospace'));

    expect((closingSpans.single as TextSpan).text, '```');
    expect((closingSpans.single as TextSpan).style?.color, colorScheme.primary);
  });

  test('renders inactive checklist markdown without visible markers', () {
    final spans = buildInactiveMarkdownLineSpans(
      '- [x] Done task',
      baseStyle: baseStyle,
      colorScheme: colorScheme,
    );

    expect(spans.length, 2);
    expect((spans[0] as TextSpan).text, '- [x] ');
    expect((spans[0] as TextSpan).style?.color, Colors.transparent);
    expect((spans[1] as TextSpan).text, 'Done task');
  });

  testWidgets('inline checklist span preserves raw markdown length',
      (tester) async {
    final repository = _StubNoteRepository();
    final note = Note(
      id: 'note-checklist-length',
      title: 'Checklist note',
      content: '- [ ] Done task\nNext line',
      documentJson: paragraphDocumentFromEditableText(
        '- [ ] Done task\nNext line',
      ),
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      syncStatus: SyncStatus.synced,
      contentHash: 'hash',
      deviceId: 'device-1',
    );

    await tester.pumpWidget(_buildEditor(repository: repository, note: note));
    await tester.pumpAndSettle();

    final bodyField = tester.widget<TextField>(_bodyField());
    bodyField.controller!.selection = TextSelection.collapsed(
      offset: bodyField.controller!.text.length,
    );
    await tester.pumpAndSettle();

    final builtSpan = bodyField.controller!.buildTextSpan(
      context: tester.element(_bodyField()),
      style: baseStyle,
      withComposing: false,
    );

    expect(
      builtSpan.toPlainText(includePlaceholders: true).length,
      bodyField.controller!.text.length,
    );
  });

  testWidgets('inactive attachment image span preserves raw markdown length',
      (tester) async {
    final repository = _StubNoteRepository();
    final note = Note(
      id: 'note-attachment-length',
      title: 'Attachment note',
      content: '![Diagram](attachment://preview.png)\nNext line',
      documentJson: paragraphDocumentFromEditableText(
        '![Diagram](attachment://preview.png)\nNext line',
      ),
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      syncStatus: SyncStatus.synced,
      contentHash: 'hash',
      deviceId: 'device-1',
    );

    await tester.pumpWidget(_buildEditor(repository: repository, note: note));
    await tester.pump();

    final bodyField = tester.widget<TextField>(_bodyField());
    final nextLineOffset = bodyField.controller!.text.indexOf('Next line');
    bodyField.controller!.selection = TextSelection.collapsed(
      offset: nextLineOffset,
    );
    await tester.pump();

    final builtSpan = bodyField.controller!.buildTextSpan(
      context: tester.element(_bodyField()),
      style: baseStyle,
      withComposing: false,
    );

    expect(find.byType(AttachmentImagePreview), findsOneWidget);
    expect(
      builtSpan.toPlainText(includePlaceholders: true).length,
      bodyField.controller!.text.length,
    );
  });

  testWidgets(
      'opening a note shows attachment previews before the editor is focused',
      (tester) async {
    final repository = _StubNoteRepository();
    final note = Note(
      id: 'note-attachment-open-preview',
      title: 'Attachment note',
      content: '![Diagram](attachment://preview.png)\nNext line',
      documentJson: paragraphDocumentFromEditableText(
        '![Diagram](attachment://preview.png)\nNext line',
      ),
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      syncStatus: SyncStatus.synced,
      contentHash: 'hash',
      deviceId: 'device-1',
    );

    await tester.pumpWidget(_buildEditor(repository: repository, note: note));
    await tester.pump();

    expect(find.byType(AttachmentImagePreview), findsOneWidget);
  });

  testWidgets(
      'active attachment image line shows raw markdown instead of preview',
      (tester) async {
    final repository = _StubNoteRepository();
    final note = Note(
      id: 'note-attachment-active',
      title: 'Attachment note',
      content: '![Diagram](attachment://preview.png)\nNext line',
      documentJson: paragraphDocumentFromEditableText(
        '![Diagram](attachment://preview.png)\nNext line',
      ),
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      syncStatus: SyncStatus.synced,
      contentHash: 'hash',
      deviceId: 'device-1',
    );

    await tester.pumpWidget(_buildEditor(repository: repository, note: note));
    await tester.pump();

    await tester.tap(_bodyField());
    await tester.pumpAndSettle();

    final bodyField = tester.widget<TextField>(_bodyField());
    bodyField.controller!.selection = const TextSelection.collapsed(offset: 0);
    await tester.pump();

    expect(find.byType(AttachmentImagePreview), findsNothing);
  });

  testWidgets('clicking attachment preview selects the image', (tester) async {
    final repository = _StubNoteRepository();
    const imageLine = '![Diagram](attachment://preview.png)';
    final note = Note(
      id: 'note-attachment-tap',
      title: 'Attachment note',
      content: '$imageLine\n\nNext line',
      documentJson:
          paragraphDocumentFromEditableText('$imageLine\n\nNext line'),
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      syncStatus: SyncStatus.synced,
      contentHash: 'hash',
      deviceId: 'device-1',
    );

    await tester.pumpWidget(_buildEditor(repository: repository, note: note));
    await tester.pump();

    final bodyField = tester.widget<TextField>(_bodyField());
    bodyField.controller!.selection = TextSelection.collapsed(
      offset: bodyField.controller!.text.length,
    );
    await tester.pump();

    await tester.tapAt(
      tester
          .getCenter(find.byKey(const ValueKey('attachment-image-overlay-0'))),
    );
    await tester.pumpAndSettle();

    final updatedBodyField = tester.widget<TextField>(_bodyField());
    final preview = tester.widget<AttachmentImagePreview>(
      find.byType(AttachmentImagePreview),
    );
    expect(updatedBodyField.focusNode!.hasFocus, isTrue);
    expect(updatedBodyField.controller!.selection.baseOffset,
        imageLine.length + 1);
    expect(
      updatedBodyField.controller!.selection.extentOffset,
      imageLine.length + 1,
    );
    expect(find.byType(AttachmentImagePreview), findsOneWidget);
    expect(preview.selected, isTrue);
    expect(find.byTooltip('Close image preview'), findsNothing);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('clicking attachment preview while unfocused selects the image',
      (tester) async {
    final repository = _StubNoteRepository();
    const imageLine = '![Diagram](attachment://preview.png)';
    final note = Note(
      id: 'note-attachment-unfocused-tap',
      title: 'Attachment note',
      content: '$imageLine\n\nNext line',
      documentJson:
          paragraphDocumentFromEditableText('$imageLine\n\nNext line'),
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      syncStatus: SyncStatus.synced,
      contentHash: 'hash',
      deviceId: 'device-1',
    );

    await tester.pumpWidget(_buildEditor(repository: repository, note: note));
    await tester.pumpAndSettle();

    final bodyField = tester.widget<TextField>(_bodyField());
    expect(bodyField.focusNode!.hasFocus, isFalse);

    await tester.tapAt(
      tester
          .getCenter(find.byKey(const ValueKey('attachment-image-overlay-0'))),
    );
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(_bodyField()).focusNode!.hasFocus, isTrue);
    expect(
      tester
          .widget<AttachmentImagePreview>(find.byType(AttachmentImagePreview))
          .selected,
      isTrue,
    );
    expect(
      tester.widget<TextField>(_bodyField()).controller!.selection.baseOffset,
      imageLine.length + 1,
    );
    expect(find.byType(AttachmentImagePreview), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('repeated clicks keep the attachment preview selected',
      (tester) async {
    final repository = _StubNoteRepository();
    const imageLine = '![Diagram](attachment://preview.png)';
    final note = Note(
      id: 'note-attachment-repeat-tap',
      title: 'Attachment note',
      content: '$imageLine\n\nNext line',
      documentJson:
          paragraphDocumentFromEditableText('$imageLine\n\nNext line'),
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      syncStatus: SyncStatus.synced,
      contentHash: 'hash',
      deviceId: 'device-1',
    );

    await tester.pumpWidget(_buildEditor(repository: repository, note: note));
    await tester.pumpAndSettle();

    final imageFinder =
        find.byKey(const ValueKey('attachment-image-overlay-0'));
    await tester.tapAt(tester.getCenter(imageFinder));
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(imageFinder));
    await tester.pumpAndSettle();

    expect(find.byType(AttachmentImagePreview), findsOneWidget);
    expect(
      tester
          .widget<AttachmentImagePreview>(find.byType(AttachmentImagePreview))
          .selected,
      isTrue,
    );
    expect(find.text(imageLine), findsNothing);
  });

  testWidgets('delete removes a selected attachment preview', (tester) async {
    final repository = _StubNoteRepository();
    const imageLine = '![Diagram](attachment://preview.png)';
    final note = Note(
      id: 'note-attachment-delete',
      title: 'Attachment note',
      content: '$imageLine\n\nNext line',
      documentJson:
          paragraphDocumentFromEditableText('$imageLine\n\nNext line'),
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      syncStatus: SyncStatus.synced,
      contentHash: 'hash',
      deviceId: 'device-1',
    );

    await tester.pumpWidget(_buildEditor(repository: repository, note: note));
    await tester.pumpAndSettle();

    await tester.tapAt(
      tester
          .getCenter(find.byKey(const ValueKey('attachment-image-overlay-0'))),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();

    expect(find.byType(AttachmentImagePreview), findsNothing);
    expect(
      tester.widget<TextField>(_bodyField()).controller!.text,
      '\nNext line',
    );
  });

  testWidgets('backspace removes a selected attachment preview',
      (tester) async {
    final repository = _StubNoteRepository();
    const imageLine = '![Diagram](attachment://preview.png)';
    final note = Note(
      id: 'note-attachment-backspace',
      title: 'Attachment note',
      content: '$imageLine\n\nNext line',
      documentJson:
          paragraphDocumentFromEditableText('$imageLine\n\nNext line'),
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      syncStatus: SyncStatus.synced,
      contentHash: 'hash',
      deviceId: 'device-1',
    );

    await tester.pumpWidget(_buildEditor(repository: repository, note: note));
    await tester.pumpAndSettle();

    await tester.tapAt(
      tester
          .getCenter(find.byKey(const ValueKey('attachment-image-overlay-0'))),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();

    expect(find.byType(AttachmentImagePreview), findsNothing);
    expect(
      tester.widget<TextField>(_bodyField()).controller!.text,
      '\nNext line',
    );
  });

  testWidgets('escape clears a selected attachment preview', (tester) async {
    final repository = _StubNoteRepository();
    const imageLine = '![Diagram](attachment://preview.png)';
    final note = Note(
      id: 'note-attachment-escape',
      title: 'Attachment note',
      content: '$imageLine\n\nNext line',
      documentJson:
          paragraphDocumentFromEditableText('$imageLine\n\nNext line'),
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      syncStatus: SyncStatus.synced,
      contentHash: 'hash',
      deviceId: 'device-1',
    );

    await tester.pumpWidget(_buildEditor(repository: repository, note: note));
    await tester.pumpAndSettle();

    await tester.tapAt(
      tester
          .getCenter(find.byKey(const ValueKey('attachment-image-overlay-0'))),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<AttachmentImagePreview>(find.byType(AttachmentImagePreview))
          .selected,
      isTrue,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<AttachmentImagePreview>(find.byType(AttachmentImagePreview))
          .selected,
      isFalse,
    );
  });

  testWidgets('clicking elsewhere clears a selected attachment preview',
      (tester) async {
    final repository = _StubNoteRepository();
    const imageLine = '![Diagram](attachment://preview.png)';
    final note = Note(
      id: 'note-attachment-clear-on-text-tap',
      title: 'Attachment note',
      content: '$imageLine\n\nNext line',
      documentJson:
          paragraphDocumentFromEditableText('$imageLine\n\nNext line'),
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      syncStatus: SyncStatus.synced,
      contentHash: 'hash',
      deviceId: 'device-1',
    );

    await tester.pumpWidget(_buildEditor(repository: repository, note: note));
    await tester.pumpAndSettle();

    await tester.tapAt(
      tester
          .getCenter(find.byKey(const ValueKey('attachment-image-overlay-0'))),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<AttachmentImagePreview>(find.byType(AttachmentImagePreview))
          .selected,
      isTrue,
    );

    await tester.tap(_bodyField());
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<AttachmentImagePreview>(find.byType(AttachmentImagePreview))
          .selected,
      isFalse,
    );
  });

  testWidgets(
      'clicking near the bottom of attachment hitbox does not collapse it',
      (tester) async {
    final repository = _StubNoteRepository();
    const imageLine = '![Diagram](attachment://preview.png)';
    final note = Note(
      id: 'note-attachment-bottom-tap',
      title: 'Attachment note',
      content: '$imageLine\n\nNext line',
      documentJson:
          paragraphDocumentFromEditableText('$imageLine\n\nNext line'),
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      syncStatus: SyncStatus.synced,
      contentHash: 'hash',
      deviceId: 'device-1',
    );

    await tester.pumpWidget(_buildEditor(repository: repository, note: note));
    await tester.pump();

    final bodyField = tester.widget<TextField>(_bodyField());
    bodyField.controller!.selection = TextSelection.collapsed(
      offset: bodyField.controller!.text.length,
    );
    await tester.pump();

    final hitbox = find.byKey(const ValueKey('attachment-image-hitbox-0'));
    final hitboxRect = tester.getRect(hitbox);
    await tester.tapAt(
      Offset(hitboxRect.center.dx, hitboxRect.bottom - 2),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AttachmentImagePreview), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('right clicking attachment preview does not open a dialog',
      (tester) async {
    final repository = _StubNoteRepository();
    const imageLine = '![Diagram](attachment://preview.png)';
    final note = Note(
      id: 'note-attachment-right-click',
      title: 'Attachment note',
      content: '$imageLine\n\nNext line',
      documentJson:
          paragraphDocumentFromEditableText('$imageLine\n\nNext line'),
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      syncStatus: SyncStatus.synced,
      contentHash: 'hash',
      deviceId: 'device-1',
    );

    await tester.pumpWidget(_buildEditor(repository: repository, note: note));
    await tester.pump();

    final gesture = await tester.startGesture(
      tester
          .getCenter(find.byKey(const ValueKey('attachment-image-overlay-0'))),
      buttons: kSecondaryButton,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byType(AttachmentImagePreview), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byTooltip('Close image preview'), findsNothing);
  });

  testWidgets('scroll wheel over attachment preview still scrolls the editor',
      (tester) async {
    final repository = _StubNoteRepository();
    final trailingLines = List<String>.generate(80, (index) => 'Line $index');
    final content = [
      '![Diagram](attachment://preview.png)',
      '',
      ...trailingLines,
    ].join('\n');
    final note = Note(
      id: 'note-attachment-scroll',
      title: 'Attachment scroll note',
      content: content,
      documentJson: paragraphDocumentFromEditableText(content),
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      syncStatus: SyncStatus.synced,
      contentHash: 'hash',
      deviceId: 'device-1',
    );

    await tester.pumpWidget(_buildEditor(repository: repository, note: note));
    await tester.pumpAndSettle();

    final editableText = tester.widget<EditableText>(
      find.byType(EditableText).last,
    );
    final scrollController = editableText.scrollController!;
    final initialOffset = scrollController.offset;

    tester.binding.handlePointerEvent(
      PointerScrollEvent(
        position: tester.getCenter(
          find.byKey(const ValueKey('attachment-image-overlay-0')),
        ),
        scrollDelta: const Offset(0, 180),
      ),
    );
    await tester.pumpAndSettle();

    expect(scrollController.offset, greaterThan(initialOffset));
  });

  testWidgets('attachment preview reserves layout space before the next line',
      (tester) async {
    final repository = _StubNoteRepository();
    const imageLine = '![Diagram](attachment://preview.png)';
    final note = Note(
      id: 'note-attachment-layout',
      title: 'Attachment note',
      content: '$imageLine\nNext line',
      documentJson: paragraphDocumentFromEditableText('$imageLine\nNext line'),
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      syncStatus: SyncStatus.synced,
      contentHash: 'hash',
      deviceId: 'device-1',
    );

    await tester.pumpWidget(_buildEditor(repository: repository, note: note));
    await tester.pumpAndSettle();

    final bodyField = tester.widget<TextField>(_bodyField());
    final nextLineOffset = imageLine.length + 1;
    bodyField.controller!.selection = TextSelection.collapsed(
      offset: nextLineOffset,
    );
    await tester.pumpAndSettle();

    final imageBottom = tester
        .getBottomLeft(find.byKey(const ValueKey('attachment-image-hitbox-0')))
        .dy;
    final editableState =
        tester.state<EditableTextState>(find.byType(EditableText).last);
    final nextLineCaretRect = editableState.renderEditable.getLocalRectForCaret(
      TextPosition(offset: nextLineOffset),
    );
    final nextLineCaretTop = editableState.renderEditable
        .localToGlobal(nextLineCaretRect.topLeft)
        .dy;

    expect(nextLineCaretTop, greaterThanOrEqualTo(imageBottom - 1));
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

  test('continues checklist markdown as another checklist item', () {
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

    expect(updated.text, '- [x] Done\n- [ ] ');
    expect(updated.selection.baseOffset, 17);
  });

  test('backspace on an empty checklist marker returns to normal text', () {
    final updated = applyMarkdownListEditBehavior(
      const TextEditingValue(
        text: '- [ ] ',
        selection: TextSelection.collapsed(offset: 6),
      ),
      const TextEditingValue(
        text: '- [ ]',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );

    expect(updated.text, '');
    expect(updated.selection.baseOffset, 0);
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

  testWidgets('slash menu converts current line into fenced code tags',
      (tester) async {
    final repository = _StubNoteRepository();

    await tester.pumpWidget(_buildEditor(repository: repository));

    await tester.enterText(_bodyField(), '/');
    await tester.pumpAndSettle();

    expect(find.text('Code block'), findsOneWidget);

    await tester.tap(find.text('Code block'));
    await tester.pumpAndSettle();

    final bodyField = tester.widget<TextField>(_bodyField());
    expect(bodyField.controller?.text, '```\n\n```');
    expect(bodyField.controller?.selection.baseOffset, 4);
    expect(bodyField.focusNode?.hasFocus, isTrue);
  });

  testWidgets('slash menu supports keyboard enter selection', (tester) async {
    final repository = _StubNoteRepository();

    await tester.pumpWidget(_buildEditor(repository: repository));

    await tester.enterText(_bodyField(), '/co');
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    final bodyField = tester.widget<TextField>(_bodyField());
    expect(bodyField.controller?.text, '```\n\n```');
  });

  testWidgets('bold button wraps the current selection in markdown',
      (tester) async {
    final repository = _StubNoteRepository();

    await tester.pumpWidget(_buildEditor(repository: repository));

    await tester.enterText(_bodyField(), 'hello');
    await tester.pumpAndSettle();

    final bodyField = tester.widget<TextField>(_bodyField());
    bodyField.controller!.selection =
        const TextSelection(baseOffset: 0, extentOffset: 5);
    await tester.pump();

    await tester.tap(find.text('Bold'));
    await tester.pumpAndSettle();

    final updatedBodyField = tester.widget<TextField>(_bodyField());
    expect(updatedBodyField.controller?.text, '**hello**');
    expect(updatedBodyField.controller?.selection.baseOffset, 2);
    expect(updatedBodyField.controller?.selection.extentOffset, 7);
  });

  testWidgets('checklist button prefixes the current line with task markdown',
      (tester) async {
    final repository = _StubNoteRepository();

    await tester.pumpWidget(_buildEditor(repository: repository));

    await tester.enterText(_bodyField(), 'Task item');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Checklist'));
    await tester.pumpAndSettle();

    final bodyField = tester.widget<TextField>(_bodyField());
    expect(bodyField.controller?.text, '- [ ] Task item');
  });

  testWidgets('italic shortcut inserts markdown placeholder at the caret',
      (tester) async {
    final repository = _StubNoteRepository();

    await tester.pumpWidget(_buildEditor(repository: repository));

    await tester.tap(_bodyField());
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyI);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyI);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    final bodyField = tester.widget<TextField>(_bodyField());
    expect(bodyField.controller?.text, '*italic text*');
    expect(bodyField.controller?.selection.baseOffset, 1);
    expect(bodyField.controller?.selection.extentOffset, 12);
  });

  testWidgets('loads note content into the unified editor', (tester) async {
    final repository = _StubNoteRepository();
    final note = Note(
      id: 'note-1',
      title: 'Doc note',
      content: 'First paragraph\n\nSecond paragraph',
      documentJson: paragraphDocumentFromEditableText(
        'First paragraph\n\nSecond paragraph',
      ),
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      syncStatus: SyncStatus.synced,
      contentHash: 'hash',
      deviceId: 'device-1',
    );

    await tester.pumpWidget(_buildEditor(repository: repository, note: note));

    final textFields =
        tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(textFields, hasLength(2));
    expect(textFields.last.controller?.text,
        'First paragraph\n\nSecond paragraph');
  });

  testWidgets('editing keeps the same body controller', (tester) async {
    final repository = _StubNoteRepository();

    await tester.pumpWidget(_buildEditor(repository: repository));

    final before = tester.widget<TextField>(_bodyField()).controller;
    await tester.enterText(_bodyField(), 'Hello world');
    await tester.pumpAndSettle();
    final after = tester.widget<TextField>(_bodyField()).controller;

    expect(identical(before, after), isTrue);
    expect(after?.text, 'Hello world');
  });

  testWidgets('loads code blocks as editable markdown content', (tester) async {
    final repository = _StubNoteRepository();
    final note = Note(
      id: 'note-2',
      title: 'Code note',
      content: 'Intro\n\n```dart\nfinal value = 42;\n```',
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

    await tester.pumpWidget(_buildEditor(repository: repository, note: note));

    expect(
      tester.widget<TextField>(_bodyField()).controller?.text,
      'Intro\n\n```dart\nfinal value = 42;\n```',
    );
  });

  testWidgets('arrow up keeps focus inside the body editor', (tester) async {
    final repository = _StubNoteRepository();

    await tester.pumpWidget(_buildEditor(repository: repository));

    await tester.enterText(_bodyField(), '\nSecond paragraph');
    await tester.pumpAndSettle();

    final bodyField = tester.widget<TextField>(_bodyField());
    bodyField.controller!.selection = TextSelection.collapsed(
      offset: bodyField.controller!.text.length,
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();

    final updatedBodyField = tester.widget<TextField>(_bodyField());
    expect(updatedBodyField.focusNode?.hasFocus, isTrue);
  });

  testWidgets('control arrow treats fenced delimiter as one jump',
      (tester) async {
    final repository = _StubNoteRepository();

    await tester.pumpWidget(_buildEditor(repository: repository));

    await tester.enterText(_bodyField(), '```\ncode\n```');
    await tester.pumpAndSettle();

    final bodyField = tester.widget<TextField>(_bodyField());
    bodyField.controller!.selection = const TextSelection.collapsed(offset: 1);
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    final updatedBodyField = tester.widget<TextField>(_bodyField());
    expect(updatedBodyField.controller?.selection.baseOffset, 3);
  });

  testWidgets('arrow up from a new paragraph below heading reaches prior line',
      (tester) async {
    final repository = _StubNoteRepository();

    await tester.pumpWidget(_buildEditor(repository: repository));

    await tester.enterText(_bodyField(), '# h1\nadasdads\n');
    await tester.pumpAndSettle();

    final bodyField = tester.widget<TextField>(_bodyField());
    expect(bodyField.controller?.selection.baseOffset, 14);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();

    final updatedBodyField = tester.widget<TextField>(_bodyField());
    expect(updatedBodyField.controller?.selection.baseOffset, lessThan(14));
  });

  testWidgets(
      'left arrow from empty line below heading reaches prior line once',
      (tester) async {
    final repository = _StubNoteRepository();

    await tester.pumpWidget(_buildEditor(repository: repository));

    await tester.enterText(_bodyField(), '# h1\nadasdads\n');
    await tester.pumpAndSettle();

    final bodyField = tester.widget<TextField>(_bodyField());
    expect(bodyField.controller?.selection.baseOffset, 14);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();

    final updatedBodyField = tester.widget<TextField>(_bodyField());
    expect(updatedBodyField.controller?.selection.baseOffset, 13);
  });

  testWidgets('left arrow moves one character at a time below a heading',
      (tester) async {
    final repository = _StubNoteRepository();

    await tester.pumpWidget(_buildEditor(repository: repository));

    await tester.enterText(_bodyField(), '# h1\nexample');
    await tester.pumpAndSettle();

    final bodyField = tester.widget<TextField>(_bodyField());
    bodyField.controller!.selection = const TextSelection.collapsed(offset: 12);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(_bodyField()).controller?.selection.baseOffset,
      11,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(_bodyField()).controller?.selection.baseOffset,
      10,
    );
  });

  testWidgets('slash menu inserts code block below existing text',
      (tester) async {
    final repository = _StubNoteRepository();

    await tester.pumpWidget(_buildEditor(repository: repository));

    await tester.enterText(_bodyField(), 'Intro\n\n/');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Code block'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(_bodyField()).controller?.text,
      'Intro\n\n```\n\n```',
    );
  });

  testWidgets('slash menu inserts a new block at the current slash line',
      (tester) async {
    final repository = _StubNoteRepository();

    await tester.pumpWidget(_buildEditor(repository: repository));

    await tester.enterText(
      _bodyField(),
      '```\nfirst();\n```\n\n/',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Code block'));
    await tester.pumpAndSettle();

    final bodyField = tester.widget<TextField>(_bodyField());
    expect(
      bodyField.controller?.text,
      '```\nfirst();\n```\n\n```\n\n```',
    );
    expect(bodyField.controller?.selection.baseOffset, 22);
  });

  testWidgets('control a once then delete clears the whole document',
      (tester) async {
    final repository = _StubNoteRepository();

    await tester.pumpWidget(_buildEditor(repository: repository));

    await tester.enterText(_bodyField(), 'Intro\n\n```\nprint("hi");\n```');
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();

    final bodyField = tester.widget<TextField>(_bodyField());
    expect(bodyField.controller?.text, '');
    expect(bodyField.controller?.selection.baseOffset, 0);
    expect(bodyField.focusNode?.hasFocus, isTrue);
  });

  testWidgets('tapping empty editor space restores a caret at the start',
      (tester) async {
    final repository = _StubNoteRepository();

    await tester.pumpWidget(_buildEditor(repository: repository));

    final editor = find.byKey(const ValueKey('document-block-editor'));
    await tester.tapAt(tester.getCenter(editor));
    await tester.pumpAndSettle();

    final bodyField = tester.widget<TextField>(_bodyField());
    expect(bodyField.focusNode?.hasFocus, isTrue);
    expect(bodyField.controller?.selection.baseOffset, 0);
  });

  testWidgets('inactive checklist checkbox toggles markdown state',
      (tester) async {
    final repository = _StubNoteRepository();
    final note = Note(
      id: 'note-3',
      title: 'Checklist note',
      content: '- [ ] Done task\nNext line',
      documentJson: paragraphDocumentFromEditableText(
        '- [ ] Done task\nNext line',
      ),
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      syncStatus: SyncStatus.synced,
      contentHash: 'hash',
      deviceId: 'device-1',
    );

    await tester.pumpWidget(_buildEditor(repository: repository, note: note));
    await tester.pumpAndSettle();

    final bodyField = tester.widget<TextField>(_bodyField());
    bodyField.controller!.selection = TextSelection.collapsed(
      offset: bodyField.controller!.text.length,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('task-checkbox-overlay-0')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(_bodyField()).controller?.text,
      '- [x] Done task\nNext line',
    );
  });

  testWidgets('shows always-visible copy buttons for each fenced block',
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

    await tester
        .pumpWidget(_buildEditor(repository: repository, embedded: true));

    await tester.enterText(
      _bodyField(),
      '```dart\nprint("hi");\n```\n\n```\nprint("bye");\n```',
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Copy code'), findsNWidgets(2));

    await tester.tap(find.byTooltip('Copy code').at(1));
    await tester.pump();

    expect(clipboardText, 'print("bye");');
    expect(find.text('Code snippet copied'), findsOneWidget);
  });
}

Widget _buildEditor({
  required NoteRepository repository,
  Note? note,
  bool embedded = false,
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
        note: note,
        embedded: embedded,
        onClose: embedded ? () {} : null,
      ),
    ),
  );
}

Finder _bodyField() => find.byType(TextField).last;

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

class _RecordingNoteRepository extends _StubNoteRepository {
  final List<Note> createdNotes = <Note>[];
  final List<Note> updatedNotes = <Note>[];

  @override
  Future<void> create(Note note) async {
    createdNotes.add(note);
  }

  @override
  Future<void> update(Note note) async {
    updatedNotes.add(note);
  }
}
