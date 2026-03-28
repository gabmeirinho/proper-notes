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
    expect(repository.syncedIds, ['local-only']);
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
    expect(result.unchangedCount, 1);
    expect(gateway.uploadedNoteIds, isEmpty);
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
    expect(repository.conflictedIds, ['conflict']);
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

  @override
  Future<void> create(Note note) async {
    createdConflictCopies.add(note);
  }

  @override
  Future<List<Note>> getActiveNotesForSync() async => _localNotes;

  @override
  Future<List<Note>> getDeletedNotesForSync() async => _deletedNotes;

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
  }) async {
    syncedIds.add(id);
  }

  @override
  Future<void> restore(String id) async {}

  @override
  Future<List<Note>> searchNotes(String query) async => const [];

  @override
  Future<void> softDelete(String id, DateTime deletedAt) async {}

  @override
  Future<void> update(Note note) async {}

  @override
  Future<void> upsertRemoteNote(RemoteNote remoteNote) async {
    upsertedRemoteIds.add(remoteNote.id);
  }

  @override
  Stream<List<Note>> watchActiveNotes() => const Stream.empty();

  @override
  Stream<List<Note>> watchDeletedNotes() => const Stream.empty();
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
  Future<RemoteSyncBatch> fetchChangesSince(String token) async {
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
}

class _FakeSyncStateRepository implements SyncStateRepository {
  _FakeSyncStateRepository({
    this.initialToken,
  });

  final String? initialToken;
  String? savedToken;

  @override
  Future<String> getOrCreateDeviceId() async => 'test-device';

  @override
  Future<String?> getDriveSyncToken() async => initialToken;

  @override
  Future<void> setDriveSyncToken(String token) async {
    savedToken = token;
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
