import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
import '../infrastructure/auth/webdav_account_store.dart';
import '../infrastructure/auth/webdav_auth_service.dart';
import '../infrastructure/database/app_database.dart';
import '../infrastructure/repositories/drift_folder_repository.dart';
import '../infrastructure/repositories/drift_sync_state_repository.dart';
import '../infrastructure/sync/webdav_sync_gateway.dart';

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
  static const String _themeModePreferenceKey = 'appearance.theme_mode';
  late final AuthController _authController;
  late final SyncController _syncController;
  late final AutoSyncCoordinator _autoSyncCoordinator;
  late final WebDavAccountStore _accountStore;
  late final DriftSyncStateRepository _syncStateRepository;
  late final FolderRepository _folderRepository;
  late final AppLifecycleListener _appLifecycleListener;
  final GlobalKey<NotesHomePageState> _homePageKey =
      GlobalKey<NotesHomePageState>();
  final WindowControlService _windowControlService =
      const WindowControlService();
  String? _deviceId;
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _accountStore = WebDavAccountStore();
    _syncStateRepository = DriftSyncStateRepository(widget.database);
    _folderRepository = DriftFolderRepository(widget.database);
    _authController = AuthController(
      authService: WebDavAuthService(accountStore: _accountStore),
    );
    _syncController = SyncController(
      runManualSync: RunManualSync(
        noteRepository: widget.noteRepository,
        syncGateway: WebDavSyncGateway(accountStore: _accountStore),
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
    unawaited(_restoreThemeMode());
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

  Future<void> _restoreThemeMode() async {
    final preferences = await SharedPreferences.getInstance();
    final restoredThemeMode = _themeModeFromPreference(
        preferences.getString(_themeModePreferenceKey));
    if (!mounted || restoredThemeMode == _themeMode) {
      return;
    }

    setState(() {
      _themeMode = restoredThemeMode;
    });
  }

  Future<void> _setThemeMode(ThemeMode themeMode) async {
    if (_themeMode == themeMode) {
      return;
    }

    setState(() {
      _themeMode = themeMode;
    });

    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _themeModePreferenceKey,
      _themeModeToPreference(themeMode),
    );
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
        theme: _buildLightTheme(),
        darkTheme: _buildDarkTheme(),
        themeMode: _themeMode,
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
      theme: _buildLightTheme(),
      darkTheme: _buildDarkTheme(),
      themeMode: _themeMode,
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
        themeMode: _themeMode,
        onThemeModeChanged: _setThemeMode,
        onLocalChangePersisted: _autoSyncCoordinator.notifyLocalChangePersisted,
        onEditingActivity: _autoSyncCoordinator.notifyEditorActivity,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
      ),
      child: child ?? const SizedBox.shrink(),
    );
  }

  ThemeData _buildLightTheme() {
    const background = Color(0xFFF6F7F4);
    const surface = Color(0xFFFEFEFC);
    const primary = Color(0xFF2F6657);
    const onSurface = Color(0xFF1D2320);
    const secondary = Color(0xFF746B55);
    final scheme = const ColorScheme.light(
      primary: primary,
      onPrimary: Colors.white,
      secondary: secondary,
      onSecondary: Colors.white,
      surface: surface,
      onSurface: onSurface,
      error: Color(0xFFB3261E),
      onError: Colors.white,
    ).copyWith(
      surfaceContainerLowest: const Color(0xFFF1F3EF),
      surfaceContainerLow: const Color(0xFFEAEDE8),
      surfaceContainer: const Color(0xFFE4E8E1),
      surfaceContainerHigh: const Color(0xFFDDE3DB),
      surfaceContainerHighest: const Color(0xFFD5DDD3),
      outline: const Color(0xFF8D998F),
      outlineVariant: const Color(0xFFC9D1C8),
      secondaryContainer: const Color(0xFFE8DFC9),
      onSecondaryContainer: const Color(0xFF2A261C),
      primaryContainer: const Color(0xFFD6EADF),
      onPrimaryContainer: const Color(0xFF10291F),
      tertiary: const Color(0xFF9C5A2E),
      tertiaryContainer: const Color(0xFFFFDCC3),
      onTertiaryContainer: const Color(0xFF321303),
      onSurfaceVariant: const Color(0xFF58625A),
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
        backgroundColor: primary,
        foregroundColor: Colors.white,
        extendedTextStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 16,
          color: Colors.white,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: onSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: Color(0xFF58625A),
        selectedColor: onSurface,
        selectedTileColor: Color(0xFFDCE8E0),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: background,
        showDragHandle: true,
      ),
      dividerColor: const Color(0xFFC9D1C8),
      textTheme: Typography.blackMountainView.copyWith(
        headlineSmall: const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          color: onSurface,
        ),
        titleLarge: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          color: onSurface,
        ),
        titleMedium: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          color: onSurface,
        ),
        bodyLarge: const TextStyle(
          fontSize: 17,
          height: 1.5,
          letterSpacing: 0,
          color: onSurface,
        ),
        bodyMedium: const TextStyle(
          fontSize: 16,
          height: 1.4,
          letterSpacing: 0,
          color: onSurface,
        ),
        bodySmall: const TextStyle(
          fontSize: 14,
          height: 1.35,
          letterSpacing: 0,
          color: secondary,
        ),
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    const background = Color(0xFF111412);
    const surface = Color(0xFF171B18);
    const primary = Color(0xFF8ECDB7);
    const onSurface = Color(0xFFE8EEE9);
    const secondary = Color(0xFFC9BE91);
    final scheme = const ColorScheme.dark(
      primary: primary,
      onPrimary: Color(0xFF0A231A),
      secondary: secondary,
      onSecondary: Color(0xFF2D260D),
      surface: surface,
      onSurface: onSurface,
      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
      errorContainer: Color(0xFF93000A),
      onErrorContainer: Color(0xFFFFDAD6),
      tertiary: Color(0xFFE6A06A),
      tertiaryContainer: Color(0xFF5F3216),
      onTertiaryContainer: Color(0xFFFFDCC3),
    ).copyWith(
      surfaceContainerLowest: const Color(0xFF0B0E0C),
      surfaceContainerLow: const Color(0xFF121713),
      surfaceContainer: const Color(0xFF1D241F),
      surfaceContainerHigh: const Color(0xFF26302A),
      surfaceContainerHighest: const Color(0xFF303B34),
      outline: const Color(0xFF8F9C92),
      outlineVariant: const Color(0xFF3D4840),
      secondaryContainer: const Color(0xFF3B3420),
      onSecondaryContainer: const Color(0xFFEDE4C2),
      primaryContainer: const Color(0xFF1C3C30),
      onPrimaryContainer: const Color(0xFFD8F5E9),
      onSurfaceVariant: const Color(0xFFBAC6BD),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: primary,
        elevation: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFFF5F1EA),
        contentTextStyle: const TextStyle(color: Color(0xFF171614)),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: const Color(0xFF0A231A),
        extendedTextStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 16,
          color: Color(0xFF0A231A),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: onSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: const Color(0xFF1D241F),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: Color(0xFFBAC6BD),
        selectedColor: onSurface,
        selectedTileColor: Color(0xFF1C3C30),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: background,
        showDragHandle: true,
      ),
      dividerColor: const Color(0xFF3D4840),
      textTheme: Typography.whiteMountainView.copyWith(
        headlineSmall: const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          color: onSurface,
        ),
        titleLarge: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          color: onSurface,
        ),
        titleMedium: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          color: onSurface,
        ),
        bodyLarge: const TextStyle(
          fontSize: 17,
          height: 1.5,
          letterSpacing: 0,
          color: onSurface,
        ),
        bodyMedium: const TextStyle(
          fontSize: 16,
          height: 1.4,
          letterSpacing: 0,
          color: onSurface,
        ),
        bodySmall: const TextStyle(
          fontSize: 14,
          height: 1.35,
          letterSpacing: 0,
          color: secondary,
        ),
      ),
    );
  }

  ThemeMode _themeModeFromPreference(String? preference) {
    return switch (preference) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      _ => ThemeMode.system,
    };
  }

  String _themeModeToPreference(ThemeMode themeMode) {
    return switch (themeMode) {
      ThemeMode.dark => 'dark',
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
    };
  }
}
