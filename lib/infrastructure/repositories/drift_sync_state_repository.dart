import 'package:drift/drift.dart';

import '../../features/sync/domain/sync_state_repository.dart';
import '../database/app_database.dart';

class DriftSyncStateRepository implements SyncStateRepository {
  DriftSyncStateRepository(this._database);

  static const _singletonKey = 1;

  final AppDatabase _database;

  @override
  Future<String?> getDriveSyncToken() async {
    final row = await (_database.select(_database.appMetadataTable)
          ..where((tbl) => tbl.keyId.equals(_singletonKey)))
        .getSingleOrNull();

    return row?.driveSyncToken;
  }

  @override
  Future<void> setDriveSyncToken(String token) async {
    await _database
        .into(_database.appMetadataTable)
        .insertOnConflictUpdate(
      AppMetadataTableCompanion(
        keyId: const Value(_singletonKey),
        deviceId: const Value('local-device'),
        driveSyncToken: Value(token),
      ),
    );
  }
}
