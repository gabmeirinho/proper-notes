import 'package:flutter_test/flutter_test.dart';
import 'package:proper_notes/core/utils/content_hash.dart';
import 'package:proper_notes/features/notes/domain/note.dart';
import 'package:proper_notes/features/notes/domain/note_repository.dart';
import 'package:proper_notes/features/notes/domain/sync_status.dart';
import 'package:proper_notes/features/sync/application/run_manual_sync.dart';
import 'package:proper_notes/features/sync/domain/remote_note.dart';
import 'package:proper_notes/features/sync/domain/sync_gateway.dart';
import 'package:proper_notes/features/sync/domain/sync_state_repository.dart';
import 'package:uuid/data.dart';
import 'package:uuid/uuid.dart';

void main() {
  test('uploads local-only notes', () async {
    final repository = _FakeNoteRepository(
      localNotes: [
        _localNote(
          id: 'local-only',
          content: '# local',
          baseContentHash: null,
        ),
      ],
    );
    final gateway = _FakeSyncGateway();
    final useCase = RunManualSync(
      noteRepository: repository,
      syncGateway: gateway,
      syncStateRepository: _FakeSyncStateRepository(),
    );

    final result = await useCase();

    expect(result.uploadedCount, 1);
    expect(gateway.uploadedNoteIds, ['local-only']);
    expect(gateway.syncedAttachmentNoteIds, ['local-only']);
    expect(repository.syncedIds, ['local-only']);
  });

  test('ensures remote attachments are downloaded before reconciliation',
      () async {
    final repository = _FakeNoteRepository();
    final gateway = _FakeSyncGateway(
      remoteNotes: [
        _remoteNote(
          id: 'remote-with-attachment',
          content: '![Screenshot](attachment://shot.png)',
        ),
      ],
    );
    final useCase = RunManualSync(
      noteRepository: repository,
      syncGateway: gateway,
      syncStateRepository: _FakeSyncStateRepository(),
    );

    await useCase();

    expect(gateway.ensuredAttachmentRemoteIds, ['remote-with-attachment']);
  });

  test('downloads remote-only notes', () async {
    final repository = _FakeNoteRepository();
    final gateway = _FakeSyncGateway(
      remoteNotes: [
        _remoteNote(id: 'remote-only', content: '# remote'),
      ],
    );
    final useCase = RunManualSync(
      noteRepository: repository,
      syncGateway: gateway,
      syncStateRepository: _FakeSyncStateRepository(),
    );

    final result = await useCase();

    expect(result.downloadedCount, 1);
    expect(repository.upsertedRemoteIds, ['remote-only']);
  });

  test('delta sync does not re-upload already-synced unchanged notes',
      () async {
    const content = 'same content';
    final repository = _FakeNoteRepository(
      localNotes: [
        _localNote(
          id: 'same',
          content: content,
          baseContentHash: computeContentHash(content),
          syncStatus: SyncStatus.synced,
          remoteFileId: 'remote-same',
        ),
      ],
    );
    final gateway = _FakeSyncGateway(
      remoteNotes: const [],
      changeBatchIsFullSnapshot: false,
    );
    final useCase = RunManualSync(
      noteRepository: repository,
      syncGateway: gateway,
      syncStateRepository: _FakeSyncStateRepository(initialToken: 'token-1'),
    );

    final result = await useCase();

    expect(result.uploadedCount, 0);
    expect(result.unchangedCount, 0);
    expect(gateway.uploadedNoteIds, isEmpty);
    expect(gateway.syncedAttachmentNoteIds, isEmpty);
  });

  test('does not sync attachments for already-synced unchanged notes',
      () async {
    const content = '![Screenshot](attachment://shot.png)';
    final repository = _FakeNoteRepository(
      localNotes: [
        _localNote(
          id: 'same-with-attachment',
          content: content,
          baseContentHash: computeContentHash(content),
          syncStatus: SyncStatus.synced,
          remoteFileId: 'remote-same-with-attachment',
        ),
      ],
    );
    final gateway = _FakeSyncGateway(
      remoteNotes: const [],
      changeBatchIsFullSnapshot: false,
    );
    final useCase = RunManualSync(
      noteRepository: repository,
      syncGateway: gateway,
      syncStateRepository: _FakeSyncStateRepository(initialToken: 'token-1'),
    );

    final result = await useCase();

    expect(result.uploadedCount, 0);
    expect(result.unchangedCount, 0);
    expect(gateway.syncedAttachmentNoteIds, isEmpty);
  });

  test('delta sync still uploads local pending notes without remote changes',
      () async {
    final repository = _FakeNoteRepository(
      localNotes: [
        _localNote(
          id: 'pending-local',
          content: '# local',
          baseContentHash: null,
        ),
      ],
    );
    final gateway = _FakeSyncGateway(
      remoteNotes: const [],
      changeBatchIsFullSnapshot: false,
    );
    final useCase = RunManualSync(
      noteRepository: repository,
      syncGateway: gateway,
      syncStateRepository: _FakeSyncStateRepository(initialToken: 'token-1'),
    );

    final result = await useCase();

    expect(result.uploadedCount, 1);
    expect(gateway.uploadedNoteIds, ['pending-local']);
  });

  test(
      'full snapshot reuploads a missing remote note instead of deleting local',
      () async {
    const content = 'trusted local content';
    final repository = _FakeNoteRepository(
      localNotes: [
        _localNote(
          id: 'missing-remotely',
          content: content,
          baseContentHash: computeContentHash(content),
          syncStatus: SyncStatus.synced,
          remoteFileId: 'notes/missing-remotely.json',
        ),
      ],
    );
    final gateway = _FakeSyncGateway();
    final useCase = RunManualSync(
      noteRepository: repository,
      syncGateway: gateway,
      syncStateRepository: _FakeSyncStateRepository(),
    );

    final result = await useCase();

    expect(result.uploadedCount, 1);
    expect(result.downloadedCount, 0);
    expect(repository.appliedRemoteDeletionIds, isEmpty);
    expect(gateway.uploadedNoteIds, ['missing-remotely']);
  });

  test('cursor write failure after upload is recoverable on retry', () async {
    final repository = _FakeNoteRepository(
      localNotes: [
        _localNote(
          id: 'retry-upload',
          content: 'local edit',
          baseContentHash: computeContentHash('base'),
        ),
      ],
    );
    final gateway = _FakeSyncGateway();
    final syncStateRepository = _FakeSyncStateRepository(
      initialToken: 'token-1',
      failNextCursorWrite: true,
    );
    final useCase = RunManualSync(
      noteRepository: repository,
      syncGateway: gateway,
      syncStateRepository: syncStateRepository,
    );

    await expectLater(useCase(), throwsA(isA<Exception>()));

    expect(gateway.uploadedNoteIds, ['retry-upload']);
    expect(repository.syncedIds, ['retry-upload']);
    expect(syncStateRepository.savedToken, isNull);

    final retryResult = await useCase();

    expect(retryResult.uploadedCount, 0);
    expect(gateway.uploadedNoteIds, ['retry-upload']);
    expect(syncStateRepository.savedToken, 'delta-token');
  });

  test('marks unchanged notes as synced when hashes match', () async {
    const content = 'same content';
    final repository = _FakeNoteRepository(
      localNotes: [
        _localNote(
          id: 'same',
          content: content,
          baseContentHash: computeContentHash(content),
        ),
      ],
    );
    final gateway = _FakeSyncGateway(
      remoteNotes: [
        _remoteNote(id: 'same', content: content),
      ],
    );
    final useCase = RunManualSync(
      noteRepository: repository,
      syncGateway: gateway,
      syncStateRepository: _FakeSyncStateRepository(initialToken: 'token-1'),
    );

    final result = await useCase();

    expect(result.unchangedCount, 1);
    expect(repository.syncedIds, ['same']);
  });

  test('re-downloads a remote note when local content does not match its hash',
      () async {
    const remoteContent = 'Organização com ação e ç';
    final repository = _FakeNoteRepository(
      localNotes: [
        Note(
          id: 'same',
          title: 'same',
          content: 'OrganizaÃ§Ã£o com aÃ§Ã£o e Ã§',
          createdAt: DateTime.utc(2026, 3, 24, 10),
          updatedAt: DateTime.utc(2026, 3, 24, 11),
          syncStatus: SyncStatus.synced,
          contentHash: computeContentHash(remoteContent),
          baseContentHash: computeContentHash(remoteContent),
          deviceId: 'device-a',
          remoteFileId: 'remote-same',
        ),
      ],
    );
    final gateway = _FakeSyncGateway(
      remoteNotes: [
        _remoteNote(
          id: 'same',
          content: remoteContent,
          remoteFileId: 'remote-same',
        ),
      ],
    );
    final useCase = RunManualSync(
      noteRepository: repository,
      syncGateway: gateway,
      syncStateRepository: _FakeSyncStateRepository(initialToken: 'token-1'),
    );

    final result = await useCase();

    expect(result.downloadedCount, 1);
    expect(result.unchangedCount, 0);
    expect(repository.upsertedRemoteIds, ['same']);
  });

  test('uploads local metadata-only changes when content hash is unchanged',
      () async {
    const content = 'same content';
    final repository = _FakeNoteRepository(
      localNotes: [
        Note(
          id: 'renamed-note',
          title: 'Local title',
          content: content,
          createdAt: DateTime.utc(2026, 3, 24, 10),
          updatedAt: DateTime.utc(2026, 3, 24, 11),
          syncStatus: SyncStatus.pendingUpload,
          contentHash: computeContentHash(content),
          baseContentHash: computeContentHash(content),
          deviceId: 'device-a',
          remoteFileId: 'remote-renamed-note',
        ),
      ],
    );
    final gateway = _FakeSyncGateway(
      remoteNotes: [
        RemoteNote(
          id: 'renamed-note',
          title: 'Remote title',
          content: content,
          createdAt: DateTime.utc(2026, 3, 24, 10),
          updatedAt: DateTime.utc(2026, 3, 24, 11),
          contentHash: computeContentHash(content),
          deviceId: 'device-b',
          remoteFileId: 'remote-renamed-note',
        ),
      ],
    );
    final useCase = RunManualSync(
      noteRepository: repository,
      syncGateway: gateway,
      syncStateRepository: _FakeSyncStateRepository(initialToken: 'token-1'),
    );

    final result = await useCase();

    expect(result.uploadedCount, 1);
    expect(gateway.uploadedNoteIds, ['renamed-note']);
    expect(repository.syncedIds, ['renamed-note']);
  });

  test('does not rewrite already-synced unchanged notes', () async {
    const content = 'same content';
    final repository = _FakeNoteRepository(
      localNotes: [
        _localNote(
          id: 'same-synced',
          content: content,
          baseContentHash: computeContentHash(content),
          syncStatus: SyncStatus.synced,
          remoteFileId: 'remote-same-synced',
        ),
      ],
    );
    final gateway = _FakeSyncGateway(
      remoteNotes: [
        _remoteNote(
          id: 'same-synced',
          content: content,
          remoteFileId: 'remote-same-synced',
        ),
      ],
    );
    final useCase = RunManualSync(
      noteRepository: repository,
      syncGateway: gateway,
      syncStateRepository: _FakeSyncStateRepository(initialToken: 'token-1'),
    );

    final result = await useCase();

    expect(result.unchangedCount, 1);
    expect(repository.syncedIds, isEmpty);
  });

  test(
      'downloads a remote update without conflict when local note has no base hash and is not dirty',
      () async {
    final repository = _FakeNoteRepository(
      localNotes: [
        _localNote(
          id: 'mobile-updated',
          content: 'old desktop content',
          baseContentHash: null,
          syncStatus: SyncStatus.synced,
          remoteFileId: 'remote-mobile-updated',
        ),
      ],
    );
    final gateway = _FakeSyncGateway(
      remoteNotes: [
        _remoteNote(
          id: 'mobile-updated',
          content: 'new mobile content',
          remoteFileId: 'remote-mobile-updated',
        ),
      ],
    );
    final useCase = RunManualSync(
      noteRepository: repository,
      syncGateway: gateway,
      syncStateRepository: _FakeSyncStateRepository(initialToken: 'token-1'),
      uuid: const _FixedUuid('unexpected-conflict-copy'),
    );

    final result = await useCase();

    expect(result.downloadedCount, 1);
    expect(result.conflictCount, 0);
    expect(repository.upsertedRemoteIds, ['mobile-updated']);
    expect(repository.createdConflictCopies, isEmpty);
    expect(gateway.uploadedNoteIds, isEmpty);
  });

  test('marks a conflict when both local and remote changed', () async {
    final repository = _FakeNoteRepository(
      localNotes: [
        _localNote(
          id: 'conflict',
          content: 'local changed',
          baseContentHash: computeContentHash('base'),
        ),
      ],
    );
    final gateway = _FakeSyncGateway(
      remoteNotes: [
        _remoteNote(id: 'conflict', content: 'remote changed'),
      ],
    );
    final useCase = RunManualSync(
      noteRepository: repository,
      syncGateway: gateway,
      syncStateRepository: _FakeSyncStateRepository(initialToken: 'token-1'),
      uuid: const _FixedUuid('conflict-copy-id'),
    );

    final result = await useCase();

    expect(result.conflictCount, 1);
    expect(repository.conflictedIds, isEmpty);
    expect(repository.syncedIds, ['conflict']);
    expect(gateway.uploadedNoteIds, ['conflict-copy-id', 'conflict']);
    expect(repository.createdConflictCopies, hasLength(1));
    expect(repository.createdConflictCopies.single.id, 'conflict-copy-id');
    expect(
      repository.createdConflictCopies.single.title,
      'conflict (Conflict Copy)',
    );
    expect(
      repository.createdConflictCopies.single.content,
      'remote changed',
    );
    expect(
      repository.createdConflictCopies.single.syncStatus,
      SyncStatus.conflicted,
    );
  });

  test(
      'uploads local note without conflict when concurrent content only differs by trailing whitespace',
      () async {
    final repository = _FakeNoteRepository(
      localNotes: [
        _localNote(
          id: 'whitespace-only',
          content: 'same visible content',
          baseContentHash: computeContentHash('base'),
          syncStatus: SyncStatus.pendingUpload,
          remoteFileId: 'remote-whitespace-only',
        ),
      ],
    );
    final gateway = _FakeSyncGateway(
      remoteNotes: [
        _remoteNote(
          id: 'whitespace-only',
          content: 'same visible content\n',
          remoteFileId: 'remote-whitespace-only',
        ),
      ],
    );
    final useCase = RunManualSync(
      noteRepository: repository,
      syncGateway: gateway,
      syncStateRepository: _FakeSyncStateRepository(initialToken: 'token-1'),
      uuid: const _FixedUuid('unexpected-conflict-copy'),
    );

    final result = await useCase();

    expect(result.conflictCount, 0);
    expect(result.uploadedCount, 1);
    expect(repository.createdConflictCopies, isEmpty);
    expect(gateway.uploadedNoteIds, ['whitespace-only']);
    expect(repository.syncedIds, ['whitespace-only']);
  });

  test('keeps conflict copies conflicted when later sync sees no changes',
      () async {
    const content = 'preserved conflict version';
    final repository = _FakeNoteRepository(
      localNotes: [
        _localNote(
          id: 'existing-conflict-copy',
          content: content,
          baseContentHash: computeContentHash(content),
          syncStatus: SyncStatus.conflicted,
          remoteFileId: 'remote-existing-conflict-copy',
        ),
      ],
    );
    final gateway = _FakeSyncGateway(
      remoteNotes: [
        _remoteNote(
          id: 'existing-conflict-copy',
          content: content,
          remoteFileId: 'remote-existing-conflict-copy',
        ),
      ],
    );
    final useCase = RunManualSync(
      noteRepository: repository,
      syncGateway: gateway,
      syncStateRepository: _FakeSyncStateRepository(initialToken: 'token-1'),
    );

    final result = await useCase();

    expect(result.unchangedCount, 1);
    expect(repository.syncedIds, isEmpty);
    expect(repository.updatedNotes, hasLength(1));
    expect(repository.updatedNotes.single.id, 'existing-conflict-copy');
    expect(repository.updatedNotes.single.syncStatus, SyncStatus.conflicted);
  });

  test('keeps conflict copies conflicted when remote metadata differs',
      () async {
    const content = 'preserved conflict version';
    final repository = _FakeNoteRepository(
      localNotes: [
        _localNote(
          id: 'metadata-conflict-copy',
          content: content,
          baseContentHash: computeContentHash(content),
          syncStatus: SyncStatus.conflicted,
          remoteFileId: 'remote-metadata-conflict-copy',
        ),
      ],
    );
    final gateway = _FakeSyncGateway(
      remoteNotes: [
        RemoteNote(
          id: 'metadata-conflict-copy',
          title: 'Renamed elsewhere',
          content: content,
          createdAt: DateTime.utc(2026, 3, 24, 10),
          updatedAt: DateTime.utc(2026, 3, 24, 11),
          contentHash: computeContentHash(content),
          deviceId: 'device-b',
          remoteFileId: 'remote-metadata-conflict-copy',
        ),
      ],
    );
    final useCase = RunManualSync(
      noteRepository: repository,
      syncGateway: gateway,
      syncStateRepository: _FakeSyncStateRepository(initialToken: 'token-1'),
    );

    final result = await useCase();

    expect(result.unchangedCount, 1);
    expect(repository.syncedIds, isEmpty);
    expect(repository.upsertedRemoteIds, isEmpty);
    expect(repository.updatedNotes.single.syncStatus, SyncStatus.conflicted);
  });

  test(
      'uploads a local edit without conflict when the remote note still matches the preserved base',
      () async {
    final repository = _FakeNoteRepository(
      localNotes: [
        _localNote(
          id: 'desktop-edit',
          content: 'desktop changed',
          baseContentHash: computeContentHash('mobile content'),
          syncStatus: SyncStatus.pendingUpload,
          remoteFileId: 'remote-desktop-edit',
        ),
      ],
    );
    final gateway = _FakeSyncGateway(
      remoteNotes: [
        _remoteNote(
          id: 'desktop-edit',
          content: 'mobile content',
          remoteFileId: 'remote-desktop-edit',
        ),
      ],
    );
    final useCase = RunManualSync(
      noteRepository: repository,
      syncGateway: gateway,
      syncStateRepository: _FakeSyncStateRepository(initialToken: 'token-1'),
      uuid: const _FixedUuid('unexpected-conflict-copy'),
    );

    final result = await useCase();

    expect(result.uploadedCount, 1);
    expect(result.conflictCount, 0);
    expect(gateway.uploadedNoteIds, ['desktop-edit']);
    expect(repository.createdConflictCopies, isEmpty);
    expect(repository.syncedIds, ['desktop-edit']);
  });

  test('uploads local tombstones when remote note is still active', () async {
    final repository = _FakeNoteRepository(
      deletedNotes: [
        _localNote(
          id: 'deleted-local',
          content: 'gone',
          baseContentHash: computeContentHash('gone'),
          deletedAt: DateTime.utc(2026, 3, 24, 12),
        ),
      ],
    );
    final gateway = _FakeSyncGateway(
      remoteNotes: [
        _remoteNote(id: 'deleted-local', content: 'gone'),
      ],
    );
    final useCase = RunManualSync(
      noteRepository: repository,
      syncGateway: gateway,
      syncStateRepository: _FakeSyncStateRepository(initialToken: 'token-1'),
    );

    final result = await useCase();

    expect(result.uploadedCount, 1);
    expect(gateway.uploadedNoteIds, ['deleted-local']);
  });

  test('applies a remote restore to a previously synced local tombstone',
      () async {
    const content = 'same content';
    final repository = _FakeNoteRepository(
      deletedNotes: [
        _localNote(
          id: 'restored-remotely',
          content: content,
          baseContentHash: computeContentHash(content),
          deletedAt: DateTime.utc(2026, 3, 24, 12),
          syncStatus: SyncStatus.synced,
          remoteFileId: 'remote-restored-remotely',
        ),
      ],
    );
    final gateway = _FakeSyncGateway(
      remoteNotes: [
        _remoteNote(
          id: 'restored-remotely',
          content: content,
          remoteFileId: 'remote-restored-remotely',
        ),
      ],
    );
    final useCase = RunManualSync(
      noteRepository: repository,
      syncGateway: gateway,
      syncStateRepository: _FakeSyncStateRepository(initialToken: 'token-1'),
    );

    final result = await useCase();

    expect(result.downloadedCount, 1);
    expect(result.uploadedCount, 0);
    expect(repository.upsertedRemoteIds, ['restored-remotely']);
    expect(gateway.uploadedNoteIds, isEmpty);
  });

  test('applies remote tombstones to unchanged local notes', () async {
    const content = 'same content';
    final repository = _FakeNoteRepository(
      localNotes: [
        _localNote(
          id: 'remote-delete',
          content: content,
          baseContentHash: computeContentHash(content),
          syncStatus: SyncStatus.synced,
          remoteFileId: 'remote-remote-delete',
        ),
      ],
    );
    final gateway = _FakeSyncGateway(
      remoteNotes: [
        _remoteNote(
          id: 'remote-delete',
          content: content,
          remoteFileId: 'remote-remote-delete',
          deletedAt: DateTime.utc(2026, 3, 24, 15),
        ),
      ],
    );
    final useCase = RunManualSync(
      noteRepository: repository,
      syncGateway: gateway,
      syncStateRepository: _FakeSyncStateRepository(initialToken: 'token-1'),
    );

    final result = await useCase();

    expect(result.downloadedCount, 1);
    expect(repository.appliedRemoteDeletionIds, ['remote-delete']);
  });

  test('uploads a local restore when the remote note is tombstoned', () async {
    const content = 'same content';
    final repository = _FakeNoteRepository(
      localNotes: [
        _localNote(
          id: 'restored-note',
          content: content,
          baseContentHash: computeContentHash(content),
          syncStatus: SyncStatus.pendingUpload,
          remoteFileId: 'remote-restored-note',
        ),
      ],
    );
    final gateway = _FakeSyncGateway(
      remoteNotes: [
        _remoteNote(
          id: 'restored-note',
          content: content,
          remoteFileId: 'remote-restored-note',
          deletedAt: DateTime.utc(2026, 3, 24, 15),
        ),
      ],
    );
    final useCase = RunManualSync(
      noteRepository: repository,
      syncGateway: gateway,
      syncStateRepository: _FakeSyncStateRepository(initialToken: 'token-1'),
    );

    final result = await useCase();

    expect(result.uploadedCount, 1);
    expect(result.downloadedCount, 0);
    expect(gateway.uploadedNoteIds, ['restored-note']);
    expect(repository.appliedRemoteDeletionIds, isEmpty);
  });

  test('preserves local edits as a conflict copy when remote deleted the note',
      () async {
    final repository = _FakeNoteRepository(
      localNotes: [
        _localNote(
          id: 'deleted-remotely',
          content: 'edited locally',
          baseContentHash: computeContentHash('base'),
          syncStatus: SyncStatus.synced,
          remoteFileId: 'remote-deleted-remotely',
        ),
      ],
    );
    final gateway = _FakeSyncGateway(
      remoteNotes: [
        _remoteNote(
          id: 'deleted-remotely',
          content: 'base',
          remoteFileId: 'remote-deleted-remotely',
          deletedAt: DateTime.utc(2026, 3, 24, 15),
        ),
      ],
    );
    final useCase = RunManualSync(
      noteRepository: repository,
      syncGateway: gateway,
      syncStateRepository: _FakeSyncStateRepository(initialToken: 'token-1'),
      uuid: const _FixedUuid('local-conflict-copy'),
    );

    final result = await useCase();

    expect(result.conflictCount, 1);
    expect(result.downloadedCount, 1);
    expect(repository.appliedRemoteDeletionIds, ['deleted-remotely']);
    expect(repository.createdConflictCopies, hasLength(1));
    expect(repository.createdConflictCopies.single.id, 'local-conflict-copy');
    expect(repository.createdConflictCopies.single.content, 'edited locally');
    expect(gateway.uploadedNoteIds, ['local-conflict-copy']);
  });

  test('preserves remote edits as a conflict copy when local deleted the note',
      () async {
    final repository = _FakeNoteRepository(
      deletedNotes: [
        _localNote(
          id: 'edited-remotely',
          content: 'base',
          baseContentHash: computeContentHash('base'),
          deletedAt: DateTime.utc(2026, 3, 24, 12),
          remoteFileId: 'remote-edited-remotely',
        ),
      ],
    );
    final gateway = _FakeSyncGateway(
      remoteNotes: [
        _remoteNote(
          id: 'edited-remotely',
          content: 'edited remotely',
          remoteFileId: 'remote-edited-remotely',
        ),
      ],
    );
    final useCase = RunManualSync(
      noteRepository: repository,
      syncGateway: gateway,
      syncStateRepository: _FakeSyncStateRepository(initialToken: 'token-1'),
      uuid: const _FixedUuid('remote-conflict-copy'),
    );

    final result = await useCase();

    expect(result.conflictCount, 1);
    expect(result.uploadedCount, 1);
    expect(repository.createdConflictCopies, hasLength(1));
    expect(repository.createdConflictCopies.single.id, 'remote-conflict-copy');
    expect(repository.createdConflictCopies.single.content, 'edited remotely');
    expect(
      gateway.uploadedNoteIds,
      ['remote-conflict-copy', 'edited-remotely'],
    );
  });

  test('stale device preserves both edits after returning offline', () async {
    const baseContent = 'shared base';
    final remoteStore = _SharedRemoteStore()
      ..seed(_remoteNote(id: 'stale-note', content: baseContent));
    final desktop = _SyncingNoteRepository(
      deviceId: 'desktop',
      initialNotes: [
        _syncedNote(
          id: 'stale-note',
          content: baseContent,
          deviceId: 'desktop',
        ),
      ],
    );
    final mobile = _SyncingNoteRepository(
      deviceId: 'mobile',
      initialNotes: [
        _syncedNote(
          id: 'stale-note',
          content: baseContent,
          deviceId: 'mobile',
        ),
      ],
    );
    final desktopSync = RunManualSync(
      noteRepository: desktop,
      syncGateway: _SharedRemoteSyncGateway(remoteStore),
      syncStateRepository:
          _FakeSyncStateRepository(initialToken: 'desktop-old'),
    );
    final mobileSync = RunManualSync(
      noteRepository: mobile,
      syncGateway: _SharedRemoteSyncGateway(remoteStore),
      syncStateRepository: _FakeSyncStateRepository(initialToken: 'mobile-old'),
      uuid: const _FixedUuid('stale-conflict-copy'),
    );

    desktop.editLocal('stale-note', 'desktop edit while mobile was away');
    await desktopSync();
    mobile.editLocal('stale-note', 'mobile stale edit');

    final result = await mobileSync();

    expect(result.conflictCount, 1);
    expect(mobile.noteById('stale-note')?.content, 'mobile stale edit');
    expect(
      mobile.noteById('stale-conflict-copy')?.content,
      'desktop edit while mobile was away',
    );
    expect(
      remoteStore.noteById('stale-note')?.content,
      'mobile stale edit',
    );
    expect(
      remoteStore.noteById('stale-conflict-copy')?.content,
      'desktop edit while mobile was away',
    );
  });

  test('offline edit survives when another device deleted the note first',
      () async {
    const baseContent = 'delete edit base';
    final remoteStore = _SharedRemoteStore()
      ..seed(_remoteNote(id: 'delete-edit', content: baseContent));
    final deletingDevice = _SyncingNoteRepository(
      deviceId: 'deleter',
      initialNotes: [
        _syncedNote(
          id: 'delete-edit',
          content: baseContent,
          deviceId: 'deleter',
        ),
      ],
    );
    final editingDevice = _SyncingNoteRepository(
      deviceId: 'editor',
      initialNotes: [
        _syncedNote(
          id: 'delete-edit',
          content: baseContent,
          deviceId: 'editor',
        ),
      ],
    );

    deletingDevice.deleteLocal('delete-edit');
    await RunManualSync(
      noteRepository: deletingDevice,
      syncGateway: _SharedRemoteSyncGateway(remoteStore),
      syncStateRepository: _FakeSyncStateRepository(initialToken: 'delete-old'),
    )();

    editingDevice.editLocal('delete-edit', 'offline edit to preserve');
    final result = await RunManualSync(
      noteRepository: editingDevice,
      syncGateway: _SharedRemoteSyncGateway(remoteStore),
      syncStateRepository: _FakeSyncStateRepository(initialToken: 'edit-old'),
      uuid: const _FixedUuid('delete-edit-conflict-copy'),
    )();

    expect(result.conflictCount, 1);
    expect(editingDevice.noteById('delete-edit')?.deletedAt, isNotNull);
    expect(
      editingDevice.noteById('delete-edit-conflict-copy')?.content,
      'offline edit to preserve',
    );
    expect(remoteStore.noteById('delete-edit')?.deletedAt, isNotNull);
    expect(
      remoteStore.noteById('delete-edit-conflict-copy')?.content,
      'offline edit to preserve',
    );
  });

  test('tombstone restore cycle converges across devices', () async {
    const content = 'restore cycle content';
    final remoteStore = _SharedRemoteStore()
      ..seed(_remoteNote(id: 'restore-cycle', content: content));
    final firstDevice = _SyncingNoteRepository(
      deviceId: 'device-a',
      initialNotes: [
        _syncedNote(
          id: 'restore-cycle',
          content: content,
          deviceId: 'device-a',
        ),
      ],
    );
    final secondDevice = _SyncingNoteRepository(
      deviceId: 'device-b',
      initialNotes: [
        _syncedNote(
          id: 'restore-cycle',
          content: content,
          deviceId: 'device-b',
        ),
      ],
    );
    final firstSyncState = _FakeSyncStateRepository(initialToken: 'first-old');
    final secondSyncState =
        _FakeSyncStateRepository(initialToken: 'second-old');

    firstDevice.deleteLocal('restore-cycle');
    await RunManualSync(
      noteRepository: firstDevice,
      syncGateway: _SharedRemoteSyncGateway(remoteStore),
      syncStateRepository: firstSyncState,
    )();

    await RunManualSync(
      noteRepository: secondDevice,
      syncGateway: _SharedRemoteSyncGateway(remoteStore),
      syncStateRepository: secondSyncState,
    )();
    expect(secondDevice.noteById('restore-cycle')?.deletedAt, isNotNull);

    secondDevice.restoreLocal('restore-cycle');
    await RunManualSync(
      noteRepository: secondDevice,
      syncGateway: _SharedRemoteSyncGateway(remoteStore),
      syncStateRepository: secondSyncState,
    )();

    await RunManualSync(
      noteRepository: firstDevice,
      syncGateway: _SharedRemoteSyncGateway(remoteStore),
      syncStateRepository: firstSyncState,
    )();

    expect(remoteStore.noteById('restore-cycle')?.deletedAt, isNull);
    expect(firstDevice.noteById('restore-cycle')?.deletedAt, isNull);
    expect(secondDevice.noteById('restore-cycle')?.deletedAt, isNull);
    expect(
        firstDevice.noteById('restore-cycle')?.syncStatus, SyncStatus.synced);
    expect(
      secondDevice.noteById('restore-cycle')?.syncStatus,
      SyncStatus.synced,
    );
  });

  test('partial tombstone upload failure is recoverable on retry', () async {
    const content = 'partial failure content';
    final remoteStore = _SharedRemoteStore()
      ..seed(_remoteNote(id: 'partial-delete', content: content));
    final repository = _SyncingNoteRepository(
      deviceId: 'device-a',
      initialNotes: [
        _syncedNote(
          id: 'partial-delete',
          content: content,
          deviceId: 'device-a',
        ),
      ],
    );
    final gateway = _SharedRemoteSyncGateway(
      remoteStore,
      failAfterPersistingUploadForId: 'partial-delete',
    );
    final syncState = _FakeSyncStateRepository(initialToken: 'partial-old');
    final useCase = RunManualSync(
      noteRepository: repository,
      syncGateway: gateway,
      syncStateRepository: syncState,
    );

    repository.deleteLocal('partial-delete');

    await expectLater(useCase(), throwsA(isA<Exception>()));

    expect(remoteStore.noteById('partial-delete')?.deletedAt, isNotNull);
    expect(
      repository.noteById('partial-delete')?.syncStatus,
      SyncStatus.pendingDelete,
    );
    expect(syncState.savedToken, isNull);

    final retryResult = await useCase();

    expect(retryResult.uploadedCount, 0);
    expect(repository.noteById('partial-delete')?.deletedAt, isNotNull);
    expect(
        repository.noteById('partial-delete')?.syncStatus, SyncStatus.synced);
    expect(syncState.savedToken, isNotNull);
  });

  test('two local repositories converge through one shared fake remote',
      () async {
    final remoteStore = _SharedRemoteStore();
    final firstDevice = _SyncingNoteRepository(deviceId: 'device-a');
    final secondDevice = _SyncingNoteRepository(deviceId: 'device-b');
    final firstSyncState = _FakeSyncStateRepository();
    final secondSyncState = _FakeSyncStateRepository();

    firstDevice.addLocalNote(
      id: 'e2e-note',
      title: 'E2E note',
      content: 'created on first device',
    );
    await RunManualSync(
      noteRepository: firstDevice,
      syncGateway: _SharedRemoteSyncGateway(remoteStore),
      syncStateRepository: firstSyncState,
    )();

    await RunManualSync(
      noteRepository: secondDevice,
      syncGateway: _SharedRemoteSyncGateway(remoteStore),
      syncStateRepository: secondSyncState,
    )();
    expect(
      secondDevice.noteById('e2e-note')?.content,
      'created on first device',
    );

    secondDevice.editLocal('e2e-note', 'edited on second device');
    await RunManualSync(
      noteRepository: secondDevice,
      syncGateway: _SharedRemoteSyncGateway(remoteStore),
      syncStateRepository: secondSyncState,
    )();

    await RunManualSync(
      noteRepository: firstDevice,
      syncGateway: _SharedRemoteSyncGateway(remoteStore),
      syncStateRepository: firstSyncState,
    )();
    expect(
        firstDevice.noteById('e2e-note')?.content, 'edited on second device');

    firstDevice.deleteLocal('e2e-note');
    await RunManualSync(
      noteRepository: firstDevice,
      syncGateway: _SharedRemoteSyncGateway(remoteStore),
      syncStateRepository: firstSyncState,
    )();

    await RunManualSync(
      noteRepository: secondDevice,
      syncGateway: _SharedRemoteSyncGateway(remoteStore),
      syncStateRepository: secondSyncState,
    )();

    expect(remoteStore.noteById('e2e-note')?.deletedAt, isNotNull);
    expect(firstDevice.noteById('e2e-note')?.deletedAt, isNotNull);
    expect(secondDevice.noteById('e2e-note')?.deletedAt, isNotNull);
  });
}

class _FakeNoteRepository implements NoteRepository {
  _FakeNoteRepository({
    List<Note>? localNotes,
    List<Note>? deletedNotes,
  })  : _localNotes = localNotes ?? <Note>[],
        _deletedNotes = deletedNotes ?? <Note>[];

  final List<Note> _localNotes;
  final List<Note> _deletedNotes;
  final List<String> syncedIds = [];
  final List<String> conflictedIds = [];
  final List<String> upsertedRemoteIds = [];
  final List<String> appliedRemoteDeletionIds = [];
  final List<Note> createdConflictCopies = [];
  final List<Note> updatedNotes = [];

  @override
  Future<int> countAttachmentReferences(String attachmentUri) async => 0;

  @override
  Future<void> create(Note note) async {
    createdConflictCopies.add(note);
  }

  @override
  Future<List<Note>> getByIds(Iterable<String> ids) async {
    final idSet = ids.toSet();
    return [
      ..._localNotes.where((note) => idSet.contains(note.id)),
      ..._deletedNotes.where((note) => idSet.contains(note.id)),
    ];
  }

  @override
  Future<List<Note>> getActiveNotesForSync() async => _localNotes;

  @override
  Future<List<Note>> getDeletedNotesForSync() async => _deletedNotes;

  @override
  Future<List<Note>> getPendingNotesForSync() async {
    return [
      ..._localNotes,
      ..._deletedNotes,
    ].where((note) {
      return note.syncStatus == SyncStatus.pendingUpload ||
          note.syncStatus == SyncStatus.pendingDelete;
    }).toList(growable: false);
  }

  @override
  Future<Map<String, String?>> getRemoteEtagsByPath() async => {
        for (final note in [..._localNotes, ..._deletedNotes])
          if (note.remoteFileId != null) note.remoteFileId!: note.remoteEtag,
      };

  @override
  Future<Note?> getById(String id) async => null;

  @override
  Future<void> applyRemoteDeletion(RemoteNote remoteNote) async {
    appliedRemoteDeletionIds.add(remoteNote.id);
  }

  @override
  Future<void> markConflict(String id) async {
    conflictedIds.add(id);
  }

  @override
  Future<void> markSynced({
    required String id,
    required DateTime syncedAt,
    required String baseContentHash,
    String? remoteFileId,
    String? remoteEtag,
  }) async {
    syncedIds.add(id);
    _replaceNote(
      id,
      (note) => note.copyWith(
        lastSyncedAt: syncedAt,
        baseContentHash: baseContentHash,
        remoteFileId: remoteFileId,
        remoteEtag: remoteEtag,
        syncStatus: SyncStatus.synced,
      ),
    );
  }

  @override
  Future<void> restore(String id) async {}

  @override
  Future<List<Note>> searchNotes(String query, {String? folderPath}) async =>
      const [];

  @override
  Future<void> softDelete(String id, DateTime deletedAt) async {}

  @override
  Future<void> update(Note note) async {
    updatedNotes.add(note);
    _replaceNote(note.id, (_) => note);
  }

  @override
  Future<void> upsertRemoteNote(RemoteNote remoteNote) async {
    upsertedRemoteIds.add(remoteNote.id);
  }

  @override
  Stream<List<Note>> watchActiveNotes({String? folderPath}) =>
      const Stream.empty();

  @override
  Stream<List<Note>> watchDeletedNotes({String? folderPath}) =>
      const Stream.empty();

  void _replaceNote(String id, Note Function(Note note) update) {
    final activeIndex = _localNotes.indexWhere((note) => note.id == id);
    if (activeIndex != -1) {
      _localNotes[activeIndex] = update(_localNotes[activeIndex]);
      return;
    }

    final deletedIndex = _deletedNotes.indexWhere((note) => note.id == id);
    if (deletedIndex != -1) {
      _deletedNotes[deletedIndex] = update(_deletedNotes[deletedIndex]);
    }
  }
}

class _FixedUuid extends Uuid {
  const _FixedUuid(this.value);

  final String value;

  @override
  String v4({
    V4Options? config,
    Map<String, dynamic>? options,
  }) =>
      value;
}

class _FakeSyncGateway implements SyncGateway {
  _FakeSyncGateway({
    List<RemoteNote>? remoteNotes,
    this.changeBatchIsFullSnapshot = false,
  }) : _remoteNotes = remoteNotes ?? <RemoteNote>[];

  final List<RemoteNote> _remoteNotes;
  final bool changeBatchIsFullSnapshot;
  final List<String> uploadedNoteIds = [];
  final List<String> syncedAttachmentNoteIds = [];
  final List<String> ensuredAttachmentRemoteIds = [];
  int bootstrapCalls = 0;
  final List<String> changeTokens = [];

  @override
  Future<RemoteSyncBatch> bootstrap() async {
    bootstrapCalls += 1;
    return RemoteSyncBatch(
      notes: _remoteNotes,
      nextToken: 'bootstrap-token',
      isFullSnapshot: true,
    );
  }

  @override
  Future<RemoteSyncBatch> fetchChangesSince(
    String token, {
    Map<String, String?> knownRemoteEtags = const <String, String?>{},
  }) async {
    changeTokens.add(token);
    return RemoteSyncBatch(
      notes: _remoteNotes,
      nextToken: 'delta-token',
      isFullSnapshot: changeBatchIsFullSnapshot,
    );
  }

  @override
  Future<List<RemoteNote>> fetchAllNotes() async => _remoteNotes;

  @override
  Future<RemoteNote> upsertNote(Note note) async {
    uploadedNoteIds.add(note.id);
    return _remoteNote(
      id: note.id,
      content: note.content,
      remoteFileId: 'remote-${note.id}',
    );
  }

  @override
  Future<void> syncNoteAttachments(Note note) async {
    syncedAttachmentNoteIds.add(note.id);
  }

  @override
  Future<void> ensureRemoteAttachmentsAvailable(List<RemoteNote> notes) async {
    ensuredAttachmentRemoteIds.addAll(notes.map((note) => note.id));
  }
}

class _FakeSyncStateRepository implements SyncStateRepository {
  _FakeSyncStateRepository({
    this.initialToken,
    this.failNextCursorWrite = false,
  }) : _currentToken = initialToken;

  final String? initialToken;
  String? _currentToken;
  bool failNextCursorWrite;
  String? savedToken;

  @override
  Future<String> getOrCreateDeviceId() async => 'test-device';

  @override
  Future<String?> getRemoteSyncCursor() async => _currentToken;

  @override
  Future<void> setRemoteSyncCursor(String token) async {
    if (failNextCursorWrite) {
      failNextCursorWrite = false;
      throw Exception('cursor write failed');
    }
    savedToken = token;
    _currentToken = token;
  }
}

class _SharedRemoteStore {
  final Map<String, RemoteNote> _notesById = <String, RemoteNote>{};
  int _version = 0;

  String get cursor => 'shared-remote-$_version';

  List<RemoteNote> get snapshot {
    final notes = _notesById.values.toList(growable: false)
      ..sort((a, b) => a.id.compareTo(b.id));
    return notes;
  }

  RemoteNote? noteById(String id) => _notesById[id];

  void seed(RemoteNote note) {
    _notesById[note.id] = note;
    _version += 1;
  }

  RemoteNote upsert(Note note) {
    _version += 1;
    final remotePath = note.deletedAt == null
        ? 'notes/${note.id}.json'
        : 'tombstones/${note.id}.json';
    final remoteNote = RemoteNote(
      id: note.id,
      title: note.title,
      content: note.content,
      documentJson: note.documentJson,
      createdAt: note.createdAt,
      updatedAt: note.updatedAt,
      deletedAt: note.deletedAt,
      contentHash: note.contentHash,
      baseContentHash: note.contentHash,
      deviceId: note.deviceId,
      folderPath: note.folderPath,
      remoteFileId: remotePath,
      remoteEtag: '"$_version"',
    );
    _notesById[note.id] = remoteNote;
    return remoteNote;
  }
}

class _SharedRemoteSyncGateway implements SyncGateway {
  _SharedRemoteSyncGateway(
    this._remoteStore, {
    this.failAfterPersistingUploadForId,
  });

  final _SharedRemoteStore _remoteStore;
  String? failAfterPersistingUploadForId;
  final List<String> uploadedNoteIds = [];
  final List<String> syncedAttachmentNoteIds = [];

  @override
  Future<RemoteSyncBatch> bootstrap() async {
    return RemoteSyncBatch(
      notes: _remoteStore.snapshot,
      nextToken: _remoteStore.cursor,
      isFullSnapshot: true,
    );
  }

  @override
  Future<void> ensureRemoteAttachmentsAvailable(List<RemoteNote> notes) async {}

  @override
  Future<RemoteSyncBatch> fetchChangesSince(
    String token, {
    Map<String, String?> knownRemoteEtags = const <String, String?>{},
  }) async {
    if (token == _remoteStore.cursor) {
      return RemoteSyncBatch(
        notes: const <RemoteNote>[],
        nextToken: token,
        isFullSnapshot: false,
      );
    }

    return RemoteSyncBatch(
      notes: _remoteStore.snapshot,
      nextToken: _remoteStore.cursor,
      isFullSnapshot: false,
    );
  }

  @override
  Future<List<RemoteNote>> fetchAllNotes() async => _remoteStore.snapshot;

  @override
  Future<void> syncNoteAttachments(Note note) async {
    syncedAttachmentNoteIds.add(note.id);
  }

  @override
  Future<RemoteNote> upsertNote(Note note) async {
    uploadedNoteIds.add(note.id);
    final remoteNote = _remoteStore.upsert(note);
    if (failAfterPersistingUploadForId == note.id) {
      failAfterPersistingUploadForId = null;
      throw Exception('simulated partial WebDAV upload failure');
    }
    return remoteNote;
  }
}

class _SyncingNoteRepository implements NoteRepository {
  _SyncingNoteRepository({
    required this.deviceId,
    List<Note>? initialNotes,
  }) {
    for (final note in initialNotes ?? const <Note>[]) {
      _notesById[note.id] = note;
    }
  }

  final String deviceId;
  final Map<String, Note> _notesById = <String, Note>{};
  final List<String> appliedRemoteDeletionIds = [];
  final List<String> upsertedRemoteIds = [];

  Note? noteById(String id) => _notesById[id];

  void addLocalNote({
    required String id,
    required String title,
    required String content,
  }) {
    final now = DateTime.utc(2026, 4, 1, 10, _notesById.length);
    _notesById[id] = Note(
      id: id,
      title: title,
      content: content,
      createdAt: now,
      updatedAt: now,
      syncStatus: SyncStatus.pendingUpload,
      contentHash: computeContentHash(content),
      deviceId: deviceId,
    );
  }

  void editLocal(String id, String content) {
    final note = _notesById[id];
    if (note == null) {
      throw StateError('Cannot edit missing note $id');
    }
    _notesById[id] = note.copyWith(
      content: content,
      updatedAt: note.updatedAt.add(const Duration(minutes: 1)),
      syncStatus: SyncStatus.pendingUpload,
      contentHash: computeContentHash(content),
      deviceId: deviceId,
      clearDeletedAt: true,
    );
  }

  void deleteLocal(String id) {
    final note = _notesById[id];
    if (note == null) {
      throw StateError('Cannot delete missing note $id');
    }
    _notesById[id] = note.copyWith(
      deletedAt: note.updatedAt.add(const Duration(minutes: 1)),
      syncStatus: SyncStatus.pendingDelete,
      deviceId: deviceId,
    );
  }

  void restoreLocal(String id) {
    final note = _notesById[id];
    if (note == null) {
      throw StateError('Cannot restore missing note $id');
    }
    _notesById[id] = note.copyWith(
      clearDeletedAt: true,
      updatedAt: note.updatedAt.add(const Duration(minutes: 1)),
      syncStatus: SyncStatus.pendingUpload,
      contentHash: computeContentHash(note.content),
      deviceId: deviceId,
    );
  }

  @override
  Future<int> countAttachmentReferences(String attachmentUri) async => 0;

  @override
  Future<void> create(Note note) async {
    _notesById[note.id] = note;
  }

  @override
  Future<void> applyRemoteDeletion(RemoteNote remoteNote) async {
    appliedRemoteDeletionIds.add(remoteNote.id);
    final existing = _notesById[remoteNote.id];
    final deletedAt = remoteNote.deletedAt ?? DateTime.now().toUtc();
    final syncedAt = DateTime.now().toUtc();
    if (existing == null) {
      _notesById[remoteNote.id] = Note(
        id: remoteNote.id,
        title: remoteNote.title,
        content: remoteNote.content,
        documentJson: remoteNote.documentJson,
        createdAt: remoteNote.createdAt,
        updatedAt: remoteNote.updatedAt,
        deletedAt: deletedAt,
        lastSyncedAt: syncedAt,
        syncStatus: SyncStatus.synced,
        contentHash: remoteNote.contentHash,
        baseContentHash: remoteNote.baseContentHash ?? remoteNote.contentHash,
        deviceId: remoteNote.deviceId,
        folderPath: remoteNote.folderPath,
        remoteFileId: remoteNote.remoteFileId,
        remoteEtag: remoteNote.remoteEtag,
      );
      return;
    }

    _notesById[remoteNote.id] = existing.copyWith(
      title: remoteNote.title.isEmpty ? existing.title : remoteNote.title,
      content:
          remoteNote.content.isEmpty ? existing.content : remoteNote.content,
      documentJson: remoteNote.content.isEmpty
          ? existing.documentJson
          : remoteNote.documentJson,
      updatedAt: remoteNote.updatedAt,
      deletedAt: deletedAt,
      lastSyncedAt: syncedAt,
      syncStatus: SyncStatus.synced,
      contentHash: remoteNote.contentHash,
      baseContentHash: remoteNote.baseContentHash ?? remoteNote.contentHash,
      deviceId: remoteNote.deviceId,
      folderPath: remoteNote.folderPath,
      remoteFileId: remoteNote.remoteFileId,
      remoteEtag: remoteNote.remoteEtag,
    );
  }

  @override
  Future<Note?> getById(String id) async => _notesById[id];

  @override
  Future<List<Note>> getActiveNotesForSync() async {
    return _notesById.values
        .where((note) => note.deletedAt == null)
        .toList(growable: false);
  }

  @override
  Future<List<Note>> getByIds(Iterable<String> ids) async {
    final idSet = ids.toSet();
    return _notesById.values
        .where((note) => idSet.contains(note.id))
        .toList(growable: false);
  }

  @override
  Future<List<Note>> getDeletedNotesForSync() async {
    return _notesById.values
        .where((note) => note.deletedAt != null)
        .toList(growable: false);
  }

  @override
  Future<List<Note>> getPendingNotesForSync() async {
    return _notesById.values.where((note) {
      return note.syncStatus == SyncStatus.pendingUpload ||
          note.syncStatus == SyncStatus.pendingDelete;
    }).toList(growable: false);
  }

  @override
  Future<Map<String, String?>> getRemoteEtagsByPath() async => {
        for (final note in _notesById.values)
          if (note.remoteFileId != null) note.remoteFileId!: note.remoteEtag,
      };

  @override
  Future<void> markConflict(String id) async {
    final note = _notesById[id];
    if (note != null) {
      _notesById[id] = note.copyWith(syncStatus: SyncStatus.conflicted);
    }
  }

  @override
  Future<void> markSynced({
    required String id,
    required DateTime syncedAt,
    required String baseContentHash,
    String? remoteFileId,
    String? remoteEtag,
  }) async {
    final note = _notesById[id];
    if (note == null) {
      return;
    }
    _notesById[id] = note.copyWith(
      lastSyncedAt: syncedAt,
      baseContentHash: baseContentHash,
      remoteFileId: remoteFileId,
      remoteEtag: remoteEtag,
      syncStatus: SyncStatus.synced,
    );
  }

  @override
  Future<void> restore(String id) async {
    restoreLocal(id);
  }

  @override
  Future<List<Note>> searchNotes(String query, {String? folderPath}) async {
    return _notesById.values
        .where((note) => note.deletedAt == null && note.content.contains(query))
        .toList(growable: false);
  }

  @override
  Future<void> softDelete(String id, DateTime deletedAt) async {
    final note = _notesById[id];
    if (note != null) {
      _notesById[id] = note.copyWith(
        deletedAt: deletedAt,
        syncStatus: SyncStatus.pendingDelete,
      );
    }
  }

  @override
  Future<void> update(Note note) async {
    _notesById[note.id] = note;
  }

  @override
  Future<void> upsertRemoteNote(RemoteNote remoteNote) async {
    upsertedRemoteIds.add(remoteNote.id);
    final syncedAt = DateTime.now().toUtc();
    final existing = _notesById[remoteNote.id];
    final syncedNote = Note(
      id: remoteNote.id,
      title: remoteNote.title,
      content: remoteNote.content,
      documentJson: remoteNote.documentJson,
      createdAt: remoteNote.createdAt,
      updatedAt: remoteNote.updatedAt,
      deletedAt: remoteNote.deletedAt,
      lastSyncedAt: syncedAt,
      syncStatus: SyncStatus.synced,
      contentHash: remoteNote.contentHash,
      baseContentHash: remoteNote.baseContentHash ?? remoteNote.contentHash,
      deviceId: remoteNote.deviceId,
      folderPath: remoteNote.folderPath,
      remoteFileId: remoteNote.remoteFileId,
      remoteEtag: remoteNote.remoteEtag,
    );

    if (existing == null || remoteNote.deletedAt != null) {
      _notesById[remoteNote.id] = syncedNote;
      return;
    }

    _notesById[remoteNote.id] = syncedNote.copyWith(clearDeletedAt: true);
  }

  @override
  Stream<List<Note>> watchActiveNotes({String? folderPath}) {
    return const Stream<List<Note>>.empty();
  }

  @override
  Stream<List<Note>> watchDeletedNotes({String? folderPath}) {
    return const Stream<List<Note>>.empty();
  }
}

Note _localNote({
  required String id,
  required String content,
  required String? baseContentHash,
  DateTime? deletedAt,
  SyncStatus? syncStatus,
  String? remoteFileId,
}) {
  return Note(
    id: id,
    title: id,
    content: content,
    createdAt: DateTime.utc(2026, 3, 24, 10),
    updatedAt: DateTime.utc(2026, 3, 24, 11),
    deletedAt: deletedAt,
    lastSyncedAt: null,
    syncStatus: syncStatus ??
        (deletedAt == null
            ? SyncStatus.pendingUpload
            : SyncStatus.pendingDelete),
    contentHash: computeContentHash(content),
    baseContentHash: baseContentHash,
    deviceId: 'device-a',
    remoteFileId: remoteFileId,
  );
}

Note _syncedNote({
  required String id,
  required String content,
  required String deviceId,
}) {
  return Note(
    id: id,
    title: id,
    content: content,
    createdAt: DateTime.utc(2026, 3, 24, 10),
    updatedAt: DateTime.utc(2026, 3, 24, 11),
    lastSyncedAt: DateTime.utc(2026, 3, 24, 12),
    syncStatus: SyncStatus.synced,
    contentHash: computeContentHash(content),
    baseContentHash: computeContentHash(content),
    deviceId: deviceId,
    remoteFileId: 'notes/$id.json',
    remoteEtag: '"seed-$id"',
  );
}

RemoteNote _remoteNote({
  required String id,
  required String content,
  String? remoteFileId,
  DateTime? deletedAt,
}) {
  return RemoteNote(
    id: id,
    title: id,
    content: content,
    createdAt: DateTime.utc(2026, 3, 24, 10),
    updatedAt: DateTime.utc(2026, 3, 24, 11),
    deletedAt: deletedAt,
    contentHash: computeContentHash(content),
    deviceId: 'device-b',
    remoteFileId: remoteFileId ?? 'remote-$id',
  );
}
