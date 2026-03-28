abstract interface class SyncStateRepository {
  Future<String?> getDriveSyncToken();
  Future<void> setDriveSyncToken(String token);
}
