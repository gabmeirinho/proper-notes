import 'auth_session.dart';

abstract interface class AuthService {
  Future<AuthSession?> restoreSession();
  Future<AuthSession> signIn();
  Future<void> signOut();
}
