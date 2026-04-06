import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:proper_notes/core/utils/content_hash.dart';
import 'package:proper_notes/core/utils/note_document.dart';
import 'package:proper_notes/core/utils/obsidian_import.dart';
import 'package:proper_notes/features/notes/domain/sync_status.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

Future<void> main(List<String> args) async {
  try {
    final options = _parseArgs(args);
    if (options.showHelp) {
      stdout.writeln(_usage());
      return;
    }

    final vaultDir = Directory(p.absolute(options.vaultPath!));
    if (!vaultDir.existsSync()) {
      stderr.writeln('Vault directory does not exist: ${vaultDir.path}');
      exitCode = 2;
      return;
    }

    final dbFile = File(p.absolute(options.dbPath ?? _defaultLinuxDbPath()));
    if (!dbFile.existsSync()) {
      stderr.writeln('Database file not found: ${dbFile.path}');
      stderr.writeln(
        'Start Proper Notes once to create it, or pass --db /absolute/path/to/proper_notes.sqlite',
      );
      exitCode = 2;
      return;
    }

    final plan = _scanVault(
      vaultDir: vaultDir,
      folderPrefix: options.folderPrefix,
      includeHidden: options.includeHidden,
    );

    final database = sqlite3.open(dbFile.path);
    try {
      _validateSchema(database);
      final existingRows = database.select(
        'SELECT folder_path, title, content '
        'FROM notes_table WHERE deleted_at IS NULL',
      );
      final resolved = _resolveAgainstExisting(
        scanned: plan.notes,
        existingRows: existingRows,
      );

      _printSummary(
        vaultPath: vaultDir.path,
        dbPath: dbFile.path,
        plan: plan,
        resolved: resolved,
        apply: options.apply,
      );

      if (!options.apply) {
        stdout.writeln('Dry run only. Re-run with --apply to import.');
        return;
      }

      final uuid = const Uuid();
      final deviceId = _getOrCreateDeviceId(database, uuid);
      database.execute('BEGIN IMMEDIATE');
      try {
        for (final folderPath in plan.folders) {
          _ensureFolderExists(database, folderPath);
        }

        for (final note in resolved.notesToImport) {
          if (note.folderPath case final folderPath?) {
            _ensureFolderExists(database, folderPath);
          }

          final timestampMillis = note.timestamp.millisecondsSinceEpoch;
          database.execute(
            '''
            INSERT INTO notes_table (
              id,
              title,
              content,
              document_json,
              created_at,
              updated_at,
              deleted_at,
              last_synced_at,
              sync_status,
              content_hash,
              base_content_hash,
              device_id,
              folder_path,
              remote_file_id
            ) VALUES (?, ?, ?, ?, ?, ?, NULL, NULL, ?, ?, NULL, ?, ?, NULL)
            ''',
            <Object?>[
              uuid.v4(),
              note.title,
              note.content,
              documentJsonFromEditableText(note.content),
              timestampMillis,
              timestampMillis,
              SyncStatus.pendingUpload.name,
              computeContentHash(note.content),
              deviceId,
              note.folderPath,
            ],
          );
        }
        database.execute('COMMIT');
      } catch (_) {
        database.execute('ROLLBACK');
        rethrow;
      }

      stdout.writeln(
        'Imported ${resolved.notesToImport.length} notes into ${dbFile.path}',
      );
    } finally {
      database.dispose();
    }
  } on _UsageError catch (error) {
    stderr.writeln(error.message);
    stderr.writeln('');
    stderr.writeln(_usage());
    exitCode = 64;
  } catch (error, stackTrace) {
    stderr.writeln('Import failed: $error');
    stderr.writeln(stackTrace);
    exitCode = 1;
  }
}

_ImportOptions _parseArgs(List<String> args) {
  String? vaultPath;
  String? dbPath;
  String? folderPrefix;
  var apply = false;
  var includeHidden = false;
  var showHelp = false;

  for (var index = 0; index < args.length; index++) {
    final arg = args[index];
    switch (arg) {
      case '--help':
      case '-h':
        showHelp = true;
      case '--apply':
        apply = true;
      case '--include-hidden':
        includeHidden = true;
      case '--vault':
        vaultPath = _readValue(args, ++index, '--vault');
      case '--db':
        dbPath = _readValue(args, ++index, '--db');
      case '--folder-prefix':
        folderPrefix = _readValue(args, ++index, '--folder-prefix');
      default:
        throw _UsageError('Unknown argument: $arg');
    }
  }

  if (!showHelp && (vaultPath == null || vaultPath.trim().isEmpty)) {
    throw _UsageError('Missing required --vault /path/to/obsidian-vault');
  }

  return _ImportOptions(
    vaultPath: vaultPath,
    dbPath: dbPath,
    folderPrefix: folderPrefix,
    apply: apply,
    includeHidden: includeHidden,
    showHelp: showHelp,
  );
}

String _readValue(List<String> args, int index, String flag) {
  if (index >= args.length) {
    throw _UsageError('Missing value for $flag');
  }
  return args[index];
}

_ScannedVault _scanVault({
  required Directory vaultDir,
  required String? folderPrefix,
  required bool includeHidden,
}) {
  final folders = <String>{};
  final notes = <_PlannedImportedNote>[];

  final normalizedPrefix = joinObsidianFolderPrefix(folderPrefix, null);
  if (normalizedPrefix != null) {
    folders.add(normalizedPrefix);
  }

  final entities = vaultDir
      .listSync(recursive: true, followLinks: false)
      .toList(growable: false)
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final entity in entities) {
    final relativePath = normalizeObsidianRelativePath(
      p.relative(entity.path, from: vaultDir.path),
    );
    if (relativePath.isEmpty) {
      continue;
    }

    if (entity is Directory) {
      if (!isImportableObsidianFolderPath(
        relativePath,
        includeHidden: includeHidden,
      )) {
        continue;
      }

      final folderPath = joinObsidianFolderPrefix(folderPrefix, relativePath);
      if (folderPath != null) {
        folders.add(folderPath);
      }
      continue;
    }

    if (entity is! File ||
        !isImportableObsidianMarkdownPath(
          relativePath,
          includeHidden: includeHidden,
        )) {
      continue;
    }

    final content = entity.readAsStringSync();
    final folderPath = obsidianFolderPathFromRelativeMarkdownPath(
      relativePath,
      folderPrefix: folderPrefix,
    );
    if (folderPath != null) {
      folders.add(folderPath);
    }

    notes.add(
      _PlannedImportedNote(
        sourceRelativePath: relativePath,
        folderPath: folderPath,
        title: deriveImportedObsidianNoteTitle(
          relativeMarkdownPath: relativePath,
          content: content,
        ),
        content: content,
        timestamp: entity.lastModifiedSync().toUtc(),
      ),
    );
  }

  return _ScannedVault(
    folders: folders.toList(growable: false)..sort(),
    notes: notes,
  );
}

_ResolvedImport _resolveAgainstExisting({
  required List<_PlannedImportedNote> scanned,
  required ResultSet existingRows,
}) {
  final existingExactKeys = existingRows
      .map(
        (row) => _exactKey(
          row['folder_path'] as String?,
          row['title'] as String,
          row['content'] as String,
        ),
      )
      .toSet();
  final existingTitleKeys = existingRows
      .map(
        (row) => _titleKey(
          row['folder_path'] as String?,
          row['title'] as String,
        ),
      )
      .toSet();

  final importExactKeys = <String>{};
  final notesToImport = <_PlannedImportedNote>[];
  final exactDuplicatesSkipped = <_PlannedImportedNote>[];
  final conflictingTitles = <_PlannedImportedNote>[];

  for (final note in scanned) {
    final exactKey = _exactKey(note.folderPath, note.title, note.content);
    if (existingExactKeys.contains(exactKey) ||
        importExactKeys.contains(exactKey)) {
      exactDuplicatesSkipped.add(note);
      continue;
    }

    if (existingTitleKeys.contains(_titleKey(note.folderPath, note.title))) {
      conflictingTitles.add(note);
    }

    importExactKeys.add(exactKey);
    notesToImport.add(note);
  }

  return _ResolvedImport(
    notesToImport: notesToImport,
    exactDuplicatesSkipped: exactDuplicatesSkipped,
    conflictingTitles: conflictingTitles,
  );
}

void _validateSchema(Database database) {
  for (final tableName in const [
    'notes_table',
    'folders_table',
    'app_metadata_table',
  ]) {
    final rows = database.select(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      <Object?>[tableName],
    );
    if (rows.isEmpty) {
      throw _UsageError(
        'Database at the selected path is missing table "$tableName".',
      );
    }
  }
}

String _getOrCreateDeviceId(Database database, Uuid uuid) {
  final rows = database.select(
    'SELECT device_id FROM app_metadata_table WHERE key_id = 1',
  );
  if (rows.isNotEmpty) {
    final existing = (rows.single['device_id'] as String?)?.trim();
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
  }

  final generated = uuid.v4();
  database.execute(
    '''
    INSERT INTO app_metadata_table (
      key_id,
      device_id,
      account_email,
      drive_sync_token,
      last_full_sync_at,
      last_successful_sync_at
    ) VALUES (1, ?, NULL, NULL, NULL, NULL)
    ON CONFLICT(key_id) DO UPDATE SET device_id = excluded.device_id
    ''',
    <Object?>[generated],
  );
  return generated;
}

void _ensureFolderExists(Database database, String path) {
  final normalized = normalizeObsidianRelativePath(path);
  if (normalized.isEmpty) {
    return;
  }

  final now = DateTime.now().toUtc().millisecondsSinceEpoch;
  final segments = normalized.split('/');
  for (var depth = 0; depth < segments.length; depth++) {
    final currentPath = segments.take(depth + 1).join('/');
    final parentPath = depth == 0 ? null : segments.take(depth).join('/');
    database.execute(
      '''
      INSERT OR IGNORE INTO folders_table (path, parent_path, created_at)
      VALUES (?, ?, ?)
      ''',
      <Object?>[currentPath, parentPath, now],
    );
  }
}

String _exactKey(String? folderPath, String title, String content) {
  return '${folderPath ?? ''}\u0000$title\u0000$content';
}

String _titleKey(String? folderPath, String title) {
  return '${folderPath ?? ''}\u0000$title';
}

void _printSummary({
  required String vaultPath,
  required String dbPath,
  required _ScannedVault plan,
  required _ResolvedImport resolved,
  required bool apply,
}) {
  stdout.writeln('Obsidian import ${apply ? 'apply' : 'preview'}');
  stdout.writeln('Vault: $vaultPath');
  stdout.writeln('Database: $dbPath');
  stdout.writeln('Folders to ensure: ${plan.folders.length}');
  stdout.writeln('Markdown files found: ${plan.notes.length}');
  stdout.writeln(
    'Exact duplicates skipped: ${resolved.exactDuplicatesSkipped.length}',
  );
  stdout.writeln('Notes to import: ${resolved.notesToImport.length}');
  stdout.writeln(
    'Folder/title conflicts that will import as extra local notes: '
    '${resolved.conflictingTitles.length}',
  );

  final preview = resolved.notesToImport.take(8).toList(growable: false);
  if (preview.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln('Preview:');
    for (final note in preview) {
      final folder = note.folderPath ?? '(root)';
      stdout
          .writeln('- [$folder] ${note.title}  <-  ${note.sourceRelativePath}');
    }
    if (resolved.notesToImport.length > preview.length) {
      stdout.writeln(
        '- ... and ${resolved.notesToImport.length - preview.length} more',
      );
    }
  }
}

String _defaultLinuxDbPath() {
  final xdgDataHome = Platform.environment['XDG_DATA_HOME'];
  final home = Platform.environment['HOME'];
  final baseDir = xdgDataHome ??
      (home == null || home.isEmpty ? null : p.join(home, '.local', 'share'));
  if (baseDir == null) {
    throw _UsageError(
      'Could not infer a default database path. Pass --db /absolute/path/to/proper_notes.sqlite',
    );
  }

  return p.join(baseDir, 'com.gabriel.propernotes', 'proper_notes.sqlite');
}

String _usage() {
  return '''
Import Obsidian markdown notes into Proper Notes.

Usage:
  dart run scripts/import_obsidian.dart --vault /path/to/vault [options]

Options:
  --vault PATH           Required. Root path of the Obsidian vault.
  --db PATH              Optional. Proper Notes SQLite database path.
                         Default: ${_defaultDbPathExample()}
  --folder-prefix PATH   Optional. Import everything under a root folder such as
                         "Imported/Obsidian".
  --include-hidden       Optional. Include hidden files/directories such as
                         ".obsidian". Default is to skip them.
  --apply                Write changes. Without this flag the script is dry-run only.
  --help, -h             Show this help text.

Examples:
  dart run scripts/import_obsidian.dart \\
    --vault ~/Documents/MyVault

  dart run scripts/import_obsidian.dart \\
    --vault ~/Documents/MyVault \\
    --folder-prefix Imported/Obsidian \\
    --apply
''';
}

String _defaultDbPathExample() {
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) {
    return '/home/YOU/.local/share/com.gabriel.propernotes/proper_notes.sqlite';
  }
  return p.join(
    home,
    '.local',
    'share',
    'com.gabriel.propernotes',
    'proper_notes.sqlite',
  );
}

class _ImportOptions {
  const _ImportOptions({
    required this.vaultPath,
    required this.dbPath,
    required this.folderPrefix,
    required this.apply,
    required this.includeHidden,
    required this.showHelp,
  });

  final String? vaultPath;
  final String? dbPath;
  final String? folderPrefix;
  final bool apply;
  final bool includeHidden;
  final bool showHelp;
}

class _ScannedVault {
  const _ScannedVault({
    required this.folders,
    required this.notes,
  });

  final List<String> folders;
  final List<_PlannedImportedNote> notes;
}

class _ResolvedImport {
  const _ResolvedImport({
    required this.notesToImport,
    required this.exactDuplicatesSkipped,
    required this.conflictingTitles,
  });

  final List<_PlannedImportedNote> notesToImport;
  final List<_PlannedImportedNote> exactDuplicatesSkipped;
  final List<_PlannedImportedNote> conflictingTitles;
}

class _PlannedImportedNote {
  const _PlannedImportedNote({
    required this.sourceRelativePath,
    required this.folderPath,
    required this.title,
    required this.content,
    required this.timestamp,
  });

  final String sourceRelativePath;
  final String? folderPath;
  final String title;
  final String content;
  final DateTime timestamp;
}

class _UsageError implements Exception {
  const _UsageError(this.message);

  final String message;
}
