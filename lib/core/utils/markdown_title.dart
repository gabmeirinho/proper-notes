String deriveTitleFromMarkdown(String content) {
  final lines = content.split('\n');

  for (final rawLine in lines) {
    final line = rawLine.trim();
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
