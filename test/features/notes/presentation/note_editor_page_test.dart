import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proper_notes/features/notes/presentation/note_editor_page.dart';

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

  test('renders inactive code fences and code lines with code styling', () {
    final fenceSpans = buildInactiveMarkdownLineSpans(
      '```dart',
      baseStyle: baseStyle,
      colorScheme: colorScheme,
      isInCodeBlock: true,
      isCodeFenceLine: true,
    );
    final codeLineSpans = buildInactiveMarkdownLineSpans(
      'print("hi");',
      baseStyle: baseStyle,
      colorScheme: colorScheme,
      isInCodeBlock: true,
    );

    expect(fenceSpans.length, 1);
    expect((fenceSpans.single as TextSpan).text, 'dart');
    expect((fenceSpans.single as TextSpan).style?.fontFamily, 'monospace');

    expect(codeLineSpans.length, 1);
    expect((codeLineSpans.single as TextSpan).text, 'print("hi");');
    expect((codeLineSpans.single as TextSpan).style?.fontFamily, 'monospace');
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
}
