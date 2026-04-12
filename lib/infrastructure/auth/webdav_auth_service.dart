import '../../features/auth/domain/auth_service.dart';
import '../../features/auth/domain/auth_session.dart';
import '../../features/auth/domain/sync_account_credentials.dart';
import '../sync/webdav_client.dart';
import 'webdav_account_store.dart';

class WebDavAuthService implements AuthService {
  WebDavAuthService({
    required WebDavAccountStore accountStore,
    WebDavClient? webDavClient,
  })  : _accountStore = accountStore,
        _webDavClient = webDavClient ?? WebDavClient();

  final WebDavAccountStore _accountStore;
  final WebDavClient _webDavClient;

  @override
  Future<AuthSession?> restoreSession() async {
    final account = await _accountStore.read();
    return account?.toSession();
  }

  @override
  Future<void> testConnection(SyncAccountCredentials credentials) {
    return _webDavClient.testConnection(credentials);
  }

  @override
  Future<AuthSession> saveConnection(SyncAccountCredentials credentials) async {
    await _webDavClient.testConnection(credentials);
    await _accountStore.write(credentials);
    final account = await _accountStore.read();
    if (account == null) {
      throw Exception('Failed to persist the WebDAV account.');
    }
    return account.toSession();
  }

  @override
  Future<void> clearConnection() {
    return _accountStore.clear();
  }
}
