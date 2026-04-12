import 'package:flutter_test/flutter_test.dart';
import 'package:proper_notes/features/auth/application/auth_controller.dart';
import 'package:proper_notes/features/auth/domain/auth_service.dart';
import 'package:proper_notes/features/auth/domain/auth_session.dart';
import 'package:proper_notes/features/auth/domain/sync_account_credentials.dart';

void main() {
  test('restore loads an existing session', () async {
    final controller = AuthController(
      authService: _FakeAuthService(
        restoredSession: const AuthSession(
          email: 'restored@example.com',
          displayName: 'Restored User',
        ),
      ),
    );

    await controller.restore();

    expect(controller.isSignedIn, isTrue);
    expect(controller.hasResolvedInitialSession, isTrue);
    expect(controller.session?.email, 'restored@example.com');
    expect(controller.errorMessage, isNull);
  });

  test('saveConnection updates session state', () async {
    final controller = AuthController(
      authService: _FakeAuthService(
        saveConnectionSession: const AuthSession(
          email: 'signed@example.com',
          displayName: 'Signed In',
        ),
      ),
    );

    await controller.saveConnection(_credentials);

    expect(controller.isSignedIn, isTrue);
    expect(controller.hasResolvedInitialSession, isTrue);
    expect(controller.session?.displayName, 'Signed In');
    expect(controller.errorMessage, isNull);
  });

  test('clearConnection clears session state', () async {
    final authService = _FakeAuthService(
      restoredSession: const AuthSession(
        email: 'restored@example.com',
        displayName: 'Restored User',
      ),
    );
    final controller = AuthController(authService: authService);

    await controller.restore();
    await controller.clearConnection();

    expect(controller.isSignedIn, isFalse);
    expect(controller.hasResolvedInitialSession, isTrue);
    expect(controller.session, isNull);
    expect(authService.didClearConnection, isTrue);
  });

  test('stores error message when auth operation fails', () async {
    final controller = AuthController(
      authService: _FakeAuthService(
        signInError: Exception('sign-in failed'),
      ),
    );

    await controller.saveConnection(_credentials);

    expect(controller.isSignedIn, isFalse);
    expect(controller.hasResolvedInitialSession, isFalse);
    expect(controller.errorMessage, contains('sign-in failed'));
  });

  test('summarizes common auth configuration errors', () async {
    final controller = AuthController(
      authService: _FakeAuthService(
        signInError: Exception('Missing Google client id for this build'),
      ),
    );

    await controller.saveConnection(_credentials);

    expect(
      controller.errorMessage,
      'Missing Google client id for this build',
    );
  });

  test('restore resolves initial session state even when restore fails',
      () async {
    final controller = AuthController(
      authService: _FakeAuthService(
        restoreError: Exception('restore failed'),
      ),
    );

    await controller.restore();

    expect(controller.isSignedIn, isFalse);
    expect(controller.hasResolvedInitialSession, isTrue);
    expect(controller.errorMessage, contains('restore failed'));
  });
}

class _FakeAuthService implements AuthService {
  _FakeAuthService({
    this.restoredSession,
    this.saveConnectionSession,
    this.signInError,
    this.restoreError,
  });

  final AuthSession? restoredSession;
  final AuthSession? saveConnectionSession;
  final Object? signInError;
  final Object? restoreError;
  bool didClearConnection = false;

  @override
  Future<AuthSession?> restoreSession() async {
    if (restoreError != null) {
      throw restoreError!;
    }

    return restoredSession;
  }

  @override
  Future<void> testConnection(SyncAccountCredentials credentials) async {}

  @override
  Future<AuthSession> saveConnection(SyncAccountCredentials credentials) async {
    if (signInError != null) {
      throw signInError!;
    }

    return saveConnectionSession ??
        const AuthSession(
          email: 'default@example.com',
          displayName: 'Default User',
        );
  }

  @override
  Future<void> clearConnection() async {
    didClearConnection = true;
  }
}

const _credentials = SyncAccountCredentials(
  serverUrl: 'https://cloud.example.com/remote.php/dav/files/user',
  username: 'user',
  password: 'app-password',
);
