import 'package:uuid/uuid.dart';

import '../../../core/utils/content_hash.dart';
import '../domain/note.dart';
import '../domain/note_repository.dart';
import '../domain/sync_status.dart';

class CreateNote {
  CreateNote({
    required NoteRepository repository,
    required String deviceId,
    Uuid? uuid,
  })  : _repository = repository,
        _deviceId = deviceId,
        _uuid = uuid ?? const Uuid();

  final NoteRepository _repository;
  final String _deviceId;
  final Uuid _uuid;

  Future<Note> call({
    required String title,
    String content = '',
  }) async {
    final now = DateTime.now().toUtc();
    final note = Note(
      id: _uuid.v4(),
      title: title,
      content: content,
      createdAt: now,
      updatedAt: now,
      syncStatus: SyncStatus.pendingUpload,
      contentHash: computeContentHash(content),
      deviceId: _deviceId,
    );

    await _repository.create(note);
    return note;
  }
}
