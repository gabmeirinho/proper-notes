import 'package:flutter/foundation.dart';

import 'manual_sync_result.dart';
import 'run_manual_sync.dart';

class SyncController extends ChangeNotifier {
  SyncController({
    required RunManualSync runManualSync,
  }) : _runManualSync = runManualSync;

  final RunManualSync _runManualSync;

  bool _isSyncing = false;
  String? _lastMessage;
  String? _errorMessage;
  String? _errorDetails;
  DateTime? _lastCompletedAt;
  Future<ManualSyncResult?>? _activeSync;

  bool get isSyncing => _isSyncing;
  String? get lastMessage => _lastMessage;
  String? get errorMessage => _errorMessage;
  String? get errorDetails => _errorDetails;
  DateTime? get lastCompletedAt => _lastCompletedAt;

  Future<ManualSyncResult?> syncNow() async {
    final activeSync = _activeSync;
    if (activeSync != null) {
      return activeSync;
    }

    final sync = _runSync();
    _activeSync = sync;

    try {
      return await sync;
    } finally {
      if (identical(_activeSync, sync)) {
        _activeSync = null;
      }
    }
  }

  Future<ManualSyncResult?> _runSync() async {
    _isSyncing = true;
    _errorMessage = null;
    _errorDetails = null;
    _lastMessage = 'Syncing notes...';
    notifyListeners();

    try {
      final result = await _runManualSync();
      _lastMessage = result.summary();
      _lastCompletedAt = result.completedAt;
      return result;
    } catch (error) {
      _errorDetails = error.toString();
      _errorMessage = _summarizeError(error.toString());
      return null;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  String _summarizeError(String rawError) {
    final message = rawError.toLowerCase();

    if (message.contains('sign in is required before sync can run')) {
      return 'Sign in again before running sync.';
    }
    if (message.contains('access_token_scope_insufficient') ||
        message.contains('insufficient authentication scopes')) {
      return 'Google account access is missing Drive permission. Sign in again and approve Drive access.';
    }
    if (message.contains('google drive access was not granted')) {
      return 'Drive access was not granted. Try sync again and approve the permission request.';
    }
    if (message.contains('failed to list drive app data files') ||
        message.contains('failed to list drive changes') ||
        message.contains('failed to get drive start page token') ||
        message.contains('failed to download drive note') ||
        message.contains('failed to upload drive note')) {
      return 'Google Drive sync failed. Check your connection and try again.';
    }
    if (message.contains('socketexception') ||
        message.contains('connection closed') ||
        message.contains('network is unreachable') ||
        message.contains('timed out')) {
      return 'Network error during sync. Check your connection and try again.';
    }

    return 'Sync failed. Try again.';
  }
}
