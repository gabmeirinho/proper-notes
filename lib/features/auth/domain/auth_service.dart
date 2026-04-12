import 'auth_session.dart';
import 'sync_account_credentials.dart';

abstract interface class AuthService {
  Future<AuthSession?> restoreSession();
  Future<void> testConnection(SyncAccountCredentials credentials);
  Future<AuthSession> saveConnection(SyncAccountCredentials credentials);
  Future<void> clearConnection();
}
