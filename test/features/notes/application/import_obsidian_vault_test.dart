import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proper_notes/features/notes/application/import_obsidian_vault.dart';

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory =
        await Directory.systemTemp.createTemp('import_obsidian_vault_test_');
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('imports markdown notes into Imported/Obsidian and skips hidden files',
      () async {
    await _writeFile(
      tempDirectory,
      'Projects/Plan.md',
      '# Launch Plan\n\nShip it.',
    );
    await _writeFile(
      tempDirectory,
      'Inbox.md',
      'No heading here',
    );
    await _writeFile(
      tempDirectory,
      '.obsidian/config.md',
      '# Hidden config',
    );
    await _writeFile(
      tempDirectory,
      'Projects/Board.canvas',
      'ignored',
    );

    final ensuredFolders = <String>[];
    final createdNotes = <_ImportedNote>[];
    final importVault = ImportObsidianVault(
      ensureFolderExists: (path) async => ensuredFolders.add(path),
      createNote: ({
        required String title,
        required String content,
        String? folderPath,
      }) async {
        createdNotes.add(
          _ImportedNote(
            title: title,
            content: content,
            folderPath: folderPath,
          ),
        );
      },
    );

    final result = await importVault(vaultPath: tempDirectory.path);

    expect(result.importedNoteCount, 2);
    expect(result.failedFileCount, 0);
    expect(ensuredFolders, ['Imported/Obsidian', 'Imported/Obsidian/Projects']);
    expect(
      createdNotes,
      [
        const _ImportedNote(
          title: 'Inbox',
          content: 'No heading here',
          folderPath: 'Imported/Obsidian',
        ),
        const _ImportedNote(
          title: 'Launch Plan',
          content: '# Launch Plan\n\nShip it.',
          folderPath: 'Imported/Obsidian/Projects',
        ),
      ],
    );
  });

  test('counts unreadable markdown files as failed imports', () async {
    await _writeFile(
      tempDirectory,
      'Readable.md',
      '# Readable',
    );
    final unreadablePath = await _writeFile(
      tempDirectory,
      'Unreadable.md',
      '# Unreadable',
    );
    await unreadablePath.writeAsBytes(const <int>[0xff, 0xfe, 0xfd]);

    final createdNotes = <_ImportedNote>[];
    final importVault = ImportObsidianVault(
      ensureFolderExists: (_) async {},
      createNote: ({
        required String title,
        required String content,
        String? folderPath,
      }) async {
        createdNotes.add(
          _ImportedNote(
            title: title,
            content: content,
            folderPath: folderPath,
          ),
        );
      },
    );

    final result = await importVault(vaultPath: tempDirectory.path);

    expect(result.importedNoteCount, 1);
    expect(result.failedFileCount, 1);
    expect(
      createdNotes,
      [
        const _ImportedNote(
          title: 'Readable',
          content: '# Readable',
          folderPath: 'Imported/Obsidian',
        ),
      ],
    );
  });
}

Future<File> _writeFile(
  Directory root,
  String relativePath,
  String content,
) async {
  final file = File('${root.path}/$relativePath');
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
  return file;
}

class _ImportedNote {
  const _ImportedNote({
    required this.title,
    required this.content,
    required this.folderPath,
  });

  final String title;
  final String content;
  final String? folderPath;

  @override
  bool operator ==(Object other) {
    return other is _ImportedNote &&
        other.title == title &&
        other.content == content &&
        other.folderPath == folderPath;
  }

  @override
  int get hashCode => Object.hash(title, content, folderPath);
}
