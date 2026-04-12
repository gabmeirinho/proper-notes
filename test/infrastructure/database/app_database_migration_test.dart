import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:proper_notes/core/utils/note_document.dart';
import 'package:proper_notes/infrastructure/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart' show Database, sqlite3;

void main() {
  test('migrates a version 1 database file to schema version 5', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'proper_notes_migration_test_',
    );
    final databaseFile =
        File(p.join(tempDirectory.path, 'proper_notes.sqlite'));
    AppDatabase? appDatabase;

    try {
      final seedDatabase = sqlite3.open(databaseFile.path);
      _createSchemaV1(seedDatabase);
      seedDatabase.dispose();

      appDatabase = AppDatabase.forTesting(NativeDatabase(databaseFile));

      final storedNote = await (appDatabase.select(appDatabase.notesTable)
            ..where((tbl) => tbl.id.equals('note-1')))
          .getSingle();

      expect(storedNote.title, 'Migration test note');
      expect(storedNote.content, 'Existing content');
      expect(
        storedNote.documentJson,
        legacyDocumentFromContent('Existing content'),
      );
      expect(storedNote.deviceId, 'device-1');
      expect(storedNote.folderPath, isNull);
      expect(appDatabase.schemaVersion, 5);

      final folders = await appDatabase.select(appDatabase.foldersTable).get();
      expect(folders, isEmpty);
    } finally {
      await appDatabase?.close();
      if (databaseFile.existsSync()) {
        databaseFile.deleteSync();
      }
      if (tempDirectory.existsSync()) {
        tempDirectory.deleteSync();
      }
    }
  });

  test('migrates a version 2 database file to schema version 5', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'proper_notes_migration_test_',
    );
    final databaseFile =
        File(p.join(tempDirectory.path, 'proper_notes.sqlite'));
    AppDatabase? appDatabase;

    try {
      final seedDatabase = sqlite3.open(databaseFile.path);
      _createSchemaV2(seedDatabase);
      seedDatabase.dispose();

      appDatabase = AppDatabase.forTesting(NativeDatabase(databaseFile));

      final storedNote = await (appDatabase.select(appDatabase.notesTable)
            ..where((tbl) => tbl.id.equals('note-2')))
          .getSingle();

      expect(storedNote.folderPath, 'Projects');
      expect(
        storedNote.documentJson,
        legacyDocumentFromContent('Version 2 content'),
      );
      expect(appDatabase.schemaVersion, 5);
    } finally {
      await appDatabase?.close();
      if (databaseFile.existsSync()) {
        databaseFile.deleteSync();
      }
      if (tempDirectory.existsSync()) {
        tempDirectory.deleteSync();
      }
    }
  });
}

void _createSchemaV1(Database database) {
  database.execute('PRAGMA user_version = 1;');
  database.execute('''
    CREATE TABLE notes_table (
      id TEXT NOT NULL PRIMARY KEY,
      title TEXT NOT NULL DEFAULT '',
      content TEXT NOT NULL DEFAULT '',
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      deleted_at INTEGER NULL,
      last_synced_at INTEGER NULL,
      sync_status TEXT NOT NULL,
      content_hash TEXT NOT NULL,
      base_content_hash TEXT NULL,
      device_id TEXT NOT NULL,
      remote_file_id TEXT NULL
    );
  ''');
  database.execute('''
    CREATE TABLE app_metadata_table (
      key_id INTEGER NOT NULL PRIMARY KEY,
      device_id TEXT NOT NULL,
      account_email TEXT NULL,
      drive_sync_token TEXT NULL,
      last_full_sync_at INTEGER NULL,
      last_successful_sync_at INTEGER NULL
    );
  ''');
  database.execute(
    '''
    INSERT INTO notes_table (
      id,
      title,
      content,
      created_at,
      updated_at,
      deleted_at,
      last_synced_at,
      sync_status,
      content_hash,
      base_content_hash,
      device_id,
      remote_file_id
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''',
    <Object?>[
      'note-1',
      'Migration test note',
      'Existing content',
      1711111111000,
      1711111112000,
      null,
      1711111113000,
      'synced',
      'content-hash-1',
      'content-hash-1',
      'device-1',
      'remote-1',
    ],
  );
}

void _createSchemaV2(Database database) {
  database.execute('PRAGMA user_version = 2;');
  database.execute('''
    CREATE TABLE notes_table (
      id TEXT NOT NULL PRIMARY KEY,
      title TEXT NOT NULL DEFAULT '',
      content TEXT NOT NULL DEFAULT '',
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      deleted_at INTEGER NULL,
      last_synced_at INTEGER NULL,
      sync_status TEXT NOT NULL,
      content_hash TEXT NOT NULL,
      base_content_hash TEXT NULL,
      device_id TEXT NOT NULL,
      folder_path TEXT NULL,
      remote_file_id TEXT NULL
    );
  ''');
  database.execute('''
    CREATE TABLE folders_table (
      path TEXT NOT NULL PRIMARY KEY,
      parent_path TEXT NULL,
      created_at INTEGER NOT NULL
    );
  ''');
  database.execute('''
    CREATE TABLE app_metadata_table (
      key_id INTEGER NOT NULL PRIMARY KEY,
      device_id TEXT NOT NULL,
      account_email TEXT NULL,
      drive_sync_token TEXT NULL,
      last_full_sync_at INTEGER NULL,
      last_successful_sync_at INTEGER NULL
    );
  ''');
  database.execute(
    '''
    INSERT INTO notes_table (
      id,
      title,
      content,
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
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''',
    <Object?>[
      'note-2',
      'Migration test note 2',
      'Version 2 content',
      1711111111000,
      1711111112000,
      null,
      1711111113000,
      'synced',
      'content-hash-2',
      'content-hash-2',
      'device-1',
      'Projects',
      'remote-2',
    ],
  );
}
