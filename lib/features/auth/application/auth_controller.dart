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
      _errorMessage = error.toString();
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }
}
