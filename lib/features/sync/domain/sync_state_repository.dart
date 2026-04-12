abstract interface class SyncStateRepository {
  Future<String> getOrCreateDeviceId();
  Future<String?> getRemoteSyncCursor();
  Future<void> setRemoteSyncCursor(String token);
}
