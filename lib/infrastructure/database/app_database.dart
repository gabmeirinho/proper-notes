import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

class NotesTable extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get content => text().withDefault(const Constant(''))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  IntColumn get lastSyncedAt => integer().nullable()();
  TextColumn get syncStatus => text()();
  TextColumn get contentHash => text()();
  TextColumn get baseContentHash => text().nullable()();
  TextColumn get deviceId => text()();
  TextColumn get remoteFileId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class AppMetadataTable extends Table {
  IntColumn get keyId => integer()();
  TextColumn get deviceId => text()();
  TextColumn get accountEmail => text().nullable()();
  TextColumn get driveSyncToken => text().nullable()();
  IntColumn get lastFullSyncAt => integer().nullable()();
  IntColumn get lastSuccessfulSyncAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {keyId};
}

@DriftDatabase(
  tables: [
    NotesTable,
    AppMetadataTable,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final directory = await getApplicationSupportDirectory();
    final file = File(p.join(directory.path, 'proper_notes.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
