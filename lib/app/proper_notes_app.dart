import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/services/window_control_service.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/notes/application/create_folder.dart';
import '../features/notes/application/create_note.dart';
import '../features/notes/application/delete_folder.dart';
import '../features/notes/application/delete_note.dart';
import '../features/notes/application/move_note.dart';
import '../features/notes/application/prepare_all_notes_for_sync.dart';
import '../features/notes/application/rename_folder.dart';
import '../features/notes/application/restore_note.dart';
import '../features/notes/application/search_notes.dart';
import '../features/notes/application/update_note.dart';
import '../features/notes/domain/folder_repository.dart';
import '../features/notes/domain/note_repository.dart';
import '../features/notes/presentation/notes_home_page.dart';
import '../features/sync/application/auto_sync_coordinator.dart';
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
  static const Duration _desktopExitSyncTimeout = Duration(seconds: 3);
  late final AuthController _authController;
  late final SyncController _syncController;
  late final AutoSyncCoordinator _autoSyncCoordinator;
  late final GoogleAuthConfig _googleAuthConfig;
  late final SharedPreferencesOAuthSessionStore _sessionStore;
  late final GoogleOAuthTokenClient _tokenClient;
  late final DriftSyncStateRepository _syncStateRepository;
  late final FolderRepository _folderRepository;
  late final AppLifecycleListener _appLifecycleListener;
  final GlobalKey<NotesHomePageState> _homePageKey =
      GlobalKey<NotesHomePageState>();
  final WindowControlService _windowControlService =
      const WindowControlService();
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
    _autoSyncCoordinator = AutoSyncCoordinator(
      noteRepository: widget.noteRepository,
      authController: _authController,
      syncController: _syncController,
    );
    _appLifecycleListener = AppLifecycleListener(
      onResume: () {
        unawaited(_autoSyncCoordinator.syncOnResume());
      },
      onPause: () {
        unawaited(_flushAndSyncOnBackground());
      },
      onExitRequested: _handleExitRequested,
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
    _appLifecycleListener.dispose();
    _autoSyncCoordinator.dispose();
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
        theme: _buildTheme(),
        builder: _wrapWithSystemUiStyle,
        home: const Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    return MaterialApp(
      title: 'Proper Notes',
      theme: _buildTheme(),
      builder: _wrapWithSystemUiStyle,
      home: NotesHomePage(
        key: _homePageKey,
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
        prepareAllNotesForSync: PrepareAllNotesForSync(
          repository: widget.noteRepository,
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
        onLocalChangePersisted: _autoSyncCoordinator.notifyLocalChangePersisted,
      ),
    );
  }

  Future<void> _flushAndSyncOnBackground() async {
    await _homePageKey.currentState?.flushPendingEdits();
    await _autoSyncCoordinator.syncOnBackground();
  }

  Future<ui.AppExitResponse> _handleExitRequested() async {
    final flushedSuccessfully =
        await _homePageKey.currentState?.flushPendingEdits() ?? true;
    if (!flushedSuccessfully) {
      return ui.AppExitResponse.cancel;
    }

    if (!Platform.isLinux) {
      return ui.AppExitResponse.exit;
    }

    if (!_authController.isSignedIn) {
      return ui.AppExitResponse.exit;
    }

    await _windowControlService.hideWindowForExit();
    unawaited(_finishDesktopExitAfterSync());
    return ui.AppExitResponse.cancel;
  }

  Future<void> _finishDesktopExitAfterSync() async {
    await _autoSyncCoordinator.syncBeforeExit(
      timeout: _desktopExitSyncTimeout,
    );
    await ServicesBinding.instance.exitApplication(ui.AppExitType.required);
  }

  Widget _wrapWithSystemUiStyle(BuildContext context, Widget? child) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: child ?? const SizedBox.shrink(),
    );
  }

  ThemeData _buildTheme() {
    const background = Color(0xFFFFFFFF);
    const surface = Color(0xFFFFFFFF);
    const primary = Color(0xFF161616);
    const secondary = Color(0xFF6E6A64);
    final scheme = const ColorScheme.light(
      primary: primary,
      onPrimary: Colors.white,
      secondary: secondary,
      onSecondary: Colors.white,
      surface: surface,
      onSurface: primary,
      error: Color(0xFFB3261E),
      onError: Colors.white,
    ).copyWith(
      surfaceContainerLowest: const Color(0xFFFBFAF8),
      surfaceContainerLow: const Color(0xFFF3F0EB),
      surfaceContainerHighest: const Color(0xFFEAE5DE),
      outlineVariant: const Color(0xFFD9D2C9),
      secondaryContainer: const Color(0xFFEAE6DF),
      onSecondaryContainer: primary,
      primaryContainer: const Color(0xFFEAE6DF),
      onPrimaryContainer: primary,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: primary,
        elevation: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: primary,
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: surface,
        foregroundColor: primary,
        extendedTextStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 22,
          color: primary,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: background,
        showDragHandle: true,
      ),
      dividerColor: const Color(0xFFD9D2C9),
      textTheme: Typography.blackMountainView.copyWith(
        headlineSmall: const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
          color: primary,
        ),
        titleLarge: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
          color: primary,
        ),
        titleMedium: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: primary,
        ),
        bodyLarge: const TextStyle(
          fontSize: 18,
          height: 1.45,
          color: primary,
        ),
        bodyMedium: const TextStyle(
          fontSize: 16,
          height: 1.4,
          color: primary,
        ),
        bodySmall: const TextStyle(
          fontSize: 14,
          height: 1.35,
          color: secondary,
        ),
      ),
    );
  }
}
