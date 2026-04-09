import '../../../core/utils/content_hash.dart';
import '../../notes/domain/note.dart';
import '../../notes/domain/note_repository.dart';
import '../../notes/domain/sync_status.dart';
import '../domain/remote_note.dart';
import '../domain/sync_gateway.dart';
import '../domain/sync_state_repository.dart';
import 'manual_sync_result.dart';
import 'package:uuid/uuid.dart';

class RunManualSync {
  RunManualSync({
    required NoteRepository noteRepository,
    required SyncGateway syncGateway,
    required SyncStateRepository syncStateRepository,
    Uuid? uuid,
  })  : _noteRepository = noteRepository,
        _syncGateway = syncGateway,
        _syncStateRepository = syncStateRepository,
        _uuid = uuid ?? const Uuid();

  final NoteRepository _noteRepository;
  final SyncGateway _syncGateway;
  final SyncStateRepository _syncStateRepository;
  final Uuid _uuid;

  Future<ManualSyncResult> call() async {
    final stopwatch = Stopwatch()..start();
    final localLoadStopwatch = Stopwatch()..start();
    final localNotes = [
      ...await _noteRepository.getActiveNotesForSync(),
      ...await _noteRepository.getDeletedNotesForSync(),
    ];
    localLoadStopwatch.stop();

    for (final localNote in localNotes) {
      if (localNote.deletedAt != null) {
        continue;
      }
      if (localNote.syncStatus != SyncStatus.pendingUpload) {
        continue;
      }

      await _syncGateway.syncNoteAttachments(localNote);
    }

    final remoteFetchStopwatch = Stopwatch()..start();
    final currentToken = await _syncStateRepository.getDriveSyncToken();
    final remoteBatch = currentToken == null
        ? await _syncGateway.bootstrap()
        : await _syncGateway.fetchChangesSince(currentToken);
    await _syncGateway.ensureRemoteAttachmentsAvailable(remoteBatch.notes);
    remoteFetchStopwatch.stop();

    final reconciliationStopwatch = Stopwatch()..start();
    final remoteNotes = remoteBatch.notes;
    final localById = <String, Note>{
      for (final note in localNotes) note.id: note,
    };
    final remoteById = <String, RemoteNote>{
      for (final note in remoteNotes) note.id: note,
    };

    var uploadedCount = 0;
    var downloadedCount = 0;
    var unchangedCount = 0;
    var conflictCount = 0;

    for (final localNote in localNotes) {
      final remoteNote = remoteById[localNote.id];

      if (remoteNote == null) {
        if (!remoteBatch.isFullSnapshot) {
          if (_shouldUploadLocalPendingNote(localNote)) {
            final uploaded = await _syncGateway.upsertNote(localNote);
            await _noteRepository.markSynced(
              id: localNote.id,
              syncedAt: DateTime.now().toUtc(),
              baseContentHash: localNote.contentHash,
              remoteFileId: uploaded.remoteFileId,
            );
            uploadedCount += 1;
          } else {
            unchangedCount += 1;
          }
          continue;
        }

        final uploaded = await _syncGateway.upsertNote(localNote);
        await _noteRepository.markSynced(
          id: localNote.id,
          syncedAt: DateTime.now().toUtc(),
          baseContentHash: localNote.contentHash,
          remoteFileId: uploaded.remoteFileId,
        );
        uploadedCount += 1;
        continue;
      }

      if (_hasInconsistentLocalContent(localNote)) {
        await _noteRepository.upsertRemoteNote(remoteNote);
        downloadedCount += 1;
        continue;
      }

      if (localNote.deletedAt != null && remoteNote.deletedAt != null) {
        if (_shouldRefreshSyncedState(
          localNote: localNote,
          remoteFileId: remoteNote.remoteFileId,
        )) {
          await _noteRepository.markSynced(
            id: localNote.id,
            syncedAt: DateTime.now().toUtc(),
            baseContentHash: localNote.contentHash,
            remoteFileId: remoteNote.remoteFileId,
          );
        }
        unchangedCount += 1;
        continue;
      }

      if (localNote.deletedAt != null && remoteNote.deletedAt == null) {
        if (localNote.syncStatus != SyncStatus.pendingDelete) {
          await _noteRepository.upsertRemoteNote(remoteNote);
          downloadedCount += 1;
          continue;
        }

        final remoteChangedSinceBase = _hasRemoteChangedSinceBase(
          localNote: localNote,
          remoteNote: remoteNote,
        );
        if (localNote.syncStatus == SyncStatus.pendingDelete &&
            remoteChangedSinceBase) {
          await _createAndSyncConflictCopy(
            title: _conflictTitleFor(remoteNote.title, localNote.title),
            content: remoteNote.content,
            updatedAt: remoteNote.updatedAt,
            contentHash: remoteNote.contentHash,
            deviceId: remoteNote.deviceId,
          );
          final uploaded = await _syncGateway.upsertNote(localNote);
          await _noteRepository.markSynced(
            id: localNote.id,
            syncedAt: DateTime.now().toUtc(),
            baseContentHash: localNote.contentHash,
            remoteFileId: uploaded.remoteFileId,
          );
          uploadedCount += 1;
          conflictCount += 1;
          continue;
        }

        final uploaded = await _syncGateway.upsertNote(localNote);
        await _noteRepository.markSynced(
          id: localNote.id,
          syncedAt: DateTime.now().toUtc(),
          baseContentHash: localNote.contentHash,
          remoteFileId: uploaded.remoteFileId,
        );
        uploadedCount += 1;
        continue;
      }

      if (localNote.deletedAt == null && remoteNote.deletedAt != null) {
        if (localNote.syncStatus == SyncStatus.pendingUpload) {
          final isLocalRestore = localNote.baseContentHash != null &&
              localNote.baseContentHash == localNote.contentHash;
          if (isLocalRestore) {
            final uploaded = await _syncGateway.upsertNote(localNote);
            await _noteRepository.markSynced(
              id: localNote.id,
              syncedAt: DateTime.now().toUtc(),
              baseContentHash: localNote.contentHash,
              remoteFileId: uploaded.remoteFileId,
            );
            uploadedCount += 1;
          } else {
            await _createAndSyncConflictCopy(
              title: _conflictTitleFor(localNote.title, localNote.title),
              content: localNote.content,
              updatedAt: localNote.updatedAt,
              contentHash: localNote.contentHash,
              deviceId: localNote.deviceId,
            );
            await _noteRepository.applyRemoteDeletion(remoteNote);
            downloadedCount += 1;
            conflictCount += 1;
          }
          continue;
        }

        final baseHash = localNote.baseContentHash;
        final localChanged =
            baseHash == null || localNote.contentHash != baseHash;
        if (localChanged) {
          await _createAndSyncConflictCopy(
            title: _conflictTitleFor(localNote.title, localNote.title),
            content: localNote.content,
            updatedAt: localNote.updatedAt,
            contentHash: localNote.contentHash,
            deviceId: localNote.deviceId,
          );
          await _noteRepository.applyRemoteDeletion(remoteNote);
          downloadedCount += 1;
          conflictCount += 1;
        } else {
          await _noteRepository.applyRemoteDeletion(remoteNote);
          downloadedCount += 1;
        }
        continue;
      }

      if (_isNoteEquivalent(localNote, remoteNote)) {
        if (_shouldRefreshSyncedState(
          localNote: localNote,
          remoteFileId: remoteNote.remoteFileId,
        )) {
          await _noteRepository.markSynced(
            id: localNote.id,
            syncedAt: DateTime.now().toUtc(),
            baseContentHash: localNote.contentHash,
            remoteFileId: remoteNote.remoteFileId,
          );
        }
        unchangedCount += 1;
        continue;
      }

      if (localNote.contentHash == remoteNote.contentHash) {
        if (localNote.syncStatus == SyncStatus.pendingUpload) {
          final uploaded = await _syncGateway.upsertNote(localNote);
          await _noteRepository.markSynced(
            id: localNote.id,
            syncedAt: DateTime.now().toUtc(),
            baseContentHash: localNote.contentHash,
            remoteFileId: uploaded.remoteFileId,
          );
          uploadedCount += 1;
        } else {
          await _noteRepository.upsertRemoteNote(remoteNote);
          downloadedCount += 1;
        }
        continue;
      }

      final baseHash = localNote.baseContentHash;
      final localChanged =
          baseHash == null || localNote.contentHash != baseHash;
      final remoteChanged =
          baseHash == null || remoteNote.contentHash != baseHash;

      if (localChanged && !remoteChanged) {
        final uploaded = await _syncGateway.upsertNote(localNote);
        await _noteRepository.markSynced(
          id: localNote.id,
          syncedAt: DateTime.now().toUtc(),
          baseContentHash: localNote.contentHash,
          remoteFileId: uploaded.remoteFileId,
        );
        uploadedCount += 1;
        continue;
      }

      if (!localChanged && remoteChanged) {
        await _noteRepository.upsertRemoteNote(remoteNote);
        downloadedCount += 1;
        continue;
      }

      await _createAndSyncConflictCopy(
        title: _conflictTitleFor(remoteNote.title, localNote.title),
        content: remoteNote.content,
        updatedAt: remoteNote.updatedAt,
        contentHash: remoteNote.contentHash,
        deviceId: remoteNote.deviceId,
      );
      final uploaded = await _syncGateway.upsertNote(localNote);
      await _noteRepository.markSynced(
        id: localNote.id,
        syncedAt: DateTime.now().toUtc(),
        baseContentHash: localNote.contentHash,
        remoteFileId: uploaded.remoteFileId,
      );
      conflictCount += 1;
    }

    for (final remoteNote in remoteNotes) {
      if (localById.containsKey(remoteNote.id)) {
        continue;
      }

      if (remoteNote.deletedAt != null) {
        await _noteRepository.applyRemoteDeletion(remoteNote);
      } else {
        await _noteRepository.upsertRemoteNote(remoteNote);
      }
      downloadedCount += 1;
    }

    await _syncStateRepository.setDriveSyncToken(remoteBatch.nextToken);
    reconciliationStopwatch.stop();

    return ManualSyncResult(
      uploadedCount: uploadedCount,
      downloadedCount: downloadedCount,
      unchangedCount: unchangedCount,
      conflictCount: conflictCount,
      completedAt: DateTime.now().toUtc(),
      totalDuration: stopwatch.elapsed,
      localLoadDuration: localLoadStopwatch.elapsed,
      remoteFetchDuration: remoteFetchStopwatch.elapsed,
      reconciliationDuration: reconciliationStopwatch.elapsed,
    );
  }

  bool _shouldRefreshSyncedState({
    required Note localNote,
    required String? remoteFileId,
  }) {
    return localNote.syncStatus != SyncStatus.synced ||
        localNote.baseContentHash != localNote.contentHash ||
        localNote.remoteFileId != remoteFileId;
  }

  bool _shouldUploadLocalPendingNote(Note localNote) {
    return localNote.syncStatus == SyncStatus.pendingUpload ||
        localNote.syncStatus == SyncStatus.pendingDelete;
  }

  bool _hasInconsistentLocalContent(Note localNote) {
    return computeContentHash(localNote.content) != localNote.contentHash;
  }

  bool _hasRemoteChangedSinceBase({
    required Note localNote,
    required RemoteNote remoteNote,
  }) {
    final baseHash = localNote.baseContentHash;
    return baseHash == null || remoteNote.contentHash != baseHash;
  }

  bool _isNoteEquivalent(Note localNote, RemoteNote remoteNote) {
    return localNote.contentHash == remoteNote.contentHash &&
        localNote.title == remoteNote.title &&
        localNote.folderPath == remoteNote.folderPath &&
        localNote.deletedAt == remoteNote.deletedAt;
  }

  Future<void> _createAndSyncConflictCopy({
    required String title,
    required String content,
    required DateTime updatedAt,
    required String contentHash,
    required String deviceId,
  }) async {
    final now = DateTime.now().toUtc();
    final conflictCopy = Note(
      id: _uuid.v4(),
      title: title,
      content: content,
      createdAt: now,
      updatedAt: updatedAt,
      lastSyncedAt: now,
      syncStatus: SyncStatus.conflicted,
      contentHash: contentHash,
      baseContentHash: contentHash,
      deviceId: deviceId,
    );

    await _noteRepository.create(conflictCopy);
    final uploaded = await _syncGateway.upsertNote(conflictCopy);
    await _syncGateway.syncNoteAttachments(conflictCopy);
    await _noteRepository.update(
      conflictCopy.copyWith(
        lastSyncedAt: now,
        baseContentHash: conflictCopy.contentHash,
        remoteFileId: uploaded.remoteFileId,
        syncStatus: SyncStatus.conflicted,
      ),
    );
  }

  String _conflictTitleFor(String remoteTitle, String localTitle) {
    final baseTitle = remoteTitle.trim().isNotEmpty
        ? remoteTitle.trim()
        : (localTitle.trim().isNotEmpty ? localTitle.trim() : 'Untitled note');
    return '$baseTitle (Conflict Copy)';
  }
}
