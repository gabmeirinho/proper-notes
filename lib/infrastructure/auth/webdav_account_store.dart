import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/domain/auth_session.dart';
import '../../features/auth/domain/sync_account_credentials.dart';
import 'secret_store.dart';

class StoredWebDavAccount {
  const StoredWebDavAccount({
    required this.serverUrl,
    required this.username,
    required this.remoteRoot,
    required this.password,
  });

  final String serverUrl;
  final String username;
  final String remoteRoot;
  final String password;

  AuthSession toSession() {
    final host = Uri.tryParse(serverUrl)?.host;
    final labelHost = (host == null || host.isEmpty) ? serverUrl : host;
    return AuthSession(
      accountLabel: '$username@$labelHost',
      serverUrl: serverUrl,
      username: username,
      remoteRoot: remoteRoot,
    );
  }
}

class WebDavAccountStore {
  WebDavAccountStore({
    SharedPreferences? sharedPreferences,
    SecretStore? secretStore,
  })  : _sharedPreferences = sharedPreferences,
        _secretStore = secretStore;

  static const _serverUrlKey = 'webdav_server_url';
  static const _usernameKey = 'webdav_username';
  static const _remoteRootKey = 'webdav_remote_root';
  static const _passwordKey = 'webdav_password';

  SharedPreferences? _sharedPreferences;
  SecretStore? _secretStore;

  Future<StoredWebDavAccount?> read() async {
    final prefs = await _prefs();
    final serverUrl = prefs.getString(_serverUrlKey)?.trim();
    final username = prefs.getString(_usernameKey)?.trim();
    final remoteRoot = prefs.getString(_remoteRootKey)?.trim();
    final password = await _storage().read(_passwordKey);

    if (serverUrl == null ||
        serverUrl.isEmpty ||
        username == null ||
        username.isEmpty ||
        password == null ||
        password.isEmpty) {
      return null;
    }

    return StoredWebDavAccount(
      serverUrl: serverUrl,
      username: username,
      remoteRoot: (remoteRoot == null || remoteRoot.isEmpty)
          ? 'ProperNotes'
          : remoteRoot,
      password: password,
    );
  }

  Future<void> write(SyncAccountCredentials credentials) async {
    final prefs = await _prefs();
    await prefs.setString(_serverUrlKey, credentials.serverUrl.trim());
    await prefs.setString(_usernameKey, credentials.username.trim());
    await prefs.setString(
      _remoteRootKey,
      credentials.remoteRoot.trim().isEmpty
          ? 'ProperNotes'
          : credentials.remoteRoot.trim(),
    );
    await _storage().write(
      key: _passwordKey,
      value: credentials.password,
    );
  }

  Future<void> clear() async {
    final prefs = await _prefs();
    await prefs.remove(_serverUrlKey);
    await prefs.remove(_usernameKey);
    await prefs.remove(_remoteRootKey);
    await _storage().delete(_passwordKey);
  }

  Future<SharedPreferences> _prefs() async {
    return _sharedPreferences ??= await SharedPreferences.getInstance();
  }

  SecretStore _storage() {
    return _secretStore ??= FlutterSecureSecretStore();
  }
}
