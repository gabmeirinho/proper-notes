import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../features/sync/domain/sync_state_repository.dart';
import '../database/app_database.dart';

class DriftSyncStateRepository implements SyncStateRepository {
  DriftSyncStateRepository(
    this._database, {
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  static const _singletonKey = 1;

  final AppDatabase _database;
  final Uuid _uuid;

  @override
  Future<String> getOrCreateDeviceId() async {
    final row = await _getMetadataRow();
    final existingDeviceId = row?.deviceId.trim();
    if (existingDeviceId != null && existingDeviceId.isNotEmpty) {
      return existingDeviceId;
    }

    final generatedDeviceId = _uuid.v4();
    if (row == null) {
      await _database.into(_database.appMetadataTable).insert(
            AppMetadataTableCompanion.insert(
              keyId: const Value(_singletonKey),
              deviceId: generatedDeviceId,
            ),
          );
    } else {
      await (_database.update(_database.appMetadataTable)
            ..where((tbl) => tbl.keyId.equals(_singletonKey)))
          .write(
        AppMetadataTableCompanion(
          deviceId: Value(generatedDeviceId),
        ),
      );
    }

    return generatedDeviceId;
  }

  @override
  Future<String?> getRemoteSyncCursor() async {
    final row = await _getMetadataRow();
    final remoteSyncCursor = row?.remoteSyncCursor?.trim();
    if (remoteSyncCursor != null && remoteSyncCursor.isNotEmpty) {
      return remoteSyncCursor;
    }

    final legacyDriveToken = row?.driveSyncToken?.trim();
    if (legacyDriveToken == null || legacyDriveToken.isEmpty) {
      return null;
    }

    await _promoteLegacyDriveSyncToken(
      deviceId: row!.deviceId,
      legacyDriveToken: legacyDriveToken,
    );
    return legacyDriveToken;
  }

  @override
  Future<void> setRemoteSyncCursor(String token) async {
    final row = await _getMetadataRow();
    final deviceId = row == null || row.deviceId.trim().isEmpty
        ? await getOrCreateDeviceId()
        : row.deviceId;

    if (row == null) {
      await _database.into(_database.appMetadataTable).insert(
            AppMetadataTableCompanion.insert(
              keyId: const Value(_singletonKey),
              deviceId: deviceId,
              remoteSyncCursor: Value(token),
            ),
          );
      return;
    }

    await (_database.update(_database.appMetadataTable)
          ..where((tbl) => tbl.keyId.equals(_singletonKey)))
        .write(
      AppMetadataTableCompanion(
        deviceId: Value(deviceId),
        remoteSyncCursor: Value(token),
      ),
    );
  }

  Future<AppMetadataTableData?> _getMetadataRow() {
    return (_database.select(_database.appMetadataTable)
          ..where((tbl) => tbl.keyId.equals(_singletonKey)))
        .getSingleOrNull();
  }

  Future<void> _promoteLegacyDriveSyncToken({
    required String deviceId,
    required String legacyDriveToken,
  }) async {
    await (_database.update(_database.appMetadataTable)
          ..where((tbl) => tbl.keyId.equals(_singletonKey)))
        .write(
      AppMetadataTableCompanion(
        deviceId: Value(deviceId),
        remoteSyncCursor: Value(legacyDriveToken),
      ),
    );
  }
}
