import 'package:flutter_test/flutter_test.dart';
import 'package:proper_notes/core/utils/markdown_title.dart';

void main() {
  test('derives a title from the first markdown heading', () {
    final title = deriveTitleFromMarkdown('''
Intro text

# Main title

## Secondary
''');

    expect(title, 'Main title');
  });

  test('returns empty when no markdown heading exists', () {
    final title = deriveTitleFromMarkdown('Plain text note without headings');

    expect(title, isEmpty);
  });

  test('ignores empty heading markers', () {
    final title = deriveTitleFromMarkdown('''
#
##   
# Useful title
''');

    expect(title, 'Useful title');
  });

  test('ignores headings inside code snippets', () {
    final title = deriveTitleFromMarkdown('''
[code]
# Not a title
[/code]

## Actual title
''');

    expect(title, 'Actual title');
  });
}
