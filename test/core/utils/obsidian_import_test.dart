import 'package:flutter_test/flutter_test.dart';
import 'package:proper_notes/core/utils/obsidian_import.dart';

void main() {
  test('imports nested markdown paths and skips hidden vault files by default',
      () {
    expect(
      isImportableObsidianMarkdownPath('Projects/Note.md'),
      isTrue,
    );
    expect(
      isImportableObsidianMarkdownPath('.obsidian/config.md'),
      isFalse,
    );
    expect(
      isImportableObsidianMarkdownPath('Projects/.drafts/Note.md'),
      isFalse,
    );
    expect(
      isImportableObsidianMarkdownPath('Projects/Note.canvas'),
      isFalse,
    );
  });

  test('can include hidden markdown paths when requested', () {
    expect(
      isImportableObsidianMarkdownPath(
        '.obsidian/config.md',
        includeHidden: true,
      ),
      isTrue,
    );
  });

  test('derives folder paths from markdown files with optional prefix', () {
    expect(
      obsidianFolderPathFromRelativeMarkdownPath('Root.md'),
      isNull,
    );
    expect(
      obsidianFolderPathFromRelativeMarkdownPath('Projects/Alpha/Note.md'),
      'Projects/Alpha',
    );
    expect(
      obsidianFolderPathFromRelativeMarkdownPath(
        'Projects/Alpha/Note.md',
        folderPrefix: 'Imported/Obsidian',
      ),
      'Imported/Obsidian/Projects/Alpha',
    );
    expect(
      obsidianFolderPathFromRelativeMarkdownPath(
        'Root.md',
        folderPrefix: 'Imported/Obsidian',
      ),
      'Imported/Obsidian',
    );
  });

  test('derives imported note title from markdown heading or file name', () {
    expect(
      deriveImportedObsidianNoteTitle(
        relativeMarkdownPath: 'Projects/alpha-note.md',
        content: '# Vault Title\n\nBody',
      ),
      'Vault Title',
    );
    expect(
      deriveImportedObsidianNoteTitle(
        relativeMarkdownPath: 'Projects/alpha-note.md',
        content: 'Body without heading',
      ),
      'alpha-note',
    );
  });
}
