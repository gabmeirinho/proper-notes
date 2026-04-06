String deriveTitleFromMarkdown(String content) {
  final lines = content.split('\n');
  var isInsideCodeSnippet = false;

  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (_isCodeSnippetClosingTag(line)) {
      if (isInsideCodeSnippet) {
        isInsideCodeSnippet = false;
      } else if (_isCodeSnippetOpeningTag(line)) {
        isInsideCodeSnippet = true;
      }
      continue;
    }

    if (_isCodeSnippetOpeningTag(line)) {
      isInsideCodeSnippet = true;
      continue;
    }

    if (isInsideCodeSnippet) {
      continue;
    }

    if (!line.startsWith('#')) {
      continue;
    }

    final heading = line.replaceFirst(RegExp(r'^#+\s*'), '').trim();
    if (heading.isNotEmpty) {
      return heading;
    }
  }

  return '';
}

bool _isCodeSnippetOpeningTag(String line) {
  return RegExp(r'^```([^\s`]+)?$').hasMatch(line);
}

bool _isCodeSnippetClosingTag(String line) {
  return line == '```';
}
