import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proper_notes/infrastructure/database/app_database.dart';
import 'package:proper_notes/infrastructure/repositories/drift_sync_state_repository.dart';
import 'package:uuid/data.dart';
import 'package:uuid/uuid.dart';

void main() {
  late AppDatabase database;
  late DriftSyncStateRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = DriftSyncStateRepository(
      database,
      uuid: const _FixedUuid('device-123'),
    );
  });

  tearDown(() async {
    await database.close();
  });

  test('getOrCreateDeviceId creates and then reuses a persisted device id',
      () async {
    final first = await repository.getOrCreateDeviceId();
    final second = await repository.getOrCreateDeviceId();

    expect(first, 'device-123');
    expect(second, 'device-123');
  });

  test('setRemoteSyncCursor preserves the stored device id', () async {
    final deviceId = await repository.getOrCreateDeviceId();

    await repository.setRemoteSyncCursor('token-1');
    final token = await repository.getRemoteSyncCursor();
    final persistedDeviceId = await repository.getOrCreateDeviceId();

    expect(deviceId, 'device-123');
    expect(token, 'token-1');
    expect(persistedDeviceId, 'device-123');
  });
}

class _FixedUuid extends Uuid {
  const _FixedUuid(this.value);

  final String value;

  @override
  String v4({
    V4Options? config,
    Map<String, dynamic>? options,
  }) =>
      value;
}
