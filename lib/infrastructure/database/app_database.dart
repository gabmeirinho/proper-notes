import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/utils/note_document.dart';

part 'app_database.g.dart';

class NotesTable extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get content => text().withDefault(const Constant(''))();
  TextColumn get documentJson => text().withDefault(const Constant(''))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  IntColumn get lastSyncedAt => integer().nullable()();
  TextColumn get syncStatus => text()();
  TextColumn get contentHash => text()();
  TextColumn get baseContentHash => text().nullable()();
  TextColumn get deviceId => text()();
  TextColumn get folderPath => text().nullable()();
  TextColumn get remoteFileId => text().nullable()();
  TextColumn get remoteEtag => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class FoldersTable extends Table {
  TextColumn get path => text()();
  TextColumn get parentPath => text().nullable()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {path};
}

class AppMetadataTable extends Table {
  IntColumn get keyId => integer()();
  TextColumn get deviceId => text()();
  TextColumn get accountEmail => text().nullable()();
  TextColumn get driveSyncToken => text().nullable()();
  TextColumn get accountLabel => text().nullable()();
  TextColumn get remoteBaseUrl => text().nullable()();
  TextColumn get remoteUsername => text().nullable()();
  TextColumn get remoteSyncCursor => text().nullable()();
  TextColumn get remoteCollectionTag => text().nullable()();
  IntColumn get remoteFormatVersion => integer().nullable()();
  IntColumn get lastFullSyncAt => integer().nullable()();
  IntColumn get lastSuccessfulSyncAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {keyId};
}

@DriftDatabase(
  tables: [
    NotesTable,
    FoldersTable,
    AppMetadataTable,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (migrator) async {
          await migrator.createAll();
        },
        onUpgrade: (migrator, from, to) async {
          if (from < 2) {
            await migrator.addColumn(notesTable, notesTable.folderPath);
            await migrator.createTable(foldersTable);
          }
          if (from < 3) {
            await migrator.addColumn(notesTable, notesTable.documentJson);
            final notes = await select(notesTable).get();
            for (final note in notes) {
              await (update(notesTable)..where((tbl) => tbl.id.equals(note.id)))
                  .write(
                NotesTableCompanion(
                  documentJson: Value(legacyDocumentFromContent(note.content)),
                ),
              );
            }
          }
          if (from < 4) {
            await migrator.addColumn(
                appMetadataTable, appMetadataTable.accountLabel);
            await migrator.addColumn(
                appMetadataTable, appMetadataTable.remoteBaseUrl);
            await migrator.addColumn(
                appMetadataTable, appMetadataTable.remoteUsername);
            await migrator.addColumn(
                appMetadataTable, appMetadataTable.remoteSyncCursor);
            await migrator.addColumn(
                appMetadataTable, appMetadataTable.remoteCollectionTag);
            await migrator.addColumn(
                appMetadataTable, appMetadataTable.remoteFormatVersion);
          }
          if (from < 5) {
            await migrator.addColumn(notesTable, notesTable.remoteEtag);
          }
        },
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final directory = await getApplicationSupportDirectory();
    final file = File(p.join(directory.path, 'proper_notes.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
