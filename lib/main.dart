import 'package:flutter/material.dart';

import 'app/proper_notes_app.dart';
import 'infrastructure/database/app_database.dart';
import 'infrastructure/repositories/drift_note_repository.dart';

void main() {
  final database = AppDatabase();
  final noteRepository = DriftNoteRepository(database);

  runApp(
    ProperNotesApp(
      database: database,
      noteRepository: noteRepository,
    ),
  );
}
