import 'package:flutter/foundation.dart';

import '../domain/auth_service.dart';
import '../domain/auth_session.dart';
import '../domain/sync_account_credentials.dart';

class AuthController extends ChangeNotifier {
  AuthController({
    required AuthService authService,
  }) : _authService = authService;

  final AuthService _authService;

  AuthSession? _session;
  bool _isBusy = false;
  bool _hasResolvedInitialSession = false;
  String? _errorMessage;

  AuthSession? get session => _session;
  bool get isBusy => _isBusy;
  bool get isSignedIn => _session != null;
  bool get hasResolvedInitialSession => _hasResolvedInitialSession;
  String? get errorMessage => _errorMessage;

  Future<void> restore() async {
    try {
      await _run(() async {
        _session = await _authService.restoreSession();
      });
    } finally {
      _hasResolvedInitialSession = true;
      notifyListeners();
    }
  }

  Future<void> testConnection(SyncAccountCredentials credentials) async {
    await _run(() async {
      await _authService.testConnection(credentials);
      _hasResolvedInitialSession = true;
    });
  }

  Future<void> saveConnection(SyncAccountCredentials credentials) async {
    await _run(() async {
      _session = await _authService.saveConnection(credentials);
      _hasResolvedInitialSession = true;
    });
  }

  Future<void> clearConnection() async {
    await _run(() async {
      await _authService.clearConnection();
      _session = null;
      _hasResolvedInitialSession = true;
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await action();
    } catch (error) {
      _errorMessage = _summarizeError(error.toString());
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  String _summarizeError(String rawError) {
    final normalized = rawError.trim();
    final withoutExceptionPrefix = normalized.startsWith('Exception: ')
        ? normalized.substring('Exception: '.length)
        : normalized;
    final message = withoutExceptionPrefix.toLowerCase();

    if (message.contains('unauthorized') ||
        message.contains('authentication')) {
      return 'Authentication failed. Check the WebDAV username and app password.';
    }
    if (message.contains('propfind') || message.contains('webdav')) {
      return 'WebDAV connection failed. Check the server URL and try again.';
    }
    if (message.contains('network') ||
        message.contains('socketexception') ||
        message.contains('timed out')) {
      return 'Network error while checking the sync account. Try again.';
    }

    return withoutExceptionPrefix;
  }
}
