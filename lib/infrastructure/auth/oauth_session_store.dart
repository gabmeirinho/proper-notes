import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/domain/auth_session.dart';
import 'secret_store.dart';

class StoredOAuthSession {
  const StoredOAuthSession({
    required this.session,
    this.refreshToken,
    this.accessToken,
    this.accessTokenExpiresAt,
  });

  final AuthSession session;
  final String? refreshToken;
  final String? accessToken;
  final DateTime? accessTokenExpiresAt;
}

abstract interface class OAuthSessionStore {
  Future<StoredOAuthSession?> read();
  Future<void> write({
    required AuthSession session,
    String? refreshToken,
    String? accessToken,
    DateTime? accessTokenExpiresAt,
  });
  Future<void> clear();
}

class SharedPreferencesOAuthSessionStore implements OAuthSessionStore {
  SharedPreferencesOAuthSessionStore({
    SharedPreferences? sharedPreferences,
    SecretStore? secretStore,
  })  : _sharedPreferences = sharedPreferences,
        _secretStore = secretStore;

  static const _refreshTokenKey = 'google_refresh_token';
  static const _accessTokenKey = 'google_access_token';
  static const _emailKey = 'google_email';
  static const _displayNameKey = 'google_display_name';
  static const _accessTokenExpiresAtKey = 'google_access_token_expires_at';

  SharedPreferences? _sharedPreferences;
  SecretStore? _secretStore;

  @override
  Future<StoredOAuthSession?> read() async {
    final prefs = await _prefs();
    final email = prefs.getString(_emailKey);
    final displayName = prefs.getString(_displayNameKey);
    final refreshToken = await _storage().read(_refreshTokenKey);
    final accessToken = await _storage().read(_accessTokenKey);
    final accessTokenExpiresAtMillis = prefs.getInt(_accessTokenExpiresAtKey);

    if (email == null || email.isEmpty) {
      return null;
    }

    return StoredOAuthSession(
      session: AuthSession(
        email: email,
        displayName:
            (displayName == null || displayName.isEmpty) ? email : displayName,
      ),
      refreshToken: refreshToken,
      accessToken: accessToken,
      accessTokenExpiresAt: accessTokenExpiresAtMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              accessTokenExpiresAtMillis,
              isUtc: true,
            ),
    );
  }

  @override
  Future<void> write({
    required AuthSession session,
    String? refreshToken,
    String? accessToken,
    DateTime? accessTokenExpiresAt,
  }) async {
    final prefs = await _prefs();
    await prefs.setString(_emailKey, session.email);
    await prefs.setString(_displayNameKey, session.displayName);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _storage().write(key: _refreshTokenKey, value: refreshToken);
    }
    if (accessToken != null && accessToken.isNotEmpty) {
      await _storage().write(key: _accessTokenKey, value: accessToken);
    }
    if (accessTokenExpiresAt != null) {
      await prefs.setInt(
        _accessTokenExpiresAtKey,
        accessTokenExpiresAt.toUtc().millisecondsSinceEpoch,
      );
    }
  }

  @override
  Future<void> clear() async {
    final prefs = await _prefs();
    await _storage().delete(_refreshTokenKey);
    await _storage().delete(_accessTokenKey);
    await prefs.remove(_emailKey);
    await prefs.remove(_displayNameKey);
    await prefs.remove(_accessTokenExpiresAtKey);
  }

  Future<SharedPreferences> _prefs() async {
    return _sharedPreferences ??= await SharedPreferences.getInstance();
  }

  SecretStore _storage() {
    return _secretStore ??= FlutterSecureSecretStore();
  }
}
