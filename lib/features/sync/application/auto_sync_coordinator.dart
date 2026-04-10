import 'dart:async';

import '../../auth/application/auth_controller.dart';
import '../../notes/domain/note.dart';
import '../../notes/domain/note_repository.dart';
import '../../notes/domain/sync_status.dart';
import 'sync_controller.dart';

class AutoSyncCoordinator {
  AutoSyncCoordinator({
    required NoteRepository noteRepository,
    required AuthController authController,
    required SyncController syncController,
    this.localChangeDebounce = const Duration(seconds: 10),
    this.idleSyncInterval = const Duration(seconds: 30),
    this.resumeSyncInterval = const Duration(seconds: 30),
    this.failureCooldown = const Duration(seconds: 20),
  })  : _noteRepository = noteRepository,
        _authController = authController,
        _syncController = syncController,
        _wasSignedIn = authController.isSignedIn {
    _authController.addListener(_handleAuthControllerChanged);
    _updateIdleSyncTimer();
  }

  final NoteRepository _noteRepository;
  final AuthController _authController;
  final SyncController _syncController;
  final Duration localChangeDebounce;
  final Duration idleSyncInterval;
  final Duration resumeSyncInterval;
  final Duration failureCooldown;

  Timer? _debounceTimer;
  Timer? _idleSyncTimer;
  Future<void>? _activeSyncFuture;
  bool _syncQueued = false;
  bool _wasSignedIn;
  DateTime? _lastAutoSyncFailureAt;

  void dispose() {
    _debounceTimer?.cancel();
    _idleSyncTimer?.cancel();
    _authController.removeListener(_handleAuthControllerChanged);
  }

  void notifyLocalChangePersisted() {
    if (!_authController.isSignedIn) {
      return;
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(localChangeDebounce, () {
      unawaited(
        _requestAutoSync(requirePendingChanges: true),
      );
    });
  }

  Future<void> syncOnResume() {
    final lastCompletedAt = _syncController.lastCompletedAt;
    final now = DateTime.now().toUtc();
    if (lastCompletedAt != null &&
        now.difference(lastCompletedAt) < resumeSyncInterval) {
      return Future<void>.value();
    }

    return _requestAutoSync(
      requirePendingChanges: false,
      ignoreFailureCooldown: true,
    );
  }

  Future<void> syncOnBackground() {
    return _requestAutoSync(
      requirePendingChanges: false,
      ignoreFailureCooldown: true,
    );
  }

  Future<void> syncBeforeExit({
    required Duration timeout,
  }) async {
    final activeSync = _activeSyncFuture;
    if (activeSync != null) {
      await _awaitWithTimeout(activeSync, timeout: timeout);
      return;
    }

    await _requestAutoSync(
      requirePendingChanges: false,
      timeout: timeout,
      ignoreFailureCooldown: true,
    );
  }

  Future<bool> hasPendingChanges() async {
    final activeNotes = await _noteRepository.getActiveNotesForSync();
    if (activeNotes.any(_isPendingSync)) {
      return true;
    }

    final deletedNotes = await _noteRepository.getDeletedNotesForSync();
    return deletedNotes.any(_isPendingSync);
  }

  void _handleAuthControllerChanged() {
    final isSignedIn = _authController.isSignedIn;
    if (_authController.isBusy) {
      _wasSignedIn = isSignedIn;
      return;
    }

    _updateIdleSyncTimer();

    if (isSignedIn && !_wasSignedIn) {
      unawaited(
        _requestAutoSync(
          requirePendingChanges: false,
          ignoreFailureCooldown: true,
        ),
      );
    }

    _wasSignedIn = isSignedIn;
  }

  void _updateIdleSyncTimer() {
    _idleSyncTimer?.cancel();
    _idleSyncTimer = null;

    if (!_authController.isSignedIn || idleSyncInterval <= Duration.zero) {
      return;
    }

    _idleSyncTimer = Timer.periodic(idleSyncInterval, (_) {
      unawaited(
        _requestAutoSync(requirePendingChanges: false),
      );
    });
  }

  Future<void> _requestAutoSync({
    required bool requirePendingChanges,
    Duration? timeout,
    bool ignoreFailureCooldown = false,
  }) async {
    if (!_authController.isSignedIn) {
      return;
    }

    final now = DateTime.now().toUtc();
    if (!ignoreFailureCooldown &&
        _lastAutoSyncFailureAt != null &&
        now.difference(_lastAutoSyncFailureAt!) < failureCooldown) {
      return;
    }

    if (requirePendingChanges && !await hasPendingChanges()) {
      return;
    }

    final activeSync = _activeSyncFuture;
    if (activeSync != null) {
      _syncQueued = true;
      if (timeout != null) {
        await _awaitWithTimeout(activeSync, timeout: timeout);
      } else {
        await activeSync;
      }
      return;
    }

    final syncFuture = _performSync();
    _activeSyncFuture = syncFuture;

    try {
      if (timeout != null) {
        await _awaitWithTimeout(syncFuture, timeout: timeout);
      } else {
        await syncFuture;
      }
    } finally {
      if (identical(_activeSyncFuture, syncFuture)) {
        _activeSyncFuture = null;
      }
    }

    if (_syncQueued) {
      _syncQueued = false;
      unawaited(
        _requestAutoSync(requirePendingChanges: true),
      );
    }
  }

  Future<void> _performSync() async {
    final result = await _syncController.syncNow();
    if (result == null) {
      _lastAutoSyncFailureAt = DateTime.now().toUtc();
      return;
    }

    _lastAutoSyncFailureAt = null;
  }

  Future<void> _awaitWithTimeout(
    Future<void> future, {
    required Duration timeout,
  }) async {
    try {
      await future.timeout(timeout);
    } on TimeoutException {
      // Best-effort exit/background sync intentionally does not block longer.
    }
  }

  bool _isPendingSync(Note note) {
    return note.syncStatus == SyncStatus.pendingUpload ||
        note.syncStatus == SyncStatus.pendingDelete;
  }
}
