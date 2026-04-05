import 'dart:convert';

class NoteDocument {
  const NoteDocument({
    required this.version,
    required this.blocks,
  });

  final int version;
  final List<NoteBlock> blocks;

  factory NoteDocument.fromJsonString(String source) {
    final trimmed = source.trim();
    if (trimmed.isEmpty) {
      return const NoteDocument(
        version: 1,
        blocks: <NoteBlock>[
          ParagraphBlock(
            id: 'legacy-block-1',
            text: '',
          ),
        ],
      );
    }

    final json = jsonDecode(trimmed);
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Note document root must be a JSON object.');
    }

    return NoteDocument.fromJson(json);
  }

  factory NoteDocument.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    final blocksJson = json['blocks'];
    if (version is! int) {
      throw const FormatException('Note document version must be an int.');
    }
    if (blocksJson is! List<dynamic>) {
      throw const FormatException('Note document blocks must be a list.');
    }

    return NoteDocument(
      version: version,
      blocks: blocksJson
          .map(
            (block) => NoteBlock.fromJson(
              Map<String, dynamic>.from(block as Map),
            ),
          )
          .toList(growable: false),
    );
  }

  factory NoteDocument.legacyParagraph(String content) {
    return NoteDocument(
      version: 1,
      blocks: <NoteBlock>[
        ParagraphBlock(
          id: 'legacy-block-1',
          text: content,
        ),
      ],
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'version': version,
      'blocks': blocks.map((block) => block.toJson()).toList(growable: false),
    };
  }

  String toJsonString() {
    return jsonEncode(toJson());
  }
}

sealed class NoteBlock {
  const NoteBlock({
    required this.id,
    required this.type,
  });

  final String id;
  final String type;

  factory NoteBlock.fromJson(Map<String, dynamic> json) {
    final type = json['type'];
    if (type is! String) {
      throw const FormatException('Note block type must be a string.');
    }

    return switch (type) {
      ParagraphBlock.blockType => ParagraphBlock.fromJson(json),
      CodeBlock.blockType => CodeBlock.fromJson(json),
      _ => UnknownBlock.fromJson(json),
    };
  }

  Map<String, Object?> toJson();
}

class ParagraphBlock extends NoteBlock {
  const ParagraphBlock({
    required super.id,
    required this.text,
  }) : super(type: blockType);

  static const String blockType = 'paragraph';

  final String text;

  factory ParagraphBlock.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final text = json['text'];
    if (id is! String) {
      throw const FormatException('Paragraph block id must be a string.');
    }
    if (text is! String) {
      throw const FormatException('Paragraph block text must be a string.');
    }

    return ParagraphBlock(
      id: id,
      text: text,
    );
  }

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'type': type,
      'text': text,
    };
  }
}

class CodeBlock extends NoteBlock {
  const CodeBlock({
    required super.id,
    required this.code,
    this.language = '',
  }) : super(type: blockType);

  static const String blockType = 'code';

  final String language;
  final String code;

  factory CodeBlock.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final language = json['language'];
    final code = json['code'];
    if (id is! String) {
      throw const FormatException('Code block id must be a string.');
    }
    if (language != null && language is! String) {
      throw const FormatException(
        'Code block language must be a string when provided.',
      );
    }
    if (code is! String) {
      throw const FormatException('Code block code must be a string.');
    }

    return CodeBlock(
      id: id,
      language: language ?? '',
      code: code,
    );
  }

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'type': type,
      'language': language,
      'code': code,
    };
  }
}

class UnknownBlock extends NoteBlock {
  const UnknownBlock({
    required super.id,
    required super.type,
    required this.data,
  });

  final Map<String, Object?> data;

  factory UnknownBlock.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final type = json['type'];
    if (id is! String || type is! String) {
      throw const FormatException(
          'Unknown block must have string id and type.');
    }

    return UnknownBlock(
      id: id,
      type: type,
      data: json.map(
        (key, value) => MapEntry(key, value),
      ),
    );
  }

  @override
  Map<String, Object?> toJson() {
    return data;
  }
}

String legacyDocumentFromContent(String content) {
  return NoteDocument.legacyParagraph(content).toJsonString();
}

String editableTextFromDocument(NoteDocument document) {
  for (final block in document.blocks) {
    if (block is! ParagraphBlock && block is! CodeBlock) {
      return '';
    }
  }

  if (document.blocks.isEmpty) {
    return '';
  }

  return document.blocks
      .map((block) => switch (block) {
            ParagraphBlock(:final text) => text,
            CodeBlock(:final language, :final code) => language.isEmpty
                ? '[code]\n$code\n[/code]'
                : '[code:$language]\n$code\n[/code]',
            _ => '',
          })
      .join('\n\n');
}

String paragraphDocumentFromEditableText(String text) {
  final paragraphs = paragraphTextsFromEditableText(text);

  final blocks = <NoteBlock>[
    for (var index = 0; index < paragraphs.length; index++)
      ParagraphBlock(
        id: 'paragraph-${index + 1}',
        text: paragraphs[index],
      ),
  ];

  return NoteDocument(
    version: 1,
    blocks: blocks,
  ).toJsonString();
}

String documentJsonFromEditableText(String text) {
  return NoteDocument(
    version: 1,
    blocks: blocksFromEditableText(text),
  ).toJsonString();
}

List<NoteBlock> blocksFromEditableText(String text) {
  final normalizedText = text.replaceAll('\r\n', '\n');
  if (normalizedText.isEmpty) {
    return const <NoteBlock>[
      ParagraphBlock(
        id: 'paragraph-1',
        text: '',
      ),
    ];
  }

  final lines = normalizedText.split('\n');
  final blocks = <NoteBlock>[];
  final paragraphBuffer = <String>[];

  void flushParagraphBuffer() {
    if (paragraphBuffer.isEmpty) {
      return;
    }

    final paragraphText = paragraphBuffer.join('\n');
    paragraphBuffer.clear();
    final trimmedParagraphText = paragraphText
        .replaceFirst(RegExp(r'^\n+'), '')
        .replaceFirst(RegExp(r'\n+$'), '');
    if (trimmedParagraphText.isEmpty) {
      return;
    }

    final paragraphs = trimmedParagraphText.split(RegExp(r'\n{2,}'));
    for (final paragraph in paragraphs) {
      if (paragraph.isEmpty) {
        continue;
      }
      blocks.add(
        ParagraphBlock(
          id: 'paragraph-${blocks.length + 1}',
          text: paragraph,
        ),
      );
    }
  }

  var index = 0;
  while (index < lines.length) {
    final openingLine = lines[index].trim();
    final language = _codeSnippetLanguage(openingLine);
    if (language == null) {
      paragraphBuffer.add(lines[index]);
      index++;
      continue;
    }

    var closingIndex = -1;
    for (var scan = index + 1; scan < lines.length; scan++) {
      if (_isCodeSnippetClosingTag(lines[scan].trim())) {
        closingIndex = scan;
        break;
      }
    }

    if (closingIndex == -1) {
      paragraphBuffer.add(lines[index]);
      index++;
      continue;
    }

    flushParagraphBuffer();
    blocks.add(
      CodeBlock(
        id: 'code-${blocks.length + 1}',
        language: language,
        code: lines.sublist(index + 1, closingIndex).join('\n'),
      ),
    );
    index = closingIndex + 1;
  }

  flushParagraphBuffer();

  return blocks.isEmpty
      ? const <NoteBlock>[
          ParagraphBlock(
            id: 'paragraph-1',
            text: '',
          ),
        ]
      : List<NoteBlock>.unmodifiable(blocks);
}

List<String> paragraphTextsFromEditableText(String text) {
  final normalizedText = text.replaceAll('\r\n', '\n');
  if (normalizedText.contains('[code') || normalizedText.contains('[/code]')) {
    return <String>[normalizedText];
  }
  return normalizedText.isEmpty
      ? const <String>['']
      : normalizedText.split(RegExp(r'\n{2,}'));
}

bool _isCodeSnippetClosingTag(String line) {
  return line == '[/code]';
}

String? _codeSnippetLanguage(String line) {
  final match = RegExp(r'^\[code(?::([^\]\s]+))?\]$').firstMatch(line);
  return match?.group(1)?.trim() ?? (match != null ? '' : null);
}
