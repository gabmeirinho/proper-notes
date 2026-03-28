abstract interface class SyncStateRepository {
  Future<String> getOrCreateDeviceId();
  Future<String?> getDriveSyncToken();
  Future<void> setDriveSyncToken(String token);
}
