import 'package:flutter/material.dart';

import '../features/auth/application/auth_controller.dart';
import '../features/notes/application/create_folder.dart';
import '../features/notes/application/create_note.dart';
import '../features/notes/application/delete_folder.dart';
import '../features/notes/application/delete_note.dart';
import '../features/notes/application/move_note.dart';
import '../features/notes/application/rename_folder.dart';
import '../features/notes/application/restore_note.dart';
import '../features/notes/application/search_notes.dart';
import '../features/notes/application/update_note.dart';
import '../features/notes/domain/folder_repository.dart';
import '../features/notes/domain/note_repository.dart';
import '../features/notes/presentation/notes_home_page.dart';
import '../features/sync/application/run_manual_sync.dart';
import '../features/sync/application/sync_controller.dart';
import '../infrastructure/auth/google_auth_config.dart';
import '../infrastructure/auth/google_auth_service.dart';
import '../infrastructure/auth/google_oauth_token_client.dart';
import '../infrastructure/auth/oauth_session_store.dart';
import '../infrastructure/database/app_database.dart';
import '../infrastructure/repositories/drift_folder_repository.dart';
import '../infrastructure/repositories/drift_sync_state_repository.dart';
import '../infrastructure/sync/google_drive_sync_gateway.dart';

class ProperNotesApp extends StatefulWidget {
  const ProperNotesApp({
    required this.database,
    required this.noteRepository,
    super.key,
  });

  final AppDatabase database;
  final NoteRepository noteRepository;

  @override
  State<ProperNotesApp> createState() => _ProperNotesAppState();
}

class _ProperNotesAppState extends State<ProperNotesApp> {
  late final AuthController _authController;
  late final SyncController _syncController;
  late final GoogleAuthConfig _googleAuthConfig;
  late final SharedPreferencesOAuthSessionStore _sessionStore;
  late final GoogleOAuthTokenClient _tokenClient;
  late final DriftSyncStateRepository _syncStateRepository;
  late final FolderRepository _folderRepository;
  String? _deviceId;

  @override
  void initState() {
    super.initState();
    _googleAuthConfig = GoogleAuthConfig.fromEnvironment();
    _sessionStore = SharedPreferencesOAuthSessionStore();
    _tokenClient = GoogleOAuthTokenClient();
    _syncStateRepository = DriftSyncStateRepository(widget.database);
    _folderRepository = DriftFolderRepository(widget.database);
    _authController = AuthController(
      authService: GoogleAuthService(
        config: _googleAuthConfig,
        sessionStore: _sessionStore,
        tokenClient: _tokenClient,
      ),
    );
    _syncController = SyncController(
      runManualSync: RunManualSync(
        noteRepository: widget.noteRepository,
        syncGateway: GoogleDriveSyncGateway(
          config: _googleAuthConfig,
          sessionStore: _sessionStore,
          tokenClient: _tokenClient,
        ),
        syncStateRepository: _syncStateRepository,
      ),
    );
    _restoreBootstrapState();
  }

  Future<void> _restoreBootstrapState() async {
    final deviceId = await _syncStateRepository.getOrCreateDeviceId();
    if (!mounted) {
      return;
    }
    setState(() {
      _deviceId = deviceId;
    });
    _authController.restore();
  }

  @override
  void dispose() {
    _authController.dispose();
    _syncController.dispose();
    widget.database.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deviceId = _deviceId;
    if (deviceId == null) {
      return MaterialApp(
        title: 'Proper Notes',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
          useMaterial3: true,
        ),
        home: const Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    return MaterialApp(
      title: 'Proper Notes',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: NotesHomePage(
        createNote: CreateNote(
          repository: widget.noteRepository,
          deviceId: deviceId,
        ),
        createFolder: CreateFolder(repository: _folderRepository),
        deleteFolder: DeleteFolder(repository: _folderRepository),
        renameFolder: RenameFolder(repository: _folderRepository),
        moveNote: MoveNote(
          repository: widget.noteRepository,
          deviceId: deviceId,
        ),
        updateNote: UpdateNote(
          repository: widget.noteRepository,
          deviceId: deviceId,
        ),
        deleteNote: DeleteNote(repository: widget.noteRepository),
        restoreNote: RestoreNote(repository: widget.noteRepository),
        searchNotes: SearchNotes(repository: widget.noteRepository),
        folderRepository: _folderRepository,
        noteRepository: widget.noteRepository,
        authController: _authController,
        syncController: _syncController,
      ),
    );
  }
}
