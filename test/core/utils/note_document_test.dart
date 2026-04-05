import 'package:flutter_test/flutter_test.dart';
import 'package:proper_notes/core/utils/note_document.dart';

void main() {
  test('legacy paragraph document round-trips through json', () {
    final document = NoteDocument.legacyParagraph('Hello world');
    final roundTrip = NoteDocument.fromJsonString(document.toJsonString());

    expect(roundTrip.version, 1);
    expect(roundTrip.blocks, hasLength(1));

    final block = roundTrip.blocks.single;
    expect(block, isA<ParagraphBlock>());
    expect((block as ParagraphBlock).text, 'Hello world');
  });

  test('parses and serializes code blocks explicitly', () {
    const source =
        '{"version":1,"blocks":[{"id":"blk-1","type":"code","language":"dart","code":"final a = 1;"}]}';

    final document = NoteDocument.fromJsonString(source);

    expect(document.blocks.single, isA<CodeBlock>());
    expect(document.toJsonString(), source);
  });

  test('preserves unknown non-code blocks during parsing and serialization', () {
    const source =
        '{"version":1,"blocks":[{"id":"img-1","type":"image","url":"local://one"}]}';

    final document = NoteDocument.fromJsonString(source);

    expect(document.blocks.single, isA<UnknownBlock>());
    expect(document.toJsonString(), source);
  });

  test('note document parsing rejects invalid root shape', () {
    expect(
      () => NoteDocument.fromJsonString('[]'),
      throwsFormatException,
    );
  });

  test('editable text joins paragraph blocks with blank lines', () {
    final document = NoteDocument(
      version: 1,
      blocks: const <NoteBlock>[
        ParagraphBlock(id: 'p1', text: 'First'),
        ParagraphBlock(id: 'p2', text: 'Second'),
      ],
    );

    expect(editableTextFromDocument(document), 'First\n\nSecond');
  });

  test('paragraph document splits editable text into paragraph blocks', () {
    final document = NoteDocument.fromJsonString(
      paragraphDocumentFromEditableText('First\n\nSecond'),
    );

    expect(document.blocks, hasLength(2));
    expect((document.blocks[0] as ParagraphBlock).text, 'First');
    expect((document.blocks[1] as ParagraphBlock).text, 'Second');
  });

  test('mixed editable text becomes paragraph and code blocks', () {
    final document = NoteDocument.fromJsonString(
      documentJsonFromEditableText(
        'Intro paragraph\n\n[code:dart]\nfinal value = 42;\n[/code]\n\nTail',
      ),
    );

    expect(document.blocks, hasLength(3));
    expect(document.blocks[0], isA<ParagraphBlock>());
    expect(document.blocks[1], isA<CodeBlock>());
    expect(document.blocks[2], isA<ParagraphBlock>());
    expect((document.blocks[1] as CodeBlock).language, 'dart');
    expect((document.blocks[1] as CodeBlock).code, 'final value = 42;');
  });

  test('editable text round-trips code blocks back to snippet syntax', () {
    final document = NoteDocument(
      version: 1,
      blocks: const <NoteBlock>[
        ParagraphBlock(id: 'p1', text: 'Intro'),
        CodeBlock(id: 'c1', language: 'dart', code: 'print("hi");'),
      ],
    );

    expect(
      editableTextFromDocument(document),
      'Intro\n\n[code:dart]\nprint("hi");\n[/code]',
    );
  });
}
