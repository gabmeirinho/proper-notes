import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/utils/obsidian_import.dart';

class ObsidianImportResult {
  const ObsidianImportResult({
    required this.importedNoteCount,
    required this.failedFileCount,
  });

  final int importedNoteCount;
  final int failedFileCount;

  bool get hasFailures => failedFileCount > 0;
}

class ImportObsidianVault {
  static const String defaultFolderPrefix = 'Imported/Obsidian';

  const ImportObsidianVault({
    required Future<void> Function(String path) ensureFolderExists,
    required Future<void> Function({
      required String title,
      required String content,
      String? folderPath,
    }) createNote,
  })  : _ensureFolderExists = ensureFolderExists,
        _createNote = createNote;

  final Future<void> Function(String path) _ensureFolderExists;
  final Future<void> Function({
    required String title,
    required String content,
    String? folderPath,
  }) _createNote;

  Future<ObsidianImportResult> call({
    required String vaultPath,
    String folderPrefix = defaultFolderPrefix,
  }) async {
    final vaultDirectory = Directory(vaultPath);
    if (!await vaultDirectory.exists()) {
      throw ArgumentError.value(
        vaultPath,
        'vaultPath',
        'Selected Obsidian folder does not exist.',
      );
    }

    final markdownPaths = <String>[];
    await for (final entity
        in vaultDirectory.list(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }

      final relativePath = p.relative(entity.path, from: vaultDirectory.path);
      if (!isImportableObsidianMarkdownPath(relativePath)) {
        continue;
      }

      markdownPaths.add(normalizeObsidianRelativePath(relativePath));
    }

    markdownPaths.sort();

    final ensuredFolders = <String>{};
    var importedNoteCount = 0;
    var failedFileCount = 0;

    for (final relativePath in markdownPaths) {
      try {
        final content = await File(p.join(vaultDirectory.path, relativePath))
            .readAsString();
        final folderPath = obsidianFolderPathFromRelativeMarkdownPath(
          relativePath,
          folderPrefix: folderPrefix,
        );
        if (folderPath != null && ensuredFolders.add(folderPath)) {
          await _ensureFolderExists(folderPath);
        }

        await _createNote(
          title: deriveImportedObsidianNoteTitle(
            relativeMarkdownPath: relativePath,
            content: content,
          ),
          content: content,
          folderPath: folderPath,
        );
        importedNoteCount += 1;
      } catch (_) {
        failedFileCount += 1;
      }
    }

    return ObsidianImportResult(
      importedNoteCount: importedNoteCount,
      failedFileCount: failedFileCount,
    );
  }
}
