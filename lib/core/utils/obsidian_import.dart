import 'package:path/path.dart' as p;

import 'markdown_title.dart';

String normalizeObsidianRelativePath(String relativePath) {
  final normalized = p.normalize(relativePath.trim());
  final parts = p
      .split(normalized)
      .where((segment) => segment.isNotEmpty && segment != '.')
      .toList(growable: false);
  if (parts.isEmpty) {
    return '';
  }
  return p.posix.joinAll(parts);
}

bool isImportableObsidianMarkdownPath(
  String relativePath, {
  bool includeHidden = false,
}) {
  final normalized = normalizeObsidianRelativePath(relativePath);
  if (normalized.isEmpty) {
    return false;
  }

  final parts = p.posix.split(normalized);
  if (!includeHidden && parts.any((segment) => segment.startsWith('.'))) {
    return false;
  }

  return p.posix.extension(normalized).toLowerCase() == '.md';
}

bool isImportableObsidianFolderPath(
  String relativePath, {
  bool includeHidden = false,
}) {
  final normalized = normalizeObsidianRelativePath(relativePath);
  if (normalized.isEmpty) {
    return false;
  }

  final parts = p.posix.split(normalized);
  if (!includeHidden && parts.any((segment) => segment.startsWith('.'))) {
    return false;
  }

  return true;
}

String? obsidianFolderPathFromRelativeMarkdownPath(
  String relativeMarkdownPath, {
  String? folderPrefix,
}) {
  final normalized = normalizeObsidianRelativePath(relativeMarkdownPath);
  if (normalized.isEmpty) {
    return _normalizeFolderPrefix(folderPrefix);
  }

  final directory = p.posix.dirname(normalized);
  final relativeFolder = directory == '.' ? null : directory;
  return _joinFolderPath(_normalizeFolderPrefix(folderPrefix), relativeFolder);
}

String? joinObsidianFolderPrefix(
  String? folderPrefix,
  String? relativeFolder,
) {
  return _joinFolderPath(
    _normalizeFolderPrefix(folderPrefix),
    relativeFolder == null
        ? null
        : normalizeObsidianRelativePath(relativeFolder),
  );
}

String deriveImportedObsidianNoteTitle({
  required String relativeMarkdownPath,
  required String content,
}) {
  final derivedTitle = deriveTitleFromMarkdown(content).trim();
  if (derivedTitle.isNotEmpty) {
    return derivedTitle;
  }

  final normalizedPath = normalizeObsidianRelativePath(relativeMarkdownPath);
  final fallback = p.posix.basenameWithoutExtension(normalizedPath).trim();
  return fallback.isEmpty ? 'Untitled note' : fallback;
}

String? _normalizeFolderPrefix(String? folderPrefix) {
  if (folderPrefix == null) {
    return null;
  }

  final normalized = normalizeObsidianRelativePath(folderPrefix);
  return normalized.isEmpty ? null : normalized;
}

String? _joinFolderPath(String? prefix, String? relativeFolder) {
  if (prefix == null || prefix.isEmpty) {
    return relativeFolder;
  }
  if (relativeFolder == null || relativeFolder.isEmpty) {
    return prefix;
  }
  return p.posix.join(prefix, relativeFolder);
}
