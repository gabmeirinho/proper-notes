import 'package:flutter/material.dart';

class MarkdownPreview extends StatelessWidget {
  const MarkdownPreview({
    required this.content,
    this.maxBlocks,
    this.compact = false,
    super.key,
  });

  final String content;
  final int? maxBlocks;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final blocks = _parseMarkdownBlocks(content);
    final visibleBlocks = maxBlocks == null
        ? blocks
        : blocks.take(maxBlocks!).toList(growable: false);

    if (visibleBlocks.isEmpty) {
      return Text(
        'No content',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
      );
    }

    final spacing = compact ? 8.0 : 12.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < visibleBlocks.length; i++) ...[
          _MarkdownBlockView(
            block: visibleBlocks[i],
            compact: compact,
          ),
          if (i < visibleBlocks.length - 1) SizedBox(height: spacing),
        ],
      ],
    );
  }
}

sealed class _MarkdownBlock {
  const _MarkdownBlock();
}

class _ParagraphBlock extends _MarkdownBlock {
  const _ParagraphBlock(this.text);

  final String text;
}

class _HeadingBlock extends _MarkdownBlock {
  const _HeadingBlock({
    required this.level,
    required this.text,
  });

  final int level;
  final String text;
}

class _ListBlock extends _MarkdownBlock {
  const _ListBlock(this.items);

  final List<_ListItem> items;
}

class _ListItem {
  const _ListItem({
    required this.text,
  });

  final String text;
}

class _QuoteBlock extends _MarkdownBlock {
  const _QuoteBlock(this.text);

  final String text;
}

class _CodeBlock extends _MarkdownBlock {
  const _CodeBlock({
    required this.language,
    required this.code,
  });

  final String language;
  final String code;
}

class _DividerBlock extends _MarkdownBlock {
  const _DividerBlock();
}

class _MarkdownBlockView extends StatelessWidget {
  const _MarkdownBlockView({
    required this.block,
    required this.compact,
  });

  final _MarkdownBlock block;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return switch (block) {
      _HeadingBlock(:final level, :final text) => Text(
          text,
          maxLines: compact ? 2 : null,
          overflow: compact ? TextOverflow.ellipsis : null,
          style: switch (level) {
            1 => theme.textTheme.headlineSmall,
            2 => theme.textTheme.titleLarge,
            _ => theme.textTheme.titleMedium,
          }
              ?.copyWith(
            fontWeight: FontWeight.w700,
            height: compact ? 1.2 : 1.25,
            color: colorScheme.onSurface,
          ),
        ),
      _ParagraphBlock(:final text) => RichText(
          maxLines: compact ? 4 : null,
          overflow: compact ? TextOverflow.ellipsis : TextOverflow.clip,
          text: TextSpan(
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurface,
              height: compact ? 1.45 : 1.6,
            ),
            children: _buildInlineSpans(
              text,
              baseStyle: theme.textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurface,
                height: compact ? 1.45 : 1.6,
              ),
              theme: theme,
            ),
          ),
        ),
      _ListBlock(:final items) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final item in items.take(compact ? 3 : items.length))
              Padding(
                padding: EdgeInsets.only(bottom: compact ? 4 : 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(top: compact ? 1 : 2),
                      child: Text(
                        '•',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: RichText(
                        maxLines: compact ? 2 : null,
                        overflow:
                            compact ? TextOverflow.ellipsis : TextOverflow.clip,
                        text: TextSpan(
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface,
                            height: compact ? 1.35 : 1.55,
                          ),
                          children: _buildInlineSpans(
                            item.text,
                            baseStyle: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurface,
                              height: compact ? 1.35 : 1.55,
                            ),
                            theme: theme,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      _QuoteBlock(:final text) => Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 14,
            vertical: compact ? 8 : 10,
          ),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
            border: Border(
              left: BorderSide(
                color: colorScheme.primary,
                width: 3,
              ),
            ),
          ),
          child: RichText(
            maxLines: compact ? 3 : null,
            overflow: compact ? TextOverflow.ellipsis : TextOverflow.clip,
            text: TextSpan(
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface,
                fontStyle: FontStyle.italic,
                height: compact ? 1.4 : 1.55,
              ),
              children: _buildInlineSpans(
                text,
                baseStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface,
                  fontStyle: FontStyle.italic,
                  height: compact ? 1.4 : 1.55,
                ),
                theme: theme,
              ),
            ),
          ),
        ),
      _CodeBlock(:final language, :final code) => Container(
          width: double.infinity,
          padding: EdgeInsets.all(compact ? 10 : 14),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (language.isNotEmpty) ...[
                Text(
                  language.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                SizedBox(height: compact ? 6 : 8),
              ],
              Text(
                code,
                maxLines: compact ? 5 : null,
                overflow: compact ? TextOverflow.ellipsis : null,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                  height: compact ? 1.35 : 1.5,
                ),
              ),
            ],
          ),
        ),
      _DividerBlock() => Divider(
          height: compact ? 8 : 16,
          color: colorScheme.outlineVariant,
        ),
    };
  }
}

List<InlineSpan> _buildInlineSpans(
  String text, {
  required TextStyle? baseStyle,
  required ThemeData theme,
}) {
  final spans = <InlineSpan>[];
  final pattern = RegExp(
    r'((?<!`)`[^`\n]+`(?!`)|\*\*[^*\n]+\*\*|\*[^*\n]+\*)',
  );
  var currentIndex = 0;

  for (final match in pattern.allMatches(text)) {
    if (match.start > currentIndex) {
      spans.add(TextSpan(text: text.substring(currentIndex, match.start)));
    }

    final token = match.group(0)!;
    if (token.startsWith('`')) {
      spans.add(
        TextSpan(
          text: token.substring(1, token.length - 1),
          style: baseStyle?.copyWith(
            fontFamily: 'monospace',
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
      );
    } else if (token.startsWith('**')) {
      spans.add(
        TextSpan(
          text: token.substring(2, token.length - 2),
          style: baseStyle?.copyWith(fontWeight: FontWeight.w700),
        ),
      );
    } else {
      spans.add(
        TextSpan(
          text: token.substring(1, token.length - 1),
          style: baseStyle?.copyWith(fontStyle: FontStyle.italic),
        ),
      );
    }

    currentIndex = match.end;
  }

  if (currentIndex < text.length) {
    spans.add(TextSpan(text: text.substring(currentIndex)));
  }

  return spans;
}

List<_MarkdownBlock> _parseMarkdownBlocks(String content) {
  final normalizedContent = content.replaceAll('\r\n', '\n').trim();
  if (normalizedContent.isEmpty) {
    return const [];
  }

  final lines = normalizedContent.split('\n');
  final blocks = <_MarkdownBlock>[];
  var index = 0;

  while (index < lines.length) {
    final line = lines[index];
    final trimmed = line.trim();

    if (trimmed.isEmpty) {
      index++;
      continue;
    }

    if (_isCodeFenceLine(line)) {
      final language = _codeFenceLanguage(line);
      final codeLines = <String>[];
      index++;
      while (index < lines.length && !_isCodeFenceLine(lines[index])) {
        codeLines.add(lines[index]);
        index++;
      }
      if (index < lines.length) {
        index++;
      }
      blocks.add(
        _CodeBlock(
          language: language,
          code: codeLines.join('\n').trimRight(),
        ),
      );
      continue;
    }

    final headingMatch = RegExp(r'^(#{1,3})\s+(.*)$').firstMatch(trimmed);
    if (headingMatch != null) {
      blocks.add(
        _HeadingBlock(
          level: headingMatch.group(1)!.length,
          text: headingMatch.group(2)!.trim(),
        ),
      );
      index++;
      continue;
    }

    if (trimmed == '---' || trimmed == '***') {
      blocks.add(const _DividerBlock());
      index++;
      continue;
    }

    if (trimmed.startsWith('> ')) {
      final quoteLines = <String>[];
      while (index < lines.length && lines[index].trim().startsWith('> ')) {
        quoteLines.add(lines[index].trim().substring(2).trim());
        index++;
      }
      blocks.add(_QuoteBlock(quoteLines.join(' ')));
      continue;
    }

    if (_isListItem(trimmed)) {
      final items = <_ListItem>[];
      while (index < lines.length && _isListItem(lines[index].trim())) {
        final marker = _parseListMarker(lines[index].trim());
        final itemLines = <String>[marker.text];
        index++;

        while (index < lines.length) {
          final continuation = lines[index];
          final continuationTrimmed = continuation.trim();
          if (continuationTrimmed.isEmpty ||
              _startsNewMarkdownBlock(continuationTrimmed)) {
            break;
          }

          itemLines.add(continuationTrimmed);
          index++;
        }

        items.add(
          _ListItem(
            text: itemLines.join(' '),
          ),
        );
      }
      blocks.add(_ListBlock(items));
      continue;
    }

    final paragraphLines = <String>[];
    while (index < lines.length) {
      final candidate = lines[index].trim();
      if (candidate.isEmpty ||
          _isCodeFenceLine(lines[index]) ||
          RegExp(r'^(#{1,3})\s+').hasMatch(candidate) ||
          candidate.startsWith('> ') ||
          _isListItem(candidate) ||
          candidate == '---' ||
          candidate == '***') {
        break;
      }
      paragraphLines.add(candidate);
      index++;
    }
    if (paragraphLines.isNotEmpty) {
      blocks.add(_ParagraphBlock(paragraphLines.join(' ')));
      continue;
    }

    index++;
  }

  return blocks;
}

bool _isListItem(String line) {
  return line.startsWith('- ') ||
      line.startsWith('* ') ||
      line.startsWith('+ ') ||
      RegExp(r'^\d+\.\s+').hasMatch(line);
}

bool _startsNewMarkdownBlock(String line) {
  return _isCodeFenceLine(line) ||
      RegExp(r'^(#{1,3})\s+').hasMatch(line) ||
      line.startsWith('> ') ||
      _isListItem(line) ||
      line == '---' ||
      line == '***';
}

bool _isCodeFenceLine(String line) {
  return RegExp(r'^\s*```(?:\S+)?\s*$').hasMatch(line);
}

String _codeFenceLanguage(String line) {
  final match = RegExp(r'^\s*```(?:\s*(\S+))?\s*$').firstMatch(line);
  return match?.group(1)?.trim() ?? '';
}

String _stripListMarker(String line) {
  if (line.startsWith('- ') || line.startsWith('* ') || line.startsWith('+ ')) {
    return line.substring(2).trim();
  }

  final orderedMatch = RegExp(r'^\d+\.\s+(.*)$').firstMatch(line);
  if (orderedMatch != null) {
    return orderedMatch.group(1)!.trim();
  }

  return line;
}

_ListItem _parseListMarker(String line) {
  return _ListItem(text: _stripListMarker(line));
}
