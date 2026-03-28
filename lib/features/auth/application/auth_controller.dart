import 'package:flutter/foundation.dart';

import '../domain/auth_service.dart';
import '../domain/auth_session.dart';

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

  Future<void> signIn() async {
    await _run(() async {
      _session = await _authService.signIn();
      _hasResolvedInitialSession = true;
    });
  }

  Future<void> signOut() async {
    await _run(() async {
      await _authService.signOut();
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

    if (message.contains('client id') || message.contains('client secret')) {
      return 'Google sign-in is not configured correctly for this build.';
    }
    if (message.contains('cancelled') || message.contains('canceled')) {
      return 'Google sign-in was cancelled.';
    }
    if (message.contains('network')) {
      return 'Network error during sign-in. Check your connection and try again.';
    }

    return withoutExceptionPrefix;
  }
}
