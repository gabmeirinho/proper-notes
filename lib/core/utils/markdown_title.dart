String deriveTitleFromMarkdown(String content) {
  final lines = content.split('\n');
  var isInsideCodeSnippet = false;

  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (_isCodeSnippetOpeningTag(line)) {
      isInsideCodeSnippet = true;
      continue;
    }

    if (_isCodeSnippetClosingTag(line)) {
      isInsideCodeSnippet = false;
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
  return RegExp(r'^\[code(?::[^\]\s]+)?\]$').hasMatch(line);
}

bool _isCodeSnippetClosingTag(String line) {
  return line == '[/code]';
}
