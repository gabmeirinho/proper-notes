import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/proper_notes_app.dart';
import 'infrastructure/database/app_database.dart';
import 'infrastructure/repositories/drift_note_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  final database = AppDatabase();
  final noteRepository = DriftNoteRepository(database);

  runApp(
    ProperNotesApp(
      database: database,
      noteRepository: noteRepository,
    ),
  );
}
