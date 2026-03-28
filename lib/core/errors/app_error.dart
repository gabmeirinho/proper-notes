sealed class AppError implements Exception {
  const AppError(this.message);

  final String message;

  @override
  String toString() => message;
}

final class ValidationError extends AppError {
  const ValidationError(super.message);
}

final class PersistenceError extends AppError {
  const PersistenceError(super.message);
}

final class SyncError extends AppError {
  const SyncError(super.message);
}

final class AuthError extends AppError {
  const AuthError(super.message);
}
