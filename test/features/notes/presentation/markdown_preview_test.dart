import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proper_notes/features/notes/presentation/markdown_preview.dart';

void main() {
  Widget buildPreview(String content) {
    return MaterialApp(
      home: Scaffold(
        body: MarkdownPreview(content: content),
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

  testWidgets('keeps fenced code isolated from surrounding markdown',
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
}
