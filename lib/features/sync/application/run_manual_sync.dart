import 'package:uuid/uuid.dart';

import '../../../core/utils/content_hash.dart';
import '../../notes/domain/note.dart';
import '../../notes/domain/note_repository.dart';
import '../../notes/domain/sync_status.dart';
import '../domain/remote_note.dart';
import '../domain/sync_gateway.dart';
import '../domain/sync_state_repository.dart';
import 'manual_sync_result.dart';

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
    final currentToken = await _syncStateRepository.getRemoteSyncCursor();
    final pendingLocalNotes = await _noteRepository.getPendingNotesForSync();
    var localNotes = <Note>[...pendingLocalNotes];

    if (currentToken == null) {
      localNotes = [
        ...await _noteRepository.getActiveNotesForSync(),
        ...await _noteRepository.getDeletedNotesForSync(),
      ];
    }
    localLoadStopwatch.stop();

    for (final localNote in pendingLocalNotes) {
      if (localNote.deletedAt != null) {
        continue;
      }
      if (localNote.syncStatus != SyncStatus.pendingUpload) {
        continue;
      }
      await _syncGateway.syncNoteAttachments(localNote);
    }

    final remoteFetchStopwatch = Stopwatch()..start();
    final remoteBatch = currentToken == null
        ? await _syncGateway.bootstrap()
        : await _syncGateway.fetchChangesSince(
            currentToken,
            knownRemoteEtags: await _noteRepository.getRemoteEtagsByPath(),
          );
    await _syncGateway.ensureRemoteAttachmentsAvailable(remoteBatch.notes);
    remoteFetchStopwatch.stop();

    if (currentToken != null) {
      final impactedIds = <String>{
        for (final note in pendingLocalNotes) note.id,
        for (final note in remoteBatch.notes) note.id,
      };
      localNotes = await _noteRepository.getByIds(impactedIds);
    }

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
            await _markSynced(localNote: localNote, remoteNote: uploaded);
            uploadedCount += 1;
          } else {
            unchangedCount += 1;
          }
          continue;
        }

        final uploaded = await _syncGateway.upsertNote(localNote);
        await _markSynced(localNote: localNote, remoteNote: uploaded);
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
          remoteNote: remoteNote,
        )) {
          await _markSynced(localNote: localNote, remoteNote: remoteNote);
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
        if (remoteChangedSinceBase) {
          await _createAndSyncRemoteConflictCopy(
            remoteNote: remoteNote,
            fallbackTitle: localNote.title,
          );
          final uploaded = await _syncGateway.upsertNote(localNote);
          await _markSynced(localNote: localNote, remoteNote: uploaded);
          uploadedCount += 1;
          conflictCount += 1;
          continue;
        }

        final uploaded = await _syncGateway.upsertNote(localNote);
        await _markSynced(localNote: localNote, remoteNote: uploaded);
        uploadedCount += 1;
        continue;
      }

      if (localNote.deletedAt == null && remoteNote.deletedAt != null) {
        if (localNote.syncStatus == SyncStatus.pendingUpload) {
          final isLocalRestore = localNote.baseContentHash != null &&
              localNote.baseContentHash == localNote.contentHash;
          if (isLocalRestore) {
            final uploaded = await _syncGateway.upsertNote(localNote);
            await _markSynced(localNote: localNote, remoteNote: uploaded);
            uploadedCount += 1;
          } else {
            await _createAndSyncLocalConflictCopy(localNote);
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
          await _createAndSyncLocalConflictCopy(localNote);
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
          remoteNote: remoteNote,
        )) {
          await _refreshSyncedState(
            localNote: localNote,
            remoteNote: remoteNote,
          );
        }
        unchangedCount += 1;
        continue;
      }

      if (localNote.syncStatus == SyncStatus.conflicted) {
        await _refreshSyncedState(
          localNote: localNote,
          remoteNote: remoteNote,
        );
        unchangedCount += 1;
        continue;
      }

      if (localNote.contentHash == remoteNote.contentHash) {
        if (localNote.syncStatus == SyncStatus.pendingUpload) {
          if (_hasMetadataDifference(localNote, remoteNote)) {
            await _createAndSyncRemoteConflictCopy(
              remoteNote: remoteNote,
              fallbackTitle: localNote.title,
            );
            conflictCount += 1;
          }
          final uploaded = await _syncGateway.upsertNote(localNote);
          await _markSynced(localNote: localNote, remoteNote: uploaded);
          uploadedCount += 1;
        } else {
          await _noteRepository.upsertRemoteNote(remoteNote);
          downloadedCount += 1;
        }
        continue;
      }

      final localChanged = _hasLocalChangedSinceBase(localNote);
      final remoteChanged = _hasRemoteChangedSinceBaseForReconciliation(
        localNote: localNote,
        remoteNote: remoteNote,
      );

      if (localNote.syncStatus == SyncStatus.pendingUpload &&
          !localChanged &&
          remoteChanged &&
          _hasMetadataDifference(localNote, remoteNote)) {
        await _createAndSyncRemoteConflictCopy(
          remoteNote: remoteNote,
          fallbackTitle: localNote.title,
        );
        final uploaded = await _syncGateway.upsertNote(localNote);
        await _markSynced(localNote: localNote, remoteNote: uploaded);
        uploadedCount += 1;
        conflictCount += 1;
        continue;
      }

      if (localChanged && !remoteChanged) {
        final uploaded = await _syncGateway.upsertNote(localNote);
        await _markSynced(localNote: localNote, remoteNote: uploaded);
        uploadedCount += 1;
        continue;
      }

      if (!localChanged && remoteChanged) {
        await _noteRepository.upsertRemoteNote(remoteNote);
        downloadedCount += 1;
        continue;
      }

      if (_hasOnlyTrailingWhitespaceContentDifference(localNote, remoteNote) &&
          localNote.title == remoteNote.title &&
          localNote.folderPath == remoteNote.folderPath) {
        final uploaded = await _syncGateway.upsertNote(localNote);
        await _markSynced(localNote: localNote, remoteNote: uploaded);
        uploadedCount += 1;
        continue;
      }

      await _createAndSyncRemoteConflictCopy(
        remoteNote: remoteNote,
        fallbackTitle: localNote.title,
      );
      final uploaded = await _syncGateway.upsertNote(localNote);
      await _markSynced(localNote: localNote, remoteNote: uploaded);
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

    await _syncStateRepository.setRemoteSyncCursor(remoteBatch.nextToken);
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
    required RemoteNote remoteNote,
  }) {
    return localNote.syncStatus != SyncStatus.synced ||
        localNote.baseContentHash != localNote.contentHash ||
        localNote.remoteFileId != remoteNote.remoteFileId ||
        localNote.remoteEtag != remoteNote.remoteEtag;
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

  bool _hasLocalChangedSinceBase(Note localNote) {
    final baseHash = localNote.baseContentHash;
    if (baseHash == null) {
      return _shouldUploadLocalPendingNote(localNote);
    }

    return localNote.contentHash != baseHash;
  }

  bool _hasRemoteChangedSinceBaseForReconciliation({
    required Note localNote,
    required RemoteNote remoteNote,
  }) {
    final baseHash = localNote.baseContentHash;
    if (baseHash == null) {
      return !_isNoteEquivalent(localNote, remoteNote);
    }

    return remoteNote.contentHash != baseHash;
  }

  bool _isNoteEquivalent(Note localNote, RemoteNote remoteNote) {
    return localNote.contentHash == remoteNote.contentHash &&
        localNote.title == remoteNote.title &&
        localNote.documentJson == remoteNote.documentJson &&
        localNote.folderPath == remoteNote.folderPath &&
        localNote.deletedAt == remoteNote.deletedAt;
  }

  bool _hasMetadataDifference(Note localNote, RemoteNote remoteNote) {
    return localNote.title != remoteNote.title ||
        localNote.documentJson != remoteNote.documentJson ||
        localNote.folderPath != remoteNote.folderPath;
  }

  bool _hasOnlyTrailingWhitespaceContentDifference(
    Note localNote,
    RemoteNote remoteNote,
  ) {
    if (localNote.contentHash == remoteNote.contentHash) {
      return false;
    }

    return localNote.content.trimRight() == remoteNote.content.trimRight();
  }

  Future<void> _refreshSyncedState({
    required Note localNote,
    required RemoteNote remoteNote,
  }) {
    if (localNote.syncStatus == SyncStatus.conflicted) {
      return _noteRepository.update(
        localNote.copyWith(
          lastSyncedAt: DateTime.now().toUtc(),
          baseContentHash: localNote.contentHash,
          remoteFileId: remoteNote.remoteFileId,
          remoteEtag: remoteNote.remoteEtag,
          syncStatus: SyncStatus.conflicted,
        ),
      );
    }

    return _markSynced(localNote: localNote, remoteNote: remoteNote);
  }

  Future<void> _markSynced({
    required Note localNote,
    required RemoteNote remoteNote,
  }) {
    return _noteRepository.markSynced(
      id: localNote.id,
      syncedAt: DateTime.now().toUtc(),
      baseContentHash: localNote.contentHash,
      remoteFileId: remoteNote.remoteFileId,
      remoteEtag: remoteNote.remoteEtag,
    );
  }

  Future<void> _createAndSyncRemoteConflictCopy({
    required RemoteNote remoteNote,
    required String fallbackTitle,
  }) {
    return _createAndSyncConflictCopy(
      title: _conflictTitleFor(remoteNote.title, fallbackTitle),
      content: remoteNote.content,
      documentJson: remoteNote.documentJson,
      createdAt: remoteNote.createdAt,
      updatedAt: remoteNote.updatedAt,
      contentHash: remoteNote.contentHash,
      deviceId: remoteNote.deviceId,
      folderPath: remoteNote.folderPath,
    );
  }

  Future<void> _createAndSyncLocalConflictCopy(Note localNote) {
    return _createAndSyncConflictCopy(
      title: _conflictTitleFor(localNote.title, localNote.title),
      content: localNote.content,
      documentJson: localNote.documentJson,
      createdAt: localNote.createdAt,
      updatedAt: localNote.updatedAt,
      contentHash: localNote.contentHash,
      deviceId: localNote.deviceId,
      folderPath: localNote.folderPath,
    );
  }

  Future<void> _createAndSyncConflictCopy({
    required String title,
    required String content,
    required String documentJson,
    required DateTime createdAt,
    required DateTime updatedAt,
    required String contentHash,
    required String deviceId,
    required String? folderPath,
  }) async {
    final now = DateTime.now().toUtc();
    final conflictCopy = Note(
      id: _uuid.v4(),
      title: title,
      content: content,
      documentJson: documentJson,
      createdAt: createdAt,
      updatedAt: updatedAt,
      lastSyncedAt: now,
      syncStatus: SyncStatus.conflicted,
      contentHash: contentHash,
      baseContentHash: contentHash,
      deviceId: deviceId,
      folderPath: folderPath,
    );

    await _noteRepository.create(conflictCopy);
    final uploaded = await _syncGateway.upsertNote(conflictCopy);
    await _syncGateway.syncNoteAttachments(conflictCopy);
    await _noteRepository.update(
      conflictCopy.copyWith(
        lastSyncedAt: now,
        baseContentHash: conflictCopy.contentHash,
        remoteFileId: uploaded.remoteFileId,
        remoteEtag: uploaded.remoteEtag,
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
