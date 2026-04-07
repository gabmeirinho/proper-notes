import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:proper_notes/core/utils/attachments.dart';

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('attachments_test_');
    debugAttachmentDirectoryOverride = tempDirectory;
  });

  tearDown(() async {
    debugAttachmentDirectoryOverride = null;
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('parses attachment image markdown line', () {
    final match = parseAttachmentImageMarkdownLine(
      '![diagram](attachment://figure.png)',
    );

    expect(match, isNotNull);
    expect(match!.altText, 'diagram');
    expect(match.attachmentUri, 'attachment://figure.png');
    expect(match.rawText, '![diagram](attachment://figure.png)');
  });

  test('saves image bytes and resolves attachment file', () async {
    final saved = await saveAttachmentImageBytes(
      Uint8List.fromList(_transparentPixelPngBytes),
      extension: 'png',
    );

    expect(saved.attachmentUri, startsWith('attachment://'));
    expect(await saved.file.exists(), isTrue);
    expect(await saved.file.readAsBytes(), _transparentPixelPngBytes);

    final resolved = await resolveAttachmentFile(saved.attachmentUri);
    expect(resolved, isNotNull);
    expect(await resolved!.exists(), isTrue);
    expect(resolved.path, saved.file.path);
  });
}

const List<int> _transparentPixelPngBytes = <int>[
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  1,
  8,
  6,
  0,
  0,
  0,
  31,
  21,
  196,
  137,
  0,
  0,
  0,
  13,
  73,
  68,
  65,
  84,
  120,
  156,
  99,
  248,
  255,
  255,
  63,
  0,
  5,
  254,
  2,
  254,
  167,
  53,
  129,
  132,
  0,
  0,
  0,
  0,
  73,
  69,
  78,
  68,
  174,
  66,
  96,
  130,
];
