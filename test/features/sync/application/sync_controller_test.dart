import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:proper_notes/features/sync/application/manual_sync_result.dart';
import 'package:proper_notes/features/sync/application/run_manual_sync.dart';
import 'package:proper_notes/features/sync/application/sync_controller.dart';
import 'package:proper_notes/features/sync/domain/remote_note.dart';
import 'package:proper_notes/features/sync/domain/sync_gateway.dart';
import 'package:proper_notes/features/sync/domain/sync_state_repository.dart';
import 'package:proper_notes/features/notes/domain/note.dart';
import 'package:proper_notes/features/notes/domain/note_repository.dart';

void main() {
  test('coalesces concurrent sync requests into one run', () async {
    final runManualSync = _CompletingRunManualSync();
    final controller = SyncController(runManualSync: runManualSync);

    final firstSync = controller.syncNow();
    final secondSync = controller.syncNow();

    expect(runManualSync.callCount, 1);
    expect(identical(firstSync, secondSync), isFalse);

    runManualSync.complete();
    final firstResult = await firstSync;
    final secondResult = await secondSync;

    expect(firstResult, isNotNull);
    expect(secondResult, isNotNull);
    expect(runManualSync.callCount, 1);
  });
}

class _CompletingRunManualSync extends RunManualSync {
  _CompletingRunManualSync()
      : super(
          noteRepository: _FakeNoteRepository(),
          syncGateway: _FakeSyncGateway(),
          syncStateRepository: _FakeSyncStateRepository(),
        );

  final Completer<ManualSyncResult> _completer = Completer<ManualSyncResult>();
  int callCount = 0;

  @override
  Future<ManualSyncResult> call() {
    callCount += 1;
    return _completer.future;
  }

  void complete() {
    if (_completer.isCompleted) {
      return;
    }

    _completer.complete(
      ManualSyncResult(
        uploadedCount: 0,
        downloadedCount: 0,
        unchangedCount: 1,
        conflictCount: 0,
        completedAt: DateTime.utc(2026, 4, 9),
        totalDuration: Duration.zero,
        localLoadDuration: Duration.zero,
        remoteFetchDuration: Duration.zero,
        reconciliationDuration: Duration.zero,
      ),
    );
  }
}

class _FakeNoteRepository implements NoteRepository {
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
  Future<List<Note>> getActiveNotesForSync() async => const <Note>[];

  @override
  Future<List<Note>> getDeletedNotesForSync() async => const <Note>[];

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

class _FakeSyncGateway implements SyncGateway {
  @override
  Future<RemoteSyncBatch> bootstrap() async => const RemoteSyncBatch(
      notes: <RemoteNote>[], nextToken: 'token', isFullSnapshot: true);

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
          notes: <RemoteNote>[], nextToken: 'token', isFullSnapshot: false);

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
