import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:proper_notes/features/auth/application/auth_controller.dart';
import 'package:proper_notes/features/auth/domain/auth_service.dart';
import 'package:proper_notes/features/auth/domain/auth_session.dart';
import 'package:proper_notes/features/auth/domain/sync_account_credentials.dart';
import 'package:proper_notes/features/notes/domain/note.dart';
import 'package:proper_notes/features/notes/domain/note_repository.dart';
import 'package:proper_notes/features/notes/domain/sync_status.dart';
import 'package:proper_notes/features/sync/application/auto_sync_coordinator.dart';
import 'package:proper_notes/features/sync/application/manual_sync_result.dart';
import 'package:proper_notes/features/sync/application/run_manual_sync.dart';
import 'package:proper_notes/features/sync/application/sync_controller.dart';
import 'package:proper_notes/features/sync/domain/remote_note.dart';
import 'package:proper_notes/features/sync/domain/sync_gateway.dart';
import 'package:proper_notes/features/sync/domain/sync_state_repository.dart';

void main() {
  test('debounces local persisted changes into one sync', () async {
    final noteRepository = _FakeNoteRepository(
      activeNotes: [
        _note(syncStatus: SyncStatus.pendingUpload),
      ],
    );
    final authController = AuthController(
      authService: _FakeAuthService(
        restoredSession: const AuthSession(
          email: 'signed@example.com',
          displayName: 'Signed In',
        ),
      ),
    );
    await authController.restore();

    final runManualSync = _RecordingRunManualSync();
    final syncController = SyncController(runManualSync: runManualSync);
    final coordinator = AutoSyncCoordinator(
      noteRepository: noteRepository,
      authController: authController,
      syncController: syncController,
      localChangeDebounce: const Duration(milliseconds: 20),
    );

    coordinator.notifyLocalChangePersisted();
    coordinator.notifyLocalChangePersisted();
    coordinator.notifyLocalChangePersisted();
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(runManualSync.callCount, 1);
    coordinator.dispose();
  });

  test('resume sync runs even without pending local changes', () async {
    final noteRepository = _FakeNoteRepository(
      activeNotes: [
        _note(syncStatus: SyncStatus.synced),
      ],
    );
    final authController = AuthController(
      authService: _FakeAuthService(
        restoredSession: const AuthSession(
          email: 'signed@example.com',
          displayName: 'Signed In',
        ),
      ),
    );
    await authController.restore();

    final runManualSync = _RecordingRunManualSync();
    final syncController = SyncController(runManualSync: runManualSync);
    final coordinator = AutoSyncCoordinator(
      noteRepository: noteRepository,
      authController: authController,
      syncController: syncController,
      resumeSyncInterval: Duration.zero,
    );

    await coordinator.syncOnResume();

    expect(runManualSync.callCount, 1);
    coordinator.dispose();
  });

  test('idle sync runs while signed in even without pending local changes',
      () async {
    final noteRepository = _FakeNoteRepository(
      activeNotes: [
        _note(syncStatus: SyncStatus.synced),
      ],
    );
    final authController = AuthController(
      authService: _FakeAuthService(
        restoredSession: const AuthSession(
          email: 'signed@example.com',
          displayName: 'Signed In',
        ),
      ),
    );
    await authController.restore();

    final runManualSync = _RecordingRunManualSync();
    final syncController = SyncController(runManualSync: runManualSync);
    final coordinator = AutoSyncCoordinator(
      noteRepository: noteRepository,
      authController: authController,
      syncController: syncController,
      idleSyncInterval: const Duration(milliseconds: 30),
    );

    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(runManualSync.callCount, 1);
    coordinator.dispose();
  });

  test('background sync runs even without pending local changes', () async {
    final noteRepository = _FakeNoteRepository(
      activeNotes: [
        _note(syncStatus: SyncStatus.synced),
      ],
    );
    final authController = AuthController(
      authService: _FakeAuthService(
        restoredSession: const AuthSession(
          email: 'signed@example.com',
          displayName: 'Signed In',
        ),
      ),
    );
    await authController.restore();

    final runManualSync = _RecordingRunManualSync();
    final syncController = SyncController(runManualSync: runManualSync);
    final coordinator = AutoSyncCoordinator(
      noteRepository: noteRepository,
      authController: authController,
      syncController: syncController,
    );

    await coordinator.syncOnBackground();

    expect(runManualSync.callCount, 1);
    coordinator.dispose();
  });
}

class _FakeAuthService implements AuthService {
  _FakeAuthService({
    this.restoredSession,
  });

  final AuthSession? restoredSession;

  @override
  Future<AuthSession?> restoreSession() async => restoredSession;

  @override
  Future<void> testConnection(SyncAccountCredentials credentials) async {}

  @override
  Future<AuthSession> saveConnection(
          SyncAccountCredentials credentials) async =>
      restoredSession!;

  @override
  Future<void> clearConnection() async {}
}

class _FakeNoteRepository implements NoteRepository {
  _FakeNoteRepository({
    this.activeNotes = const <Note>[],
    this.deletedNotes = const <Note>[],
  });

  final List<Note> activeNotes;
  final List<Note> deletedNotes;

  @override
  Future<void> applyRemoteDeletion(RemoteNote remoteNote) async {}

  @override
  Future<int> countAttachmentReferences(String attachmentUri) async => 0;

  @override
  Future<void> create(Note note) async {}

  @override
  Future<List<Note>> getByIds(Iterable<String> ids) async => const <Note>[];

  @override
  Future<Note?> getById(String id) async => null;

  @override
  Future<List<Note>> getActiveNotesForSync() async => activeNotes;

  @override
  Future<List<Note>> getDeletedNotesForSync() async => deletedNotes;

  @override
  Future<List<Note>> getPendingNotesForSync() async => const <Note>[];

  @override
  Future<Map<String, String?>> getRemoteEtagsByPath() async =>
      const <String, String?>{};

  @override
  Future<void> markConflict(String id) async {}

  @override
  Future<void> markSynced({
    required String id,
    required DateTime syncedAt,
    required String baseContentHash,
    String? remoteFileId,
    String? remoteEtag,
  }) async {}

  @override
  Future<void> restore(String id) async {}

  @override
  Future<List<Note>> searchNotes(String query, {String? folderPath}) async =>
      const <Note>[];

  @override
  Future<void> softDelete(String id, DateTime deletedAt) async {}

  @override
  Future<void> update(Note note) async {}

  @override
  Future<void> upsertRemoteNote(RemoteNote remoteNote) async {}

  @override
  Stream<List<Note>> watchActiveNotes({String? folderPath}) =>
      const Stream<List<Note>>.empty();

  @override
  Stream<List<Note>> watchDeletedNotes({String? folderPath}) =>
      const Stream<List<Note>>.empty();
}

class _RecordingRunManualSync extends RunManualSync {
  _RecordingRunManualSync()
      : super(
          noteRepository: _FakeNoteRepository(),
          syncGateway: _FakeSyncGateway(),
          syncStateRepository: _FakeSyncStateRepository(),
        );

  int callCount = 0;

  @override
  Future<ManualSyncResult> call() async {
    callCount += 1;
    return ManualSyncResult(
      uploadedCount: 0,
      downloadedCount: 0,
      unchangedCount: 1,
      conflictCount: 0,
      completedAt: DateTime.utc(2026, 4, 9),
      totalDuration: Duration.zero,
      localLoadDuration: Duration.zero,
      remoteFetchDuration: Duration.zero,
      reconciliationDuration: Duration.zero,
    );
  }
}

class _FakeSyncGateway implements SyncGateway {
  @override
  Future<RemoteSyncBatch> bootstrap() async => const RemoteSyncBatch(
        notes: <RemoteNote>[],
        nextToken: 'token',
        isFullSnapshot: true,
      );

  @override
  Future<void> ensureRemoteAttachmentsAvailable(List<RemoteNote> notes) async {}

  @override
  Future<List<RemoteNote>> fetchAllNotes() async => const <RemoteNote>[];

  @override
  Future<RemoteSyncBatch> fetchChangesSince(
    String token, {
    Map<String, String?> knownRemoteEtags = const <String, String?>{},
  }) async =>
      const RemoteSyncBatch(
        notes: <RemoteNote>[],
        nextToken: 'token',
        isFullSnapshot: false,
      );

  @override
  Future<void> syncNoteAttachments(Note note) async {}

  @override
  Future<RemoteNote> upsertNote(Note note) async => RemoteNote(
        id: note.id,
        title: note.title,
        content: note.content,
        createdAt: note.createdAt,
        updatedAt: note.updatedAt,
        contentHash: note.contentHash,
        deviceId: note.deviceId,
      );
}

class _FakeSyncStateRepository implements SyncStateRepository {
  @override
  Future<String?> getRemoteSyncCursor() async => null;

  @override
  Future<String> getOrCreateDeviceId() async => 'device-1';

  @override
  Future<void> setRemoteSyncCursor(String token) async {}
}

Note _note({
  required SyncStatus syncStatus,
}) {
  return Note(
    id: 'note-1',
    title: 'Title',
    content: 'content',
    createdAt: DateTime.utc(2026, 4, 9),
    updatedAt: DateTime.utc(2026, 4, 9),
    syncStatus: syncStatus,
    contentHash: 'hash-1',
    deviceId: 'device-1',
  );
}
