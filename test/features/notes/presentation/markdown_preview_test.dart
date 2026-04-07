import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proper_notes/core/utils/attachments.dart';
import 'package:proper_notes/core/utils/note_document.dart';
import 'package:proper_notes/features/notes/presentation/attachment_image_preview.dart';
import 'package:proper_notes/features/notes/presentation/markdown_preview.dart';

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory =
        await Directory.systemTemp.createTemp('markdown_preview_test_');
    debugAttachmentDirectoryOverride = tempDirectory;
  });

  tearDown(() async {
    debugAttachmentDirectoryOverride = null;
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  Widget buildPreview(String content) {
    return MaterialApp(
      home: Scaffold(
        body: MarkdownPreview(content: content),
      ),
    );
  }

  Widget buildDocumentPreview(NoteDocument document) {
    return MaterialApp(
      home: Scaffold(
        body: MarkdownPreview(document: document),
      ),
    );
  }

  List<String> richTextContents(WidgetTester tester) {
    return tester
        .widgetList<RichText>(find.byType(RichText))
        .map((widget) => widget.text.toPlainText())
        .toList(growable: false);
  }

  testWidgets('renders multiline bullet items as a single list item',
      (tester) async {
    await tester.pumpWidget(
      buildPreview('''
- First bullet line
continued on the next line
- Second bullet
'''),
    );

    expect(find.text('•'), findsNWidgets(2));
    expect(
      richTextContents(tester),
      contains('First bullet line continued on the next line'),
    );
    expect(richTextContents(tester), contains('Second bullet'));
  });

  testWidgets('ends a list block after a blank line', (tester) async {
    await tester.pumpWidget(
      buildPreview('''
- First bullet line
continued on the next line

Standalone paragraph
'''),
    );

    expect(find.text('•'), findsOneWidget);
    expect(
      richTextContents(tester),
      contains('First bullet line continued on the next line'),
    );
    expect(richTextContents(tester), contains('Standalone paragraph'));
  });

  testWidgets('renders task-like markdown as plain bullet text',
      (tester) async {
    await tester.pumpWidget(
      buildPreview('''
- [x] Done
- [ ] Next
'''),
    );

    expect(find.text('•'), findsNWidgets(2));
    expect(richTextContents(tester), contains('[x] Done'));
    expect(richTextContents(tester), contains('[ ] Next'));
  });

  testWidgets('renders attachment markdown as an image preview',
      (tester) async {
    await tester.pumpWidget(
      buildPreview('![Architecture](attachment://preview.png)'),
    );
    await tester.pump();

    expect(find.byType(AttachmentImagePreview), findsOneWidget);
    expect(find.text('Architecture'), findsOneWidget);
  });

  testWidgets('renders fenced code blocks as isolated snippet blocks',
      (tester) async {
    await tester.pumpWidget(
      buildPreview('''
Before **bold**

```dart
final value = '**not bold**';
```

After *italic*
'''),
    );

    expect(richTextContents(tester), contains('Before bold'));
    expect(find.text('DART'), findsOneWidget);
    expect(find.text("final value = '**not bold**';"), findsOneWidget);
    expect(richTextContents(tester), contains('After italic'));
  });

  testWidgets('does not treat inline triple backticks as a fenced block',
      (tester) async {
    await tester.pumpWidget(
      buildPreview('Prefix ```not a fence``` suffix'),
    );

    expect(
      richTextContents(tester),
      contains('Prefix ```not a fence``` suffix'),
    );
  });

  testWidgets('renders code snippets as isolated snippet blocks',
      (tester) async {
    await tester.pumpWidget(
      buildPreview('''
Before **bold**

```dart
final value = '**not bold**';
```

After *italic*
'''),
    );

    expect(richTextContents(tester), contains('Before bold'));
    expect(find.text('DART'), findsOneWidget);
    expect(find.text("final value = '**not bold**';"), findsOneWidget);
    expect(richTextContents(tester), contains('After italic'));
  });

  testWidgets('treats malformed code snippets as plain paragraph text',
      (tester) async {
    await tester.pumpWidget(
      buildPreview('''
```dart
final value = '**still markdown**';
'''),
    );

    expect(
      richTextContents(tester),
      contains("```dart final value = 'still markdown';"),
    );
  });

  testWidgets('renders paragraph blocks from a note document', (tester) async {
    await tester.pumpWidget(
      buildDocumentPreview(
        NoteDocument(
          version: 1,
          blocks: const <NoteBlock>[
            ParagraphBlock(
              id: 'blk-1',
              text: '# Title\n\nParagraph body',
            ),
          ],
        ),
      ),
    );

    expect(find.text('Title'), findsOneWidget);
    expect(richTextContents(tester), contains('Paragraph body'));
  });

  testWidgets('renders unknown code blocks safely from a note document',
      (tester) async {
    await tester.pumpWidget(
      buildDocumentPreview(
        NoteDocument(
          version: 1,
          blocks: const <NoteBlock>[
            UnknownBlock(
              id: 'blk-code',
              type: 'code',
              data: <String, Object?>{
                'id': 'blk-code',
                'type': 'code',
                'language': 'dart',
                'code': 'final value = 1;',
              },
            ),
          ],
        ),
      ),
    );

    expect(find.text('DART'), findsOneWidget);
    expect(find.text('final value = 1;'), findsOneWidget);
  });
}
