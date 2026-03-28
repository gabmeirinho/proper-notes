import 'package:flutter_test/flutter_test.dart';
import 'package:proper_notes/features/auth/domain/auth_session.dart';
import 'package:proper_notes/infrastructure/auth/oauth_session_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('writes and reads session metadata and refresh token', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = SharedPreferencesOAuthSessionStore(
      secretStore: _FakeSecretStore(),
    );

    await store.write(
      session: const AuthSession(
        email: 'user@example.com',
        displayName: 'User',
      ),
      refreshToken: 'refresh-token-123',
      accessToken: 'access-token-456',
      accessTokenExpiresAt: DateTime.utc(2026, 3, 26, 12),
    );

    final stored = await store.read();

    expect(stored, isNotNull);
    expect(stored!.session.email, 'user@example.com');
    expect(stored.session.displayName, 'User');
    expect(stored.refreshToken, 'refresh-token-123');
    expect(stored.accessToken, 'access-token-456');
    expect(stored.accessTokenExpiresAt, DateTime.utc(2026, 3, 26, 12));
  });

  test('clear removes both visible metadata and refresh token', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final secretStore = _FakeSecretStore();
    final store = SharedPreferencesOAuthSessionStore(
      secretStore: secretStore,
    );

    await store.write(
      session: const AuthSession(
        email: 'user@example.com',
        displayName: 'User',
      ),
      refreshToken: 'refresh-token-123',
    );

    await store.clear();

    final stored = await store.read();
    expect(stored, isNull);
    expect(secretStore.values, isEmpty);
  });
}

class _FakeSecretStore implements SecretStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async {
    return values[key];
  }

  @override
  Future<void> write({
    required String key,
    required String value,
  }) async {
    values[key] = value;
  }
}
