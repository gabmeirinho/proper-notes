import 'package:flutter_test/flutter_test.dart';
import 'package:proper_notes/features/auth/application/auth_controller.dart';
import 'package:proper_notes/features/auth/domain/auth_service.dart';
import 'package:proper_notes/features/auth/domain/auth_session.dart';

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

  test('signIn updates session state', () async {
    final controller = AuthController(
      authService: _FakeAuthService(
        signInSession: const AuthSession(
          email: 'signed@example.com',
          displayName: 'Signed In',
        ),
      ),
    );

    await controller.signIn();

    expect(controller.isSignedIn, isTrue);
    expect(controller.hasResolvedInitialSession, isTrue);
    expect(controller.session?.displayName, 'Signed In');
    expect(controller.errorMessage, isNull);
  });

  test('signOut clears session state', () async {
    final authService = _FakeAuthService(
      restoredSession: const AuthSession(
        email: 'restored@example.com',
        displayName: 'Restored User',
      ),
    );
    final controller = AuthController(authService: authService);

    await controller.restore();
    await controller.signOut();

    expect(controller.isSignedIn, isFalse);
    expect(controller.hasResolvedInitialSession, isTrue);
    expect(controller.session, isNull);
    expect(authService.didSignOut, isTrue);
  });

  test('stores error message when auth operation fails', () async {
    final controller = AuthController(
      authService: _FakeAuthService(
        signInError: Exception('sign-in failed'),
      ),
    );

    await controller.signIn();

    expect(controller.isSignedIn, isFalse);
    expect(controller.hasResolvedInitialSession, isFalse);
    expect(controller.errorMessage, contains('sign-in failed'));
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
    this.signInSession,
    this.signInError,
    this.restoreError,
  });

  final AuthSession? restoredSession;
  final AuthSession? signInSession;
  final Object? signInError;
  final Object? restoreError;
  bool didSignOut = false;

  @override
  Future<AuthSession?> restoreSession() async {
    if (restoreError != null) {
      throw restoreError!;
    }

    return restoredSession;
  }

  @override
  Future<AuthSession> signIn() async {
    if (signInError != null) {
      throw signInError!;
    }

    return signInSession ??
        const AuthSession(
          email: 'default@example.com',
          displayName: 'Default User',
        );
  }

  @override
  Future<void> signOut() async {
    didSignOut = true;
  }
}
