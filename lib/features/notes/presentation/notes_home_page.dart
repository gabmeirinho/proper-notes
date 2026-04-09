import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/attachments.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/presentation/account_sheet.dart';
import '../../sync/application/sync_controller.dart';
import '../application/create_folder.dart';
import '../application/create_note.dart';
import '../application/delete_folder.dart';
import '../application/delete_note.dart';
import '../application/import_obsidian_vault.dart';
import '../application/move_note.dart';
import '../application/prepare_all_notes_for_sync.dart';
import '../application/rename_folder.dart';
import '../application/restore_note.dart';
import '../application/search_notes.dart';
import '../application/update_note.dart';
import '../domain/folder.dart';
import '../domain/folder_repository.dart';
import '../domain/note.dart';
import '../domain/note_repository.dart';
import '../domain/sync_status.dart';
import 'markdown_preview.dart';
import 'note_editor_page.dart';
import 'note_search_delegate.dart';

class NotesHomePage extends StatefulWidget {
  const NotesHomePage({
    required this.createNote,
    required this.createFolder,
    required this.deleteFolder,
    required this.renameFolder,
    required this.moveNote,
    this.prepareAllNotesForSync,
    required this.updateNote,
    required this.deleteNote,
    required this.restoreNote,
    required this.searchNotes,
    required this.folderRepository,
    required this.noteRepository,
    required this.authController,
    required this.syncController,
    super.key,
  });

  final CreateNote createNote;
  final CreateFolder createFolder;
  final DeleteFolder deleteFolder;
  final RenameFolder renameFolder;
  final MoveNote moveNote;
  final PrepareAllNotesForSync? prepareAllNotesForSync;
  final UpdateNote updateNote;
  final DeleteNote deleteNote;
  final RestoreNote restoreNote;
  final SearchNotes searchNotes;
  final FolderRepository folderRepository;
  final NoteRepository noteRepository;
  final AuthController authController;
  final SyncController syncController;

  @override
  State<NotesHomePage> createState() => _NotesHomePageState();
}

class _NotesHomePageState extends State<NotesHomePage> {
  static const double _desktopBreakpoint = 900;
  static const double _desktopSidebarWidth = 320;
  static const Duration _timedSnackBarDuration = Duration(seconds: 4);
  static const String _conflictCopySuffix = ' (Conflict Copy)';
  static const double _mobileMinTextScale = 0.8;
  static const double _mobileMaxTextScale = 1.2;
  static const double _defaultMobileTextScale = 0.92;
  final GlobalKey<ScaffoldState> _mobileScaffoldKey =
      GlobalKey<ScaffoldState>();

  String? _selectedFolderPath;
  _DesktopEditorSession? _desktopEditorSession;
  _WorkspaceSection _workspaceSection = _WorkspaceSection.notes;
  bool _isDesktopSidebarCollapsed = false;
  int _nextDesktopEditorSessionId = 0;
  int _snackBarSequence = 0;
  Timer? _snackBarDismissTimer;
  Timer? _syncNoticeDismissTimer;
  String? _dismissedSyncNotice;
  String? _lastSeenSyncNotice;
  final Set<String> _expandedFolderPaths = <String>{};
  late final ImportObsidianVault _importObsidianVault;
  double _mobileNoteTextScale = _defaultMobileTextScale;

  @override
  void initState() {
    super.initState();
    _importObsidianVault = ImportObsidianVault(
      ensureFolderExists: widget.folderRepository.ensureFolderExists,
      createNote: ({
        required String title,
        required String content,
        String? folderPath,
      }) async {
        await widget.createNote(
          title: title,
          content: content,
          folderPath: folderPath,
        );
      },
    );
    widget.syncController.addListener(_handleSyncControllerChanged);
  }

  @override
  void dispose() {
    _snackBarDismissTimer?.cancel();
    _syncNoticeDismissTimer?.cancel();
    widget.syncController.removeListener(_handleSyncControllerChanged);
    super.dispose();
  }

  void _handleSyncControllerChanged() {
    final summary = widget.syncController.errorMessage ??
        (widget.syncController.isSyncing
            ? null
            : widget.syncController.lastMessage);

    if (summary == null) {
      _syncNoticeDismissTimer?.cancel();
      _lastSeenSyncNotice = null;
      return;
    }

    if (_lastSeenSyncNotice == summary) {
      return;
    }

    _lastSeenSyncNotice = summary;
    _dismissedSyncNotice = null;
    _syncNoticeDismissTimer?.cancel();

    if (widget.syncController.errorMessage == null) {
      _syncNoticeDismissTimer = Timer(_timedSnackBarDuration, () {
        if (!mounted) {
          return;
        }
        setState(() {
          _dismissedSyncNotice = summary;
        });
      });
    }

    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktopWide =
        MediaQuery.sizeOf(context).width >= _desktopBreakpoint;

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyN, control: true):
            _CreateNoteIntent(),
        SingleActivator(LogicalKeyboardKey.keyN, meta: true):
            _CreateNoteIntent(),
        SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _SearchNotesIntent(),
        SingleActivator(LogicalKeyboardKey.keyF, meta: true):
            _SearchNotesIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _CreateNoteIntent: CallbackAction<_CreateNoteIntent>(
            onInvoke: (_) => _createNote(),
          ),
          _SearchNotesIntent: CallbackAction<_SearchNotesIntent>(
            onInvoke: (_) => _showSearch(),
          ),
        },
        child: Scaffold(
          key: isDesktopWide ? null : _mobileScaffoldKey,
          appBar: null,
          drawer: isDesktopWide ? null : _buildMobileDrawer(),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= _desktopBreakpoint;

              final body = Column(
                children: [
                  if (!isWide) _buildMobileTopBar(),
                  if (isWide) _buildDesktopTopBar(),
                  AnimatedBuilder(
                    animation: widget.syncController,
                    builder: (context, _) {
                      if (widget.syncController.isSyncing) {
                        return const SizedBox.shrink();
                      }

                      final message = widget.syncController.lastMessage;
                      final error = widget.syncController.errorMessage;
                      if (message == null && error == null) {
                        return const SizedBox.shrink();
                      }

                      final isError = error != null;
                      final summary = error ?? message!;
                      if (_dismissedSyncNotice == summary) {
                        return const SizedBox.shrink();
                      }
                      final details = widget.syncController.errorDetails;

                      return Container(
                        width: double.infinity,
                        margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isError
                              ? Theme.of(context).colorScheme.errorContainer
                              : Theme.of(context)
                                  .colorScheme
                                  .secondaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 1),
                              child: Icon(
                                isError
                                    ? Icons.error_outline
                                    : Icons.check_circle_outline,
                                size: 18,
                                color: isError
                                    ? Theme.of(context)
                                        .colorScheme
                                        .onErrorContainer
                                    : Theme.of(context)
                                        .colorScheme
                                        .onSecondaryContainer,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                summary,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: isError
                                          ? Theme.of(context)
                                              .colorScheme
                                              .onErrorContainer
                                          : Theme.of(context)
                                              .colorScheme
                                              .onSecondaryContainer,
                                    ),
                              ),
                            ),
                            if (isError &&
                                details != null &&
                                details != summary) ...[
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: () => _showSyncErrorDetails(
                                  context: context,
                                  summary: summary,
                                  details: details,
                                ),
                                child: const Text('Details'),
                              ),
                            ],
                            IconButton(
                              onPressed: () {
                                _syncNoticeDismissTimer?.cancel();
                                setState(() {
                                  _dismissedSyncNotice = summary;
                                });
                              },
                              tooltip: 'Dismiss sync notice',
                              icon: const Icon(Icons.close, size: 18),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  Expanded(
                    child: isWide
                        ? _buildDesktopWorkspace()
                        : _buildMobileContent(),
                  ),
                ],
              );

              return body;
            },
          ),
          floatingActionButton: _showNewNoteButton
              ? FloatingActionButton.extended(
                  onPressed: _createNote,
                  icon: const Icon(Icons.add),
                  label: const Text('New note'),
                )
              : null,
        ),
      ),
    );
  }

  Future<void> _showSyncErrorDetails({
    required BuildContext context,
    required String summary,
    required String details,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sync details',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  summary,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      details,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMobileTopBar() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Row(
          children: [
            IconButton(
              onPressed: () => _mobileScaffoldKey.currentState?.openDrawer(),
              tooltip: 'Folders',
              icon: const Icon(Icons.menu_rounded),
            ),
            const Spacer(),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: _showSearch,
                  tooltip: 'Search',
                  icon: const Icon(Icons.search_rounded),
                ),
                PopupMenuButton<_MobileAppMenuAction>(
                  tooltip: 'More app actions',
                  onSelected: (action) async {
                    switch (action) {
                      case _MobileAppMenuAction.sync:
                        await _runSync();
                      case _MobileAppMenuAction.forceReuploadAllNotes:
                        await _forceReuploadAllNotes();
                      case _MobileAppMenuAction.account:
                        await _showAccountSheet();
                      case _MobileAppMenuAction.noteTextSize:
                        await _showMobileTextSizeSheet();
                      case _MobileAppMenuAction.importObsidianNotes:
                        await _importObsidianNotes();
                      case _MobileAppMenuAction.showAttachmentsFolder:
                        await _showAttachmentsFolder();
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: _MobileAppMenuAction.sync,
                      child: Text('Sync now'),
                    ),
                    PopupMenuItem(
                      value: _MobileAppMenuAction.forceReuploadAllNotes,
                      child: Text('Force re-upload all notes'),
                    ),
                    PopupMenuItem(
                      value: _MobileAppMenuAction.account,
                      child: Text('Account'),
                    ),
                    PopupMenuItem(
                      value: _MobileAppMenuAction.noteTextSize,
                      child: Text('Note text size'),
                    ),
                    PopupMenuItem(
                      value: _MobileAppMenuAction.importObsidianNotes,
                      child: Text('Import Obsidian notes'),
                    ),
                    PopupMenuItem(
                      value: _MobileAppMenuAction.showAttachmentsFolder,
                      child: Text('Show attachments folder'),
                    ),
                  ],
                  icon: const Icon(Icons.more_vert_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopTopBar() {
    return Padding(
      key: const ValueKey('desktop-top-bar'),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        children: [
          _MobileChromeSurface(
            child: IconButton(
              onPressed: _toggleDesktopSidebar,
              tooltip: _isDesktopSidebarCollapsed
                  ? 'Expand sidebar'
                  : 'Collapse sidebar',
              icon: Icon(
                _isDesktopSidebarCollapsed
                    ? Icons.view_sidebar_outlined
                    : Icons.view_sidebar,
                size: 18,
              ),
            ),
          ),
          const Spacer(),
          _MobileChromeSurface(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: _showSearch,
                  tooltip: 'Search',
                  icon: const Icon(Icons.search, size: 18),
                ),
                _buildSyncButton(iconSize: 18),
                _buildAccountButton(iconSize: 18),
                _buildTopBarActionsMenu(iconSize: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _toggleDesktopSidebar() {
    setState(() {
      _isDesktopSidebarCollapsed = !_isDesktopSidebarCollapsed;
    });
  }

  Widget _buildAccountButton({double iconSize = 24}) {
    return AnimatedBuilder(
      animation: widget.authController,
      builder: (context, _) {
        final isCheckingAccount =
            !widget.authController.hasResolvedInitialSession &&
                widget.authController.isBusy;
        final isSignedIn = widget.authController.isSignedIn;
        return IconButton(
          onPressed: _showAccountSheet,
          tooltip: isCheckingAccount
              ? 'Checking account'
              : (isSignedIn ? 'Account' : 'Sign in'),
          icon: Icon(
            isSignedIn ? Icons.account_circle : Icons.account_circle_outlined,
            size: iconSize,
          ),
        );
      },
    );
  }

  Widget _buildSyncButton({double iconSize = 24}) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.authController,
        widget.syncController,
      ]),
      builder: (context, _) {
        final isCheckingAccount =
            !widget.authController.hasResolvedInitialSession &&
                widget.authController.isBusy;
        final syncReady = widget.authController.isSignedIn;
        return IconButton(
          onPressed:
              widget.syncController.isSyncing || isCheckingAccount || !syncReady
                  ? null
                  : _runSync,
          tooltip: isCheckingAccount
              ? 'Checking account'
              : (syncReady ? 'Sync' : 'Sign in to sync'),
          icon: widget.syncController.isSyncing
              ? SizedBox(
                  width: iconSize,
                  height: iconSize,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Icons.sync, size: iconSize),
        );
      },
    );
  }

  Widget _buildTopBarActionsMenu({double iconSize = 24}) {
    return PopupMenuButton<_TopBarMenuAction>(
      tooltip: 'More app actions',
      icon: Icon(Icons.more_vert, size: iconSize),
      onSelected: (action) async {
        switch (action) {
          case _TopBarMenuAction.forceReuploadAllNotes:
            await _forceReuploadAllNotes();
          case _TopBarMenuAction.importObsidianNotes:
            await _importObsidianNotes();
          case _TopBarMenuAction.showAttachmentsFolder:
            await _showAttachmentsFolder();
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _TopBarMenuAction.forceReuploadAllNotes,
          child: Text('Force re-upload all notes'),
        ),
        PopupMenuItem(
          value: _TopBarMenuAction.importObsidianNotes,
          child: Text('Import Obsidian notes'),
        ),
        PopupMenuItem(
          value: _TopBarMenuAction.showAttachmentsFolder,
          child: Text('Show attachments folder'),
        ),
      ],
    );
  }

  Future<void> _createNote() async {
    if (_workspaceSection == _WorkspaceSection.notes) {
      setState(() {
        _workspaceSection = _WorkspaceSection.notes;
        _desktopEditorSession = _DesktopEditorSession(
          sessionId: _nextDesktopEditorSessionId++,
          initialFolderPath: _selectedFolderPath,
        );
      });
      return;
    }
  }

  Future<void> _showSearch() async {
    final selectedNote = await showSearch<Note?>(
      context: context,
      delegate: NoteSearchDelegate(
        searchNotes: (query) =>
            widget.searchNotes(query, folderPath: _selectedFolderPath),
      ),
    );

    if (!mounted || selectedNote == null) {
      return;
    }

    await _openEditor(selectedNote);
  }

  Future<void> _showAccountSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return AccountSheet(
          authController: widget.authController,
        );
      },
    );

    if (!mounted) {
      return;
    }

    final error = widget.authController.errorMessage;
    if (error != null) {
      _showTimedSnackBar(error);
    }
  }

  Future<void> _runSync() async {
    final result = await widget.syncController.syncNow();
    if (!mounted || result == null) {
      final error = widget.syncController.errorMessage;
      if (error != null) {
        _showTimedSnackBar(error);
      }
      return;
    }

    if (!widget.authController.isSignedIn) {
      await widget.authController.restore();
    }
  }

  Future<void> _restoreConflictCopy(Note note) async {
    await _openEditor(note);
  }

  Future<void> _resolveConflict(Note conflictNote) async {
    final baseTitle = _baseTitleForConflict(conflictNote.title);
    final activeNotes = await widget.noteRepository.getActiveNotesForSync();
    final candidates = activeNotes
        .where(
          (note) =>
              note.id != conflictNote.id &&
              note.syncStatus != SyncStatus.conflicted &&
              note.title.trim() == baseTitle &&
              note.folderPath == conflictNote.folderPath,
        )
        .toList(growable: false);
    final originalNote = candidates.length == 1 ? candidates.single : null;

    if (!mounted) {
      return;
    }

    final action = await showModalBottomSheet<_ConflictResolutionAction>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return _ConflictResolutionSheet(
          conflictNote: conflictNote,
          originalNote: originalNote,
          baseTitle: baseTitle,
        );
      },
    );

    if (!mounted || action == null) {
      return;
    }

    switch (action) {
      case _ConflictResolutionAction.openConflictCopy:
        await _openEditor(conflictNote);
      case _ConflictResolutionAction.openOriginal:
        if (originalNote != null) {
          await _openEditor(originalNote);
        }
      case _ConflictResolutionAction.keepOriginal:
        await _keepOriginalVersion(conflictNote);
      case _ConflictResolutionAction.keepConflictCopy:
        await _keepConflictVersion(
          conflictNote,
          originalNote: originalNote,
          baseTitle: baseTitle,
        );
    }
  }

  Future<void> _keepOriginalVersion(Note conflictNote) async {
    await widget.deleteNote(conflictNote.id);
    if (!mounted) {
      return;
    }
    _showTimedSnackBar('Conflict copy deleted. Original note kept.');
  }

  Future<void> _keepConflictVersion(
    Note conflictNote, {
    required Note? originalNote,
    required String baseTitle,
  }) async {
    if (originalNote != null) {
      await widget.deleteNote(originalNote.id);
    }

    final resolvedNote = await widget.updateNote(
      original: conflictNote,
      title: baseTitle,
      content: conflictNote.content,
      folderPath: conflictNote.folderPath,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      if (_desktopEditorSession?.note?.id == conflictNote.id) {
        _desktopEditorSession = _desktopEditorSession!.copyWith(
          note: resolvedNote,
        );
      }
    });

    _showTimedSnackBar(
      originalNote == null
          ? 'Conflict copy converted to a normal note.'
          : 'Conflict copy kept. Original note moved to trash.',
    );
  }

  String _baseTitleForConflict(String title) {
    if (!title.endsWith(_conflictCopySuffix)) {
      return title.trim();
    }

    return title.substring(0, title.length - _conflictCopySuffix.length).trim();
  }

  Future<void> _openEditor(Note note) async {
    if (_workspaceSection == _WorkspaceSection.notes) {
      setState(() {
        _workspaceSection = _WorkspaceSection.notes;
        _selectedFolderPath = _normalizeFolderPath(note.folderPath);
        _expandFolderAncestors(note.folderPath);
        _desktopEditorSession = _DesktopEditorSession(
          sessionId: _nextDesktopEditorSessionId++,
          note: note,
        );
      });
      return;
    }
  }

  Future<void> _importObsidianNotes() async {
    String? selectedDirectoryPath;
    try {
      selectedDirectoryPath = await getDirectoryPath(
        confirmButtonText: 'Import',
      );
    } catch (_) {
      if (mounted) {
        _showTimedSnackBar('Could not open the folder picker.');
      }
      return;
    }

    if (selectedDirectoryPath == null) {
      return;
    }

    ObsidianImportResult result;
    try {
      result = await _importObsidianVault(vaultPath: selectedDirectoryPath);
    } catch (_) {
      if (mounted) {
        _showTimedSnackBar('Could not import the selected Obsidian folder.');
      }
      return;
    }
    if (!mounted) {
      return;
    }

    if (result.importedNoteCount == 0) {
      _showTimedSnackBar('No Obsidian markdown notes were found to import.');
      return;
    }

    final summary = result.hasFailures
        ? 'Imported ${result.importedNoteCount} Obsidian notes. Skipped ${result.failedFileCount} files.'
        : 'Imported ${result.importedNoteCount} Obsidian notes.';
    _showTimedSnackBar(summary);
  }

  Future<void> _forceReuploadAllNotes() async {
    final prepareAllNotesForSync = widget.prepareAllNotesForSync ??
        PrepareAllNotesForSync(
          repository: widget.noteRepository,
        );
    final preparedCount = await prepareAllNotesForSync();
    if (!mounted) {
      return;
    }

    final prepLabel = preparedCount == 1
        ? 'Prepared 1 note for sync.'
        : 'Prepared $preparedCount notes for sync.';
    _showTimedSnackBar(prepLabel);
    await _runSync();
  }

  Future<void> _showMobileTextSizeSheet() async {
    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final percent = (_mobileNoteTextScale * 100).round();

            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Note text size',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$percent%',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Slider(
                    value: _mobileNoteTextScale,
                    min: _mobileMinTextScale,
                    max: _mobileMaxTextScale,
                    divisions: 8,
                    label: '$percent%',
                    onChanged: (value) {
                      setState(() {
                        _mobileNoteTextScale = value;
                      });
                      setModalState(() {});
                    },
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        setState(() {
                          _mobileNoteTextScale = _defaultMobileTextScale;
                        });
                        setModalState(() {});
                      },
                      child: const Text('Reset'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showAttachmentsFolder() async {
    final directory = await getAttachmentsDirectory();
    var opened = false;

    try {
      opened = await launchUrl(
        Uri.directory(directory.path),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }

    if (!opened && !kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
      try {
        final result = await Process.run('xdg-open', <String>[directory.path]);
        opened = result.exitCode == 0;
      } catch (_) {
        opened = false;
      }
    }

    if (!mounted || opened) {
      return;
    }

    _showTimedSnackBar(
      'Could not open attachments folder: ${directory.path}',
    );
  }

  Future<void> _delete(Note note) async {
    await widget.deleteNote(note.id);
    if (!mounted) {
      return;
    }

    _showTimedSnackBar(
      note.title.isEmpty ? 'Note deleted' : '"${note.title}" deleted',
      actionLabel: 'Undo',
      onAction: () {
        widget.restoreNote(note.id);
      },
    );
  }

  Future<void> _restore(Note note) async {
    await widget.restoreNote(note.id);
    if (!mounted) {
      return;
    }

    _showTimedSnackBar(
      note.title.isEmpty ? 'Note restored' : '"${note.title}" restored',
    );
  }

  Future<void> _moveNote(Note note) async {
    if (!_isDesktopWideLayout) {
      final destination = await _showMoveNoteSheet(note);
      if (destination == null) {
        return;
      }
      await _moveNoteToFolderPath(
          note, destination.isEmpty ? null : destination);
      return;
    }

    final destination = await _showTextEntryDialog(
      title: 'Move note',
      labelText: 'Folder path',
      hintText: 'Leave empty for root',
      actionLabel: 'Move',
      initialValue: note.folderPath ?? '',
    );

    if (destination == null) {
      return;
    }

    await _moveNoteToFolderPath(note, destination);
  }

  Future<String?> _showMoveNoteSheet(Note note) async {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: 420,
            child: _MoveNoteFolderSheet(
              foldersStream: widget.folderRepository.watchFolders(),
              currentFolderPath: note.folderPath,
            ),
          ),
        );
      },
    );
  }

  Future<void> _renameFolder(Folder folder) async {
    final renamedName = await _showTextEntryDialog(
      title: 'Rename folder',
      labelText: 'Folder name',
      hintText: 'Renamed folder',
      actionLabel: 'Rename',
      initialValue: folder.name,
    );

    if (renamedName == null) {
      return;
    }

    final normalizedName = _normalizeFolderName(renamedName);
    if (normalizedName == null) {
      _showTimedSnackBar('Folder name cannot be empty');
      return;
    }

    await _applyFolderPathChange(
      folder: folder,
      newPath: _joinFolderPath(folder.parentPath, normalizedName),
      successMessage:
          'Renamed folder to "${_joinFolderPath(folder.parentPath, normalizedName)}"',
    );
  }

  Future<void> _moveFolder(Folder folder) async {
    final destinationPath = await _showTextEntryDialog(
      title: 'Move folder',
      labelText: 'Folder path',
      hintText: 'Archive/Projects',
      actionLabel: 'Move',
      initialValue: folder.path,
    );

    if (destinationPath == null) {
      return;
    }

    final newPath = _normalizeFolderPath(destinationPath);
    if (newPath == null) {
      _showTimedSnackBar('Folder path cannot be empty');
      return;
    }

    final resolvedPath = await _resolveFolderMoveDestination(
      folder: folder,
      destinationPath: newPath,
    );

    await _applyFolderPathChange(
      folder: folder,
      newPath: resolvedPath,
      successMessage: 'Moved folder to "$resolvedPath"',
    );
  }

  Future<String> _resolveFolderMoveDestination({
    required Folder folder,
    required String destinationPath,
  }) async {
    final existingFolders = await widget.folderRepository.watchFolders().first;
    final matchesExistingFolder = existingFolders.any(
      (existingFolder) => existingFolder.path == destinationPath,
    );

    if (matchesExistingFolder && destinationPath != folder.path) {
      return _joinFolderPath(destinationPath, folder.name);
    }

    return destinationPath;
  }

  Future<bool> _applyFolderPathChange({
    required Folder folder,
    required String newPath,
    required String successMessage,
  }) async {
    if (folder.path == newPath) {
      _showTimedSnackBar('Folder is already at "$newPath"');
      return false;
    }

    late final RenameFolderResult result;
    try {
      result = await widget.renameFolder(folder.path, newPath);
    } catch (error) {
      if (mounted) {
        _showTimedSnackBar(
          'Move failed from "${folder.path}" to "$newPath": $error',
        );
      }
      return false;
    }

    if (!mounted) {
      return false;
    }

    switch (result) {
      case RenameFolderResult.renamed:
        setState(() {
          _workspaceSection = _WorkspaceSection.notes;
          _selectedFolderPath = newPath;
          _replaceFolderState(folder.path, newPath);
        });
        _showTimedSnackBar(successMessage);
        return true;
      case RenameFolderResult.notFound:
        _showTimedSnackBar(
          'Move failed: "${folder.path}" no longer exists',
        );
        return false;
      case RenameFolderResult.invalidDestination:
        _showTimedSnackBar(
          'Move failed: "$newPath" is not a valid destination for "${folder.path}"',
        );
        return false;
      case RenameFolderResult.destinationExists:
        _showTimedSnackBar(
          'Move failed: a folder already exists at "$newPath"',
        );
        return false;
    }
  }

  Future<void> _moveFolderToParentPath(
      Folder folder, String? parentPath) async {
    final nextPath = _joinFolderPath(parentPath, folder.name);
    if (nextPath == folder.path) {
      return;
    }

    await _applyFolderPathChange(
      folder: folder,
      newPath: nextPath,
      successMessage: parentPath == null
          ? 'Moved folder "${folder.name}" to root'
          : 'Moved folder to "$nextPath"',
    );
  }

  Future<void> _moveNoteToFolderPath(Note note, String? folderPath) async {
    final normalizedPath = _normalizeFolderPath(folderPath);
    if (normalizedPath == note.folderPath) {
      return;
    }

    final moved = await widget.moveNote(
      original: note,
      folderPath: normalizedPath,
    );
    if (!mounted) {
      return;
    }

    setState(() {
      if (_desktopEditorSession?.note?.id == note.id) {
        _desktopEditorSession = _desktopEditorSession!.copyWith(note: moved);
      }
      _expandFolderAncestors(normalizedPath);
    });
    _showTimedSnackBar(
      normalizedPath == null
          ? 'Moved note to All notes'
          : 'Moved note to "$normalizedPath"',
    );
  }

  void _replaceFolderState(String oldPath, String newPath) {
    String remap(String path) =>
        path == oldPath ? newPath : '$newPath${path.substring(oldPath.length)}';

    if (_selectedFolderPath == oldPath ||
        (_selectedFolderPath != null &&
            _selectedFolderPath!.startsWith('$oldPath/'))) {
      _selectedFolderPath = remap(_selectedFolderPath!);
    }

    final openNote = _desktopEditorSession?.note;
    if (openNote != null &&
        openNote.folderPath != null &&
        (openNote.folderPath == oldPath ||
            openNote.folderPath!.startsWith('$oldPath/'))) {
      _desktopEditorSession = _desktopEditorSession!.copyWith(
        note: openNote.copyWith(folderPath: remap(openNote.folderPath!)),
      );
    }

    final remappedExpanded = _expandedFolderPaths.map((path) {
      if (path == oldPath || path.startsWith('$oldPath/')) {
        return remap(path);
      }
      return path;
    }).toSet();
    _expandedFolderPaths
      ..clear()
      ..addAll(remappedExpanded);
    _expandFolderAncestors(newPath);
  }

  Future<void> _deleteFolder(Folder folder) async {
    final deleteImpact = await widget.deleteFolder.getDeleteImpact(folder.path);
    if (!mounted || deleteImpact == null) {
      _showTimedSnackBar('Folder no longer exists');
      return;
    }

    final shouldDelete = deleteImpact.isEmpty ||
        await _confirmFolderDeletion(folder, deleteImpact);
    if (!mounted || !shouldDelete) {
      return;
    }

    final result = await widget.deleteFolder(
      folder.path,
      recursive: !deleteImpact.isEmpty,
    );
    if (!mounted) {
      return;
    }

    switch (result) {
      case DeleteFolderResult.deleted:
        setState(() {
          _expandedFolderPaths.removeWhere(
            (path) => path == folder.path || path.startsWith('${folder.path}/'),
          );
          final openNoteFolderPath = _desktopEditorSession?.note?.folderPath;
          if (openNoteFolderPath == folder.path ||
              (openNoteFolderPath != null &&
                  openNoteFolderPath.startsWith('${folder.path}/'))) {
            _desktopEditorSession = null;
          }
        });
        if (_selectedFolderPath == folder.path ||
            (_selectedFolderPath != null &&
                _selectedFolderPath!.startsWith('${folder.path}/'))) {
          _selectFolder(folder.parentPath);
        }
        _showTimedSnackBar('Deleted folder "${folder.name}"');
      case DeleteFolderResult.notFound:
        _showTimedSnackBar('Folder no longer exists');
    }
  }

  Future<bool> _confirmFolderDeletion(
    Folder folder,
    FolderDeleteImpact impact,
  ) async {
    final folderLabel = impact.childFolderCount == 1 ? 'folder' : 'folders';
    final noteLabel = impact.noteCount == 1 ? 'note' : 'notes';
    final impactSummary = <String>[
      if (impact.childFolderCount > 0)
        '${impact.childFolderCount} nested $folderLabel',
      if (impact.noteCount > 0) '${impact.noteCount} $noteLabel',
    ].join(' and ');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete folder?'),
          content: Text(
            'Delete "${folder.name}" and its contents? This will move $impactSummary to deletion too.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );

    return confirmed ?? false;
  }

  void _showTimedSnackBar(
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final snackBarSequence = ++_snackBarSequence;
    _snackBarDismissTimer?.cancel();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: _timedSnackBarDuration,
        behavior: SnackBarBehavior.floating,
        action: actionLabel == null
            ? null
            : SnackBarAction(
                label: actionLabel,
                onPressed: onAction ?? () {},
              ),
      ),
    );

    _snackBarDismissTimer = Timer(_timedSnackBarDuration, () {
      if (!mounted) {
        return;
      }

      if (_snackBarSequence == snackBarSequence) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }
    });
  }

  Future<T?> _showPopupMenu<T>({
    required Offset position,
    required List<PopupMenuEntry<T>> items,
  }) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    return showMenu<T>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(position, position),
        Offset.zero & overlay.size,
      ),
      items: items,
    );
  }

  Future<void> _showDesktopRootMenu(Offset position) async {
    final action = await _showPopupMenu<_RootSidebarMenuAction>(
      position: position,
      items: const [
        PopupMenuItem(
          value: _RootSidebarMenuAction.createNote,
          child: Text('New note'),
        ),
        PopupMenuItem(
          value: _RootSidebarMenuAction.createFolder,
          child: Text('New folder'),
        ),
      ],
    );

    if (!mounted || action == null) {
      return;
    }

    switch (action) {
      case _RootSidebarMenuAction.createNote:
        _selectFolder(null);
        await _createNote();
      case _RootSidebarMenuAction.createFolder:
        await _showCreateFolderDialog();
    }
  }

  Future<void> _showActiveNoteMenu(Note note, Offset position) async {
    final action = await _showPopupMenu<_NoteMenuAction>(
      position: position,
      items: [
        const PopupMenuItem(
          value: _NoteMenuAction.open,
          child: Text('Open'),
        ),
        if (note.syncStatus == SyncStatus.conflicted)
          const PopupMenuItem(
            value: _NoteMenuAction.resolveConflict,
            child: Text('Resolve conflict'),
          ),
        const PopupMenuItem(
          value: _NoteMenuAction.move,
          child: Text('Move'),
        ),
        const PopupMenuItem(
          value: _NoteMenuAction.delete,
          child: Text('Delete'),
        ),
      ],
    );

    if (!mounted || action == null) {
      return;
    }

    switch (action) {
      case _NoteMenuAction.open:
        if (note.syncStatus == SyncStatus.conflicted) {
          await _restoreConflictCopy(note);
        } else {
          await _openEditor(note);
        }
      case _NoteMenuAction.resolveConflict:
        await _resolveConflict(note);
      case _NoteMenuAction.move:
        await _moveNote(note);
      case _NoteMenuAction.delete:
        await _delete(note);
      case _NoteMenuAction.restore:
        break;
    }
  }

  Future<void> _showDeletedNoteMenu(Note note, Offset position) async {
    final action = await _showPopupMenu<_NoteMenuAction>(
      position: position,
      items: const [
        PopupMenuItem(
          value: _NoteMenuAction.restore,
          child: Text('Restore'),
        ),
      ],
    );

    if (!mounted || action == null) {
      return;
    }

    switch (action) {
      case _NoteMenuAction.restore:
        await _restore(note);
      case _NoteMenuAction.open:
      case _NoteMenuAction.resolveConflict:
      case _NoteMenuAction.move:
      case _NoteMenuAction.delete:
        break;
    }
  }

  Future<void> _handleActiveNoteAction(
    Note note,
    _NoteMenuAction action,
  ) async {
    switch (action) {
      case _NoteMenuAction.open:
        if (note.syncStatus == SyncStatus.conflicted) {
          await _restoreConflictCopy(note);
        } else {
          await _openEditor(note);
        }
      case _NoteMenuAction.resolveConflict:
        await _resolveConflict(note);
      case _NoteMenuAction.move:
        await _moveNote(note);
      case _NoteMenuAction.delete:
        await _delete(note);
      case _NoteMenuAction.restore:
        break;
    }
  }

  Future<void> _showMobileNoteActions(Note note) async {
    final action = await showModalBottomSheet<_NoteMenuAction>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return _MobileNoteActionsSheet(
          note: note,
          showMoveAction: _workspaceSection == _WorkspaceSection.notes,
          showResolveConflictAction: note.syncStatus == SyncStatus.conflicted,
        );
      },
    );

    if (!mounted || action == null) {
      return;
    }

    await _handleActiveNoteAction(note, action);
  }

  Widget _buildContent() {
    return _workspaceSection == _WorkspaceSection.trash
        ? _buildTrashList()
        : _buildNotesList();
  }

  Widget _buildMobileContent() {
    if (_workspaceSection == _WorkspaceSection.trash) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: _buildTrashList(),
      );
    }

    return _buildDesktopEditorPane();
  }

  Widget _buildNotesList() {
    final isDesktopWide = _isDesktopWideLayout;

    return _NotesList(
      stream: widget.noteRepository.watchActiveNotes(
        folderPath: _selectedFolderPath,
      ),
      mobileLayout: !isDesktopWide,
      emptyState: _selectedFolderPath == null
          ? 'No notes yet. Create your first note.'
          : 'No notes in this folder yet.',
      onTap: _openEditor,
      onRestoreConflictCopy: _restoreConflictCopy,
      onShowContextMenu: isDesktopWide
          ? _showActiveNoteMenu
          : (note, _) => _showMobileNoteActions(note),
      trailingBuilder: (context, note) {
        if (!isDesktopWide) {
          return IconButton(
            tooltip: 'Note actions',
            icon: const Icon(Icons.more_vert),
            onPressed: () => _showMobileNoteActions(note),
          );
        }

        return PopupMenuButton<_NoteMenuAction>(
          tooltip: 'Note actions',
          onSelected: (action) => _handleActiveNoteAction(note, action),
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: _NoteMenuAction.open,
              child: Text('Open'),
            ),
            if (note.syncStatus == SyncStatus.conflicted)
              const PopupMenuItem(
                value: _NoteMenuAction.resolveConflict,
                child: Text('Resolve conflict'),
              ),
            const PopupMenuItem(
              value: _NoteMenuAction.move,
              child: Text('Move'),
            ),
            const PopupMenuItem(
              value: _NoteMenuAction.delete,
              child: Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTrashList() {
    return _NotesList(
      stream: widget.noteRepository.watchDeletedNotes(
        folderPath: _selectedFolderPath,
      ),
      mobileLayout: !_isDesktopWideLayout,
      emptyState: _selectedFolderPath == null
          ? 'Trash is empty.'
          : 'No deleted notes in this folder.',
      onTap: (_) async {},
      onRestoreConflictCopy: _restoreConflictCopy,
      onShowContextMenu: _showDeletedNoteMenu,
      trailingBuilder: (context, note) {
        return IconButton(
          tooltip: 'Restore',
          icon: const Icon(Icons.restore),
          onPressed: () => _restore(note),
        );
      },
    );
  }

  bool get _showNewNoteButton =>
      _workspaceSection == _WorkspaceSection.notes &&
      _desktopEditorSession == null;

  Future<void> _showFoldersSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: 420,
            child: _FolderSidebar(
              stream: widget.folderRepository.watchFolders(),
              selectedFolderPath: _selectedFolderPath,
              selectedSection: _workspaceSection,
              onSelectFolder: (path) {
                _selectFolder(path);
                Navigator.of(context).pop();
              },
              onSelectSection: (section) {
                _selectWorkspaceSection(section);
                Navigator.of(context).pop();
              },
              onShowRootMenu: _showDesktopRootMenu,
              onCreateNoteInFolder: (path) async {
                Navigator.of(context).pop();
                _selectFolder(path);
                await _createNote();
              },
              onDeleteFolder: (folder) async {
                Navigator.of(context).pop();
                await _deleteFolder(folder);
              },
              onCreateFolder: (parentPath) async {
                Navigator.of(context).pop();
                await _showCreateFolderDialog(parentPath);
              },
              onRenameFolder: (folder) async {
                Navigator.of(context).pop();
                await _renameFolder(folder);
              },
              onMoveFolder: (folder) async {
                Navigator.of(context).pop();
                await _moveFolder(folder);
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildMobileDrawer() {
    return Drawer(
      child: SafeArea(
        child: _MobileSidebarTree(
          foldersStream: widget.folderRepository.watchFolders(),
          notesStream: widget.noteRepository.watchActiveNotes(),
          selectedFolderPath: _selectedFolderPath,
          selectedNoteId: _desktopEditorSession?.note?.id,
          selectedSection: _workspaceSection,
          expandedFolderPaths: _expandedFolderPaths,
          onSelectFolder: (path) {
            _selectFolder(path);
          },
          onSelectSection: (section) {
            Navigator.of(context).pop();
            _selectWorkspaceSection(section);
          },
          onToggleFolderExpansion: _toggleFolderExpansion,
          onOpenNote: (note) async {
            Navigator.of(context).pop();
            await _openEditor(note);
          },
          onShowNoteMenu: (note, _) => _showMobileNoteActions(note),
          onShowRootMenu: _showDesktopRootMenu,
          onCreateNoteInFolder: (path) async {
            Navigator.of(context).pop();
            _selectFolder(path);
            await _createNote();
          },
          onDeleteFolder: (folder) async {
            Navigator.of(context).pop();
            await _deleteFolder(folder);
          },
          onCreateFolder: (parentPath) async {
            Navigator.of(context).pop();
            await _showCreateFolderDialog(parentPath);
          },
          onRenameFolder: (folder) async {
            Navigator.of(context).pop();
            await _renameFolder(folder);
          },
          onMoveFolder: (folder) async {
            Navigator.of(context).pop();
            await _moveFolder(folder);
          },
        ),
      ),
    );
  }

  Future<void> _showCreateFolderDialog([String? parentPath]) async {
    final created = await _showTextEntryDialog(
      title: 'New folder',
      labelText: 'Folder path',
      hintText: 'Projects/Proper Notes',
      actionLabel: 'Create',
      initialValue: parentPath == null ? '' : '$parentPath/',
    );

    final normalizedPath = _normalizeFolderPath(created);
    if (normalizedPath == null) {
      return;
    }

    await widget.createFolder(normalizedPath);
    if (!mounted) {
      return;
    }
    _selectFolder(normalizedPath);
  }

  void _selectFolder(String? path) {
    final normalizedPath = _normalizeFolderPath(path);
    setState(() {
      _workspaceSection = _WorkspaceSection.notes;
      _selectedFolderPath = normalizedPath;
      _expandFolderAncestors(normalizedPath);
    });
  }

  void _selectWorkspaceSection(_WorkspaceSection section) {
    setState(() {
      _workspaceSection = section;
      if (section == _WorkspaceSection.trash) {
        _selectedFolderPath = null;
        _desktopEditorSession = null;
      }
    });
  }

  void _toggleFolderExpansion(String path) {
    setState(() {
      if (_expandedFolderPaths.contains(path)) {
        _expandedFolderPaths.remove(path);
      } else {
        _expandedFolderPaths.add(path);
        _expandFolderAncestors(path);
      }
    });
  }

  void _expandFolderAncestors(String? path) {
    final normalizedPath = _normalizeFolderPath(path);
    if (normalizedPath == null) {
      return;
    }

    final segments = normalizedPath.split('/');
    var current = '';
    for (final segment in segments) {
      current = current.isEmpty ? segment : '$current/$segment';
      _expandedFolderPaths.add(current);
    }
  }

  String? _normalizeFolderPath(String? rawPath) {
    if (rawPath == null) {
      return null;
    }

    final segments = rawPath
        .split('/')
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);

    if (segments.isEmpty) {
      return null;
    }

    return segments.join('/');
  }

  String? _normalizeFolderName(String? rawName) {
    final normalized = _normalizeFolderPath(rawName);
    if (normalized == null || normalized.contains('/')) {
      return null;
    }
    return normalized;
  }

  String _joinFolderPath(String? parentPath, String name) {
    final normalizedName = _normalizeFolderName(name) ?? name;
    return parentPath == null ? normalizedName : '$parentPath/$normalizedName';
  }

  Future<String?> _showTextEntryDialog({
    required String title,
    required String labelText,
    required String hintText,
    required String actionLabel,
    required String initialValue,
  }) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return _TextEntryDialog(
          title: title,
          labelText: labelText,
          hintText: hintText,
          actionLabel: actionLabel,
          initialValue: initialValue,
        );
      },
    );
  }

  bool get _isDesktopWideLayout =>
      MediaQuery.sizeOf(context).width >= _desktopBreakpoint;

  Widget _buildDesktopWorkspace() {
    return Row(
      key: const ValueKey('desktop-workspace'),
      children: [
        if (!_isDesktopSidebarCollapsed) ...[
          SizedBox(
            width: _desktopSidebarWidth,
            child: _DesktopSidebarTree(
              foldersStream: widget.folderRepository.watchFolders(),
              notesStream: widget.noteRepository.watchActiveNotes(),
              selectedFolderPath: _selectedFolderPath,
              selectedNoteId: _desktopEditorSession?.note?.id,
              selectedSection: _workspaceSection,
              expandedFolderPaths: _expandedFolderPaths,
              onSelectFolder: _selectFolder,
              onSelectSection: _selectWorkspaceSection,
              onToggleFolderExpansion: _toggleFolderExpansion,
              onOpenNote: _openEditor,
              onShowNoteMenu: _showActiveNoteMenu,
              onShowRootMenu: _showDesktopRootMenu,
              onCreateNoteInFolder: (path) async {
                _selectFolder(path);
                await _createNote();
              },
              onDeleteFolder: _deleteFolder,
              onCreateFolder: _showCreateFolderDialog,
              onRenameFolder: _renameFolder,
              onMoveFolder: _moveFolder,
              onMoveNoteToFolderPath: _moveNoteToFolderPath,
              onMoveFolderToParentPath: _moveFolderToParentPath,
            ),
          ),
          const VerticalDivider(width: 1),
        ],
        Expanded(
          child: _buildDesktopContent(),
        ),
      ],
    );
  }

  Widget _buildDesktopContent() {
    return _workspaceSection == _WorkspaceSection.trash
        ? _buildTrashList()
        : _buildDesktopEditorPane();
  }

  Widget _buildDesktopEditorPane() {
    if (_desktopEditorSession == null) {
      return _DesktopEditorPlaceholder(
        selectedFolderPath: _selectedFolderPath,
      );
    }

    final session = _desktopEditorSession!;

    final editor = session.note == null
        ? _buildDesktopNoteEditor(session: session, note: null)
        : StreamBuilder<List<Note>>(
            stream: widget.noteRepository.watchActiveNotes(),
            builder: (context, snapshot) {
              Note? liveNote;
              for (final candidate in snapshot.data ?? const <Note>[]) {
                if (candidate.id == session.note!.id) {
                  liveNote = candidate;
                  break;
                }
              }
              return _buildDesktopNoteEditor(
                session: session,
                note: liveNote ?? session.note,
              );
            },
          );

    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: editor,
    );
  }

  Widget _buildDesktopNoteEditor({
    required _DesktopEditorSession session,
    required Note? note,
  }) {
    return NoteEditorPage(
      key: ValueKey('desktop-editor-${session.sessionId}'),
      createNote: widget.createNote,
      updateNote: widget.updateNote,
      noteRepository: widget.noteRepository,
      note: note,
      initialFolderPath: session.initialFolderPath,
      embedded: true,
      mobileTextScale: _mobileNoteTextScale,
      onPersisted: _handleDesktopEditorPersisted,
      onClose: _closeDesktopEditor,
    );
  }

  void _handleDesktopEditorPersisted(Note note) {
    if (!mounted || _desktopEditorSession == null) {
      return;
    }

    setState(() {
      _desktopEditorSession = _desktopEditorSession!.copyWith(
        note: note,
        initialFolderPath: note.folderPath,
      );
      _selectedFolderPath = _normalizeFolderPath(note.folderPath);
      _expandFolderAncestors(note.folderPath);
    });
  }

  void _closeDesktopEditor() {
    if (!mounted) {
      return;
    }

    setState(() {
      _desktopEditorSession = null;
    });
  }
}

class _DesktopEditorSession {
  const _DesktopEditorSession({
    required this.sessionId,
    this.note,
    this.initialFolderPath,
  });

  final int sessionId;
  final Note? note;
  final String? initialFolderPath;

  _DesktopEditorSession copyWith({
    Note? note,
    String? initialFolderPath,
  }) {
    return _DesktopEditorSession(
      sessionId: sessionId,
      note: note ?? this.note,
      initialFolderPath: initialFolderPath ?? this.initialFolderPath,
    );
  }
}

class _DesktopEditorPlaceholder extends StatelessWidget {
  const _DesktopEditorPlaceholder({
    required this.selectedFolderPath,
  });

  final String? selectedFolderPath;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selectionLabel =
        selectedFolderPath == null ? 'All notes' : '"$selectedFolderPath"';

    return Container(
      key: const ValueKey('desktop-editor-placeholder'),
      color: colorScheme.surface,
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.edit_note_outlined,
                size: 40,
                color: colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Keep writing without leaving the workspace.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                'Select a note from the sidebar or create a new one. Current location: $selectionLabel.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopSidebarTree extends StatelessWidget {
  const _DesktopSidebarTree({
    required this.foldersStream,
    required this.notesStream,
    required this.selectedFolderPath,
    required this.selectedNoteId,
    required this.selectedSection,
    required this.expandedFolderPaths,
    required this.onSelectFolder,
    required this.onSelectSection,
    required this.onToggleFolderExpansion,
    required this.onOpenNote,
    required this.onShowNoteMenu,
    required this.onShowRootMenu,
    required this.onCreateNoteInFolder,
    required this.onDeleteFolder,
    required this.onCreateFolder,
    required this.onRenameFolder,
    required this.onMoveFolder,
    required this.onMoveNoteToFolderPath,
    required this.onMoveFolderToParentPath,
  });

  final Stream<List<Folder>> foldersStream;
  final Stream<List<Note>> notesStream;
  final String? selectedFolderPath;
  final String? selectedNoteId;
  final _WorkspaceSection selectedSection;
  final Set<String> expandedFolderPaths;
  final ValueChanged<String?> onSelectFolder;
  final ValueChanged<_WorkspaceSection> onSelectSection;
  final ValueChanged<String> onToggleFolderExpansion;
  final Future<void> Function(Note note) onOpenNote;
  final Future<void> Function(Note note, Offset position) onShowNoteMenu;
  final Future<void> Function(Offset position) onShowRootMenu;
  final Future<void> Function(String? path) onCreateNoteInFolder;
  final Future<void> Function(Folder folder) onDeleteFolder;
  final Future<void> Function(String? parentPath) onCreateFolder;
  final Future<void> Function(Folder folder) onRenameFolder;
  final Future<void> Function(Folder folder) onMoveFolder;
  final Future<void> Function(Note note, String? folderPath)
      onMoveNoteToFolderPath;
  final Future<void> Function(Folder folder, String? parentPath)
      onMoveFolderToParentPath;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: StreamBuilder<List<Folder>>(
        stream: foldersStream,
        builder: (context, folderSnapshot) {
          final folders = folderSnapshot.data ?? const <Folder>[];

          return StreamBuilder<List<Note>>(
            stream: notesStream,
            builder: (context, noteSnapshot) {
              final notes = noteSnapshot.data ?? const <Note>[];
              final content = _DesktopSidebarTreeContent(
                folders: folders,
                notes: notes,
                selectedFolderPath: selectedFolderPath,
                selectedNoteId: selectedNoteId,
                selectedSection: selectedSection,
                expandedFolderPaths: expandedFolderPaths,
                enableDragDrop: true,
                onSelectFolder: onSelectFolder,
                onSelectSection: onSelectSection,
                onToggleFolderExpansion: onToggleFolderExpansion,
                onOpenNote: onOpenNote,
                onShowNoteMenu: onShowNoteMenu,
                onShowRootMenu: onShowRootMenu,
                onCreateNoteInFolder: onCreateNoteInFolder,
                onDeleteFolder: onDeleteFolder,
                onCreateFolder: onCreateFolder,
                onRenameFolder: onRenameFolder,
                onMoveFolder: onMoveFolder,
                onMoveNoteToFolderPath: onMoveNoteToFolderPath,
                onMoveFolderToParentPath: onMoveFolderToParentPath,
              );

              return Column(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onSecondaryTapDown: (details) =>
                        onShowRootMenu(details.globalPosition),
                    onLongPressStart: (details) =>
                        onShowRootMenu(details.globalPosition),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
                      child: Row(
                        children: [
                          Text(
                            'Workspace',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: content,
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _MobileSidebarTree extends StatelessWidget {
  const _MobileSidebarTree({
    required this.foldersStream,
    required this.notesStream,
    required this.selectedFolderPath,
    required this.selectedNoteId,
    required this.selectedSection,
    required this.expandedFolderPaths,
    required this.onSelectFolder,
    required this.onSelectSection,
    required this.onToggleFolderExpansion,
    required this.onOpenNote,
    required this.onShowNoteMenu,
    required this.onShowRootMenu,
    required this.onCreateNoteInFolder,
    required this.onDeleteFolder,
    required this.onCreateFolder,
    required this.onRenameFolder,
    required this.onMoveFolder,
  });

  final Stream<List<Folder>> foldersStream;
  final Stream<List<Note>> notesStream;
  final String? selectedFolderPath;
  final String? selectedNoteId;
  final _WorkspaceSection selectedSection;
  final Set<String> expandedFolderPaths;
  final ValueChanged<String?> onSelectFolder;
  final ValueChanged<_WorkspaceSection> onSelectSection;
  final ValueChanged<String> onToggleFolderExpansion;
  final Future<void> Function(Note note) onOpenNote;
  final Future<void> Function(Note note, Offset position) onShowNoteMenu;
  final Future<void> Function(Offset position) onShowRootMenu;
  final Future<void> Function(String? path) onCreateNoteInFolder;
  final Future<void> Function(Folder folder) onDeleteFolder;
  final Future<void> Function(String? parentPath) onCreateFolder;
  final Future<void> Function(Folder folder) onRenameFolder;
  final Future<void> Function(Folder folder) onMoveFolder;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: StreamBuilder<List<Folder>>(
        stream: foldersStream,
        builder: (context, folderSnapshot) {
          final folders = folderSnapshot.data ?? const <Folder>[];

          return StreamBuilder<List<Note>>(
            stream: notesStream,
            builder: (context, noteSnapshot) {
              final notes = noteSnapshot.data ?? const <Note>[];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
                    child: Text(
                      'Files',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Expanded(
                    child: _DesktopSidebarTreeContent(
                      folders: folders,
                      notes: notes,
                      selectedFolderPath: selectedFolderPath,
                      selectedNoteId: selectedNoteId,
                      selectedSection: selectedSection,
                      expandedFolderPaths: expandedFolderPaths,
                      enableDragDrop: false,
                      onSelectFolder: onSelectFolder,
                      onSelectSection: onSelectSection,
                      onToggleFolderExpansion: onToggleFolderExpansion,
                      onOpenNote: onOpenNote,
                      onShowNoteMenu: onShowNoteMenu,
                      onShowRootMenu: onShowRootMenu,
                      onCreateNoteInFolder: onCreateNoteInFolder,
                      onDeleteFolder: onDeleteFolder,
                      onCreateFolder: onCreateFolder,
                      onRenameFolder: onRenameFolder,
                      onMoveFolder: onMoveFolder,
                      onMoveNoteToFolderPath: (_, __) async {},
                      onMoveFolderToParentPath: (_, __) async {},
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _DesktopSidebarTreeContent extends StatelessWidget {
  const _DesktopSidebarTreeContent({
    required this.folders,
    required this.notes,
    required this.selectedFolderPath,
    required this.selectedNoteId,
    required this.selectedSection,
    required this.expandedFolderPaths,
    required this.enableDragDrop,
    required this.onSelectFolder,
    required this.onSelectSection,
    required this.onToggleFolderExpansion,
    required this.onOpenNote,
    required this.onShowNoteMenu,
    required this.onShowRootMenu,
    required this.onCreateNoteInFolder,
    required this.onDeleteFolder,
    required this.onCreateFolder,
    required this.onRenameFolder,
    required this.onMoveFolder,
    required this.onMoveNoteToFolderPath,
    required this.onMoveFolderToParentPath,
  });

  final List<Folder> folders;
  final List<Note> notes;
  final String? selectedFolderPath;
  final String? selectedNoteId;
  final _WorkspaceSection selectedSection;
  final Set<String> expandedFolderPaths;
  final bool enableDragDrop;
  final ValueChanged<String?> onSelectFolder;
  final ValueChanged<_WorkspaceSection> onSelectSection;
  final ValueChanged<String> onToggleFolderExpansion;
  final Future<void> Function(Note note) onOpenNote;
  final Future<void> Function(Note note, Offset position) onShowNoteMenu;
  final Future<void> Function(Offset position) onShowRootMenu;
  final Future<void> Function(String? path) onCreateNoteInFolder;
  final Future<void> Function(Folder folder) onDeleteFolder;
  final Future<void> Function(String? parentPath) onCreateFolder;
  final Future<void> Function(Folder folder) onRenameFolder;
  final Future<void> Function(Folder folder) onMoveFolder;
  final Future<void> Function(Note note, String? folderPath)
      onMoveNoteToFolderPath;
  final Future<void> Function(Folder folder, String? parentPath)
      onMoveFolderToParentPath;

  @override
  Widget build(BuildContext context) {
    final foldersByParent = <String?, List<Folder>>{};
    for (final folder in folders) {
      foldersByParent
          .putIfAbsent(folder.parentPath, () => <Folder>[])
          .add(folder);
    }
    for (final entry in foldersByParent.entries) {
      entry.value.sort((a, b) => a.path.compareTo(b.path));
    }

    final notesByFolder = <String?, List<Note>>{};
    for (final note in notes) {
      final folderPath = (note.folderPath == null || note.folderPath!.isEmpty)
          ? null
          : note.folderPath;
      notesByFolder.putIfAbsent(folderPath, () => <Note>[]).add(note);
    }
    for (final entry in notesByFolder.entries) {
      entry.value.sort(_compareNotesAlphabetically);
    }

    final children = <Widget>[
      _SidebarHeaderRow(
        icon: Icons.delete_outline,
        label: 'Trash',
        selected: selectedSection == _WorkspaceSection.trash,
        onTap: () => onSelectSection(_WorkspaceSection.trash),
      ),
    ];

    final rootFolders = foldersByParent[null] ?? const <Folder>[];
    for (final folder in rootFolders) {
      children.addAll(
        _buildFolderBranch(
          folder: folder,
          foldersByParent: foldersByParent,
          notesByFolder: notesByFolder,
        ),
      );
    }

    final rootNotes = notesByFolder[null] ?? const <Note>[];
    for (final note in rootNotes) {
      children.add(
        _SidebarNoteTile(
          note: note,
          depth: 0,
          selected: note.id == selectedNoteId,
          onOpen: onOpenNote,
          onShowContextMenu: onShowNoteMenu,
          enableDragDrop: enableDragDrop,
          dragData: _DesktopSidebarDragDataNote(note),
        ),
      );
    }

    if (folders.isEmpty && notes.isEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Text(
            'No notes yet.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        SliverList.list(children: children),
        SliverFillRemaining(
          hasScrollBody: false,
          child: GestureDetector(
            key: const ValueKey('desktop-sidebar-empty-space'),
            behavior: HitTestBehavior.opaque,
            onSecondaryTapDown: (details) =>
                onShowRootMenu(details.globalPosition),
            onLongPressStart: (details) =>
                onShowRootMenu(details.globalPosition),
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildFolderBranch({
    required Folder folder,
    required Map<String?, List<Folder>> foldersByParent,
    required Map<String?, List<Note>> notesByFolder,
  }) {
    final childFolders = foldersByParent[folder.path] ?? const <Folder>[];
    final childNotes = notesByFolder[folder.path] ?? const <Note>[];
    final isExpanded = expandedFolderPaths.contains(folder.path);
    final hasChildren = childFolders.isNotEmpty || childNotes.isNotEmpty;
    final branch = <Widget>[
      _SidebarFolderTile(
        folder: folder,
        expanded: isExpanded,
        hasChildren: hasChildren,
        onTap: () {
          if (hasChildren) {
            if (isExpanded && selectedFolderPath == folder.path) {
              onToggleFolderExpansion(folder.path);
              return;
            }

            if (!isExpanded) {
              onToggleFolderExpansion(folder.path);
            }
          }

          onSelectFolder(folder.path);
        },
        onToggleExpanded: () => onToggleFolderExpansion(folder.path),
        onCreateNote: () => onCreateNoteInFolder(folder.path),
        onCreateFolder: () => onCreateFolder(folder.path),
        onRenameFolder: () => onRenameFolder(folder),
        onMoveFolder: () => onMoveFolder(folder),
        onDeleteFolder: onDeleteFolder,
        enableDragDrop: enableDragDrop,
        canAcceptDrop: (data) {
          if (!enableDragDrop) {
            return false;
          }
          if (data is _DesktopSidebarDragDataNote) {
            return data.note.folderPath != folder.path;
          }
          if (data is _DesktopSidebarDragDataFolder) {
            return data.folder.path != folder.path &&
                !folder.path.startsWith('${data.folder.path}/');
          }
          return false;
        },
        onAcceptDrop: (data) async {
          if (!enableDragDrop) {
            return;
          }
          if (data is _DesktopSidebarDragDataNote) {
            await onMoveNoteToFolderPath(data.note, folder.path);
            return;
          }
          if (data is _DesktopSidebarDragDataFolder) {
            await onMoveFolderToParentPath(data.folder, folder.path);
          }
        },
      ),
    ];

    if (!isExpanded) {
      return branch;
    }

    for (final childFolder in childFolders) {
      branch.addAll(
        _buildFolderBranch(
          folder: childFolder,
          foldersByParent: foldersByParent,
          notesByFolder: notesByFolder,
        ),
      );
    }

    for (final note in childNotes) {
      branch.add(
        _SidebarNoteTile(
          note: note,
          depth: folder.depth + 1,
          selected: note.id == selectedNoteId,
          onOpen: onOpenNote,
          onShowContextMenu: onShowNoteMenu,
          enableDragDrop: enableDragDrop,
          dragData: _DesktopSidebarDragDataNote(note),
        ),
      );
    }

    return branch;
  }

  int _compareNotesAlphabetically(Note a, Note b) {
    final leftTitle = _sortableNoteTitle(a);
    final rightTitle = _sortableNoteTitle(b);
    final titleComparison = leftTitle.compareTo(rightTitle);
    if (titleComparison != 0) {
      return titleComparison;
    }

    return a.id.compareTo(b.id);
  }

  String _sortableNoteTitle(Note note) {
    final title = note.title.trim();
    if (title.isEmpty) {
      return '\uffff${note.id}';
    }
    return title.toLowerCase();
  }
}

class _SidebarHeaderRow extends StatelessWidget {
  const _SidebarHeaderRow({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.onShowContextMenu,
    this.canAcceptDrop,
    this.onAcceptDrop,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Future<void> Function(Offset position)? onShowContextMenu;
  final bool Function(_DesktopSidebarDragData data)? canAcceptDrop;
  final Future<void> Function(_DesktopSidebarDragData data)? onAcceptDrop;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    Widget buildRow(bool isDropTargetActive) {
      return Material(
        color: selected || isDropTargetActive
            ? colorScheme.secondaryContainer
            : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          hoverColor: colorScheme.primary.withValues(alpha: 0.16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget child = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: onShowContextMenu == null
          ? null
          : (details) => onShowContextMenu!(details.globalPosition),
      onLongPressStart: onShowContextMenu == null
          ? null
          : (details) => onShowContextMenu!(details.globalPosition),
      child: buildRow(false),
    );

    if (canAcceptDrop == null || onAcceptDrop == null) {
      return child;
    }

    return DragTarget<_DesktopSidebarDragData>(
      onWillAcceptWithDetails: (details) => canAcceptDrop!(details.data),
      onAcceptWithDetails: (details) async {
        await onAcceptDrop!(details.data);
      },
      builder: (context, candidateData, rejectedData) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onSecondaryTapDown: onShowContextMenu == null
              ? null
              : (details) => onShowContextMenu!(details.globalPosition),
          onLongPressStart: onShowContextMenu == null
              ? null
              : (details) => onShowContextMenu!(details.globalPosition),
          child: buildRow(candidateData.isNotEmpty),
        );
      },
    );
  }
}

class _SidebarFolderTile extends StatelessWidget {
  const _SidebarFolderTile({
    required this.folder,
    required this.expanded,
    required this.hasChildren,
    required this.onTap,
    required this.onToggleExpanded,
    required this.onCreateNote,
    required this.onCreateFolder,
    required this.onRenameFolder,
    required this.onMoveFolder,
    required this.onDeleteFolder,
    required this.enableDragDrop,
    required this.canAcceptDrop,
    required this.onAcceptDrop,
  });

  final Folder folder;
  final bool expanded;
  final bool hasChildren;
  final VoidCallback onTap;
  final VoidCallback onToggleExpanded;
  final Future<void> Function() onCreateNote;
  final Future<void> Function() onCreateFolder;
  final Future<void> Function() onRenameFolder;
  final Future<void> Function() onMoveFolder;
  final Future<void> Function(Folder folder) onDeleteFolder;
  final bool enableDragDrop;
  final bool Function(_DesktopSidebarDragData data) canAcceptDrop;
  final Future<void> Function(_DesktopSidebarDragData data) onAcceptDrop;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    Widget buildDragHandle() {
      return Draggable<_DesktopSidebarDragData>(
        data: _DesktopSidebarDragDataFolder(folder),
        onDragEnd: (details) {
          if (details.wasAccepted || !context.mounted) {
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Folder move was not accepted. Drop it on another folder or the root level.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        feedback: Material(
          elevation: 4,
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.folder_outlined, size: 18),
                const SizedBox(width: 8),
                Text(folder.name),
              ],
            ),
          ),
        ),
        childWhenDragging: Icon(
          Icons.drag_indicator,
          key: ValueKey('sidebar-folder-drag-${folder.path}'),
          size: 18,
          color: colorScheme.outline,
        ),
        child: Icon(
          Icons.drag_indicator,
          key: ValueKey('sidebar-folder-drag-${folder.path}'),
          size: 18,
          color: colorScheme.outline,
        ),
      );
    }

    Widget buildTile(bool isDropTargetActive) {
      return _SidebarTreeGuide(
        depth: folder.depth,
        guideKey: ValueKey('sidebar-tree-guide-folder-${folder.path}'),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onSecondaryTapDown: (details) =>
              _showFolderMenu(context, details.globalPosition),
          onLongPressStart: (details) =>
              _showFolderMenu(context, details.globalPosition),
          child: Material(
            color: isDropTargetActive
                ? colorScheme.secondaryContainer
                : Colors.transparent,
            child: InkWell(
              key: ValueKey('sidebar-folder-tile-${folder.path}'),
              onTap: onTap,
              hoverColor: colorScheme.primary.withValues(alpha: 0.18),
              child: Padding(
                padding: EdgeInsets.only(
                  left: 8 + (folder.depth * 14),
                  right: 4,
                  top: 2,
                  bottom: 2,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: hasChildren
                          ? IconButton(
                              key: ValueKey(
                                  'sidebar-folder-toggle-${folder.path}'),
                              onPressed: onToggleExpanded,
                              tooltip: expanded
                                  ? 'Collapse folder'
                                  : 'Expand folder',
                              iconSize: 18,
                              splashRadius: 16,
                              icon: Icon(
                                expanded
                                    ? Icons.keyboard_arrow_down
                                    : Icons.keyboard_arrow_right,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    const Icon(Icons.folder_outlined, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        folder.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (enableDragDrop)
                      Tooltip(
                        message: 'Drag folder',
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: buildDragHandle(),
                        ),
                      ),
                    PopupMenuButton<_FolderMenuAction>(
                      tooltip: 'Folder actions',
                      onSelected: (action) => _handleFolderAction(action),
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: _FolderMenuAction.createNote,
                          child: Text('New note'),
                        ),
                        PopupMenuItem(
                          value: _FolderMenuAction.createFolder,
                          child: Text('New folder'),
                        ),
                        PopupMenuItem(
                          value: _FolderMenuAction.move,
                          child: Text('Move'),
                        ),
                        PopupMenuItem(
                          value: _FolderMenuAction.rename,
                          child: Text('Rename'),
                        ),
                        PopupMenuItem(
                          value: _FolderMenuAction.delete,
                          child: Text('Delete'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (!enableDragDrop) {
      return buildTile(false);
    }

    return DragTarget<_DesktopSidebarDragData>(
      onWillAcceptWithDetails: (details) => canAcceptDrop(details.data),
      onAcceptWithDetails: (details) async {
        await onAcceptDrop(details.data);
      },
      builder: (context, candidateData, rejectedData) {
        return buildTile(candidateData.isNotEmpty);
      },
    );
  }

  Future<void> _showFolderMenu(BuildContext context, Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<_FolderMenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(position, position),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(
          value: _FolderMenuAction.createNote,
          child: Text('New note'),
        ),
        PopupMenuItem(
          value: _FolderMenuAction.createFolder,
          child: Text('New folder'),
        ),
        PopupMenuItem(
          value: _FolderMenuAction.move,
          child: Text('Move'),
        ),
        PopupMenuItem(
          value: _FolderMenuAction.rename,
          child: Text('Rename'),
        ),
        PopupMenuItem(
          value: _FolderMenuAction.delete,
          child: Text('Delete'),
        ),
      ],
    );

    if (!context.mounted || action == null) {
      return;
    }

    await _handleFolderAction(action);
  }

  Future<void> _handleFolderAction(_FolderMenuAction action) async {
    switch (action) {
      case _FolderMenuAction.createNote:
        await onCreateNote();
      case _FolderMenuAction.createFolder:
        await onCreateFolder();
      case _FolderMenuAction.move:
        await onMoveFolder();
      case _FolderMenuAction.rename:
        await onRenameFolder();
      case _FolderMenuAction.delete:
        await onDeleteFolder(folder);
    }
  }
}

class _SidebarNoteTile extends StatelessWidget {
  const _SidebarNoteTile({
    required this.note,
    required this.depth,
    required this.selected,
    required this.onOpen,
    required this.onShowContextMenu,
    required this.enableDragDrop,
    required this.dragData,
  });

  final Note note;
  final int depth;
  final bool selected;
  final Future<void> Function(Note note) onOpen;
  final Future<void> Function(Note note, Offset position) onShowContextMenu;
  final bool enableDragDrop;
  final _DesktopSidebarDragDataNote dragData;

  @override
  Widget build(BuildContext context) {
    final title = note.title.isEmpty ? 'Untitled note' : note.title;
    final colorScheme = Theme.of(context).colorScheme;
    final titleStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: selected ? FontWeight.w700 : null,
          color: note.syncStatus == SyncStatus.conflicted
              ? colorScheme.tertiary
              : null,
        );

    Widget buildTile() {
      return _SidebarTreeGuide(
        depth: depth,
        guideKey: ValueKey('sidebar-tree-guide-note-${note.id}'),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onSecondaryTapDown: (details) =>
              onShowContextMenu(note, details.globalPosition),
          onLongPressStart: (details) =>
              onShowContextMenu(note, details.globalPosition),
          child: Material(
            key: ValueKey('sidebar-note-surface-${note.id}'),
            color: selected
                ? colorScheme.surfaceContainerHigh
                : Colors.transparent,
            child: InkWell(
              key: ValueKey('sidebar-note-${note.id}'),
              onTap: () => onOpen(note),
              hoverColor: colorScheme.primary.withValues(alpha: 0.18),
              child: Padding(
                padding: EdgeInsets.only(
                  left: 48 + (depth * 14),
                  right: 12,
                  top: 8,
                  bottom: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _SidebarNoteSyncIndicator(status: note.syncStatus),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (!enableDragDrop) {
      return buildTile();
    }

    return Draggable<_DesktopSidebarDragData>(
      data: dragData,
      onDragEnd: (details) {
        if (details.wasAccepted || !context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Note move was not accepted. Drop it on a folder or the root level.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      feedback: Material(
        elevation: 4,
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: buildTile(),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.55,
        child: buildTile(),
      ),
      child: buildTile(),
    );
  }
}

class _SidebarTreeGuide extends StatelessWidget {
  const _SidebarTreeGuide({
    required this.depth,
    required this.child,
    required this.guideKey,
  });

  final int depth;
  final Widget child;
  final Key guideKey;

  @override
  Widget build(BuildContext context) {
    if (depth <= 0) {
      return child;
    }

    final guideColor = Theme.of(context).colorScheme.outlineVariant;
    final leftOffset = 18.0 + ((depth - 1) * 14.0);

    return Stack(
      children: [
        Positioned(
          left: leftOffset,
          top: 2,
          bottom: 2,
          child: IgnorePointer(
            child: Container(
              key: guideKey,
              width: 1,
              color: guideColor.withValues(alpha: 0.8),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _SidebarNoteSyncIndicator extends StatelessWidget {
  const _SidebarNoteSyncIndicator({
    required this.status,
  });

  final SyncStatus status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (icon, color, tooltip) = switch (status) {
      SyncStatus.synced => (
          Icons.cloud_done_outlined,
          colorScheme.secondary,
          'Synced',
        ),
      SyncStatus.pendingUpload => (
          Icons.cloud_upload_outlined,
          colorScheme.primary,
          'Pending sync',
        ),
      SyncStatus.pendingDelete => (
          Icons.delete_outline,
          colorScheme.error,
          'Pending delete sync',
        ),
      SyncStatus.conflicted => (
          Icons.warning_amber_outlined,
          colorScheme.tertiary,
          'Sync conflict',
        ),
    };

    return Tooltip(
      message: tooltip,
      child: Icon(
        icon,
        size: 16,
        color: color,
      ),
    );
  }
}

enum _TopBarMenuAction {
  forceReuploadAllNotes,
  importObsidianNotes,
  showAttachmentsFolder,
}

class _NotesList extends StatelessWidget {
  const _NotesList({
    required this.stream,
    required this.mobileLayout,
    required this.emptyState,
    required this.onTap,
    required this.onRestoreConflictCopy,
    required this.onShowContextMenu,
    required this.trailingBuilder,
  });

  final Stream<List<Note>> stream;
  final bool mobileLayout;
  final String emptyState;
  final Future<void> Function(Note note) onTap;
  final Future<void> Function(Note note) onRestoreConflictCopy;
  final Future<void> Function(Note note, Offset position) onShowContextMenu;
  final Widget Function(BuildContext context, Note note) trailingBuilder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Note>>(
      stream: stream,
      builder: (context, snapshot) {
        final notes = snapshot.data ?? const <Note>[];

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (notes.isEmpty) {
          return Center(child: Text(emptyState));
        }

        return ListView.separated(
          padding: EdgeInsets.fromLTRB(4, mobileLayout ? 4 : 12, 4, 140),
          itemCount: notes.length,
          separatorBuilder: (_, __) => SizedBox(height: mobileLayout ? 10 : 8),
          itemBuilder: (context, index) {
            final note = notes[index];
            final title = note.title.isEmpty ? 'Untitled note' : note.title;
            final secondaryLine = _buildSecondaryLine(note);
            final isConflictCopy = note.syncStatus == SyncStatus.conflicted;
            final colorScheme = Theme.of(context).colorScheme;

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onSecondaryTapDown: (details) =>
                  onShowContextMenu(note, details.globalPosition),
              onLongPressStart: (details) =>
                  onShowContextMenu(note, details.globalPosition),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(28),
                child: InkWell(
                  borderRadius: BorderRadius.circular(28),
                  onTap: () => isConflictCopy
                      ? onRestoreConflictCopy(note)
                      : onTap(note),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isConflictCopy
                          ? colorScheme.tertiaryContainer
                              .withValues(alpha: 0.36)
                          : colorScheme.surface,
                      borderRadius:
                          BorderRadius.circular(mobileLayout ? 28 : 22),
                      boxShadow: mobileLayout
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 18,
                                offset: const Offset(0, 10),
                              ),
                            ]
                          : null,
                    ),
                    padding: EdgeInsets.fromLTRB(
                      mobileLayout ? 20 : 16,
                      mobileLayout ? 18 : 10,
                      mobileLayout ? 10 : 16,
                      mobileLayout ? 18 : 10,
                    ),
                    child: mobileLayout
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: -0.6,
                                          ),
                                    ),
                                    const SizedBox(height: 10),
                                    if (isConflictCopy) ...[
                                      Text(
                                        'Conflict copy preserved during sync.',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      const SizedBox(height: 8),
                                    ],
                                    Text(
                                      _buildPlainExcerpt(note),
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyLarge
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                            height: 1.45,
                                          ),
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      secondaryLine,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              trailingBuilder(context, note),
                            ],
                          )
                        : ListTile(
                            hoverColor:
                                colorScheme.primary.withValues(alpha: 0.18),
                            contentPadding: EdgeInsets.zero,
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _SyncStatusChip(status: note.syncStatus),
                              ],
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (isConflictCopy) ...[
                                    Text(
                                      'Conflict copy preserved during sync. Review before editing further.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                  MarkdownPreview(
                                    document: note.document,
                                    compact: true,
                                    maxBlocks: 2,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    secondaryLine,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            trailing: trailingBuilder(context, note),
                          ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _buildSecondaryLine(Note note) {
    final timestamp = _formatTimestamp(note);
    final folderPath = note.folderPath;
    if (folderPath == null || folderPath.isEmpty) {
      return timestamp;
    }

    return '$timestamp  •  $folderPath';
  }

  String _buildPlainExcerpt(Note note) {
    final lines = note.content
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .where((line) => !line.startsWith('!['))
        .toList(growable: false);
    if (lines.isEmpty) {
      return 'Start writing...';
    }

    final cleaned = lines.first
        .replaceAll(RegExp(r'^#{1,6}\s*'), '')
        .replaceAll(RegExp(r'^-\s+\[[ xX]\]\s*'), '')
        .replaceAll(RegExp(r'^-\s+'), '')
        .replaceAll(RegExp(r'^>\s+'), '')
        .trim();
    return cleaned.isEmpty ? 'Start writing...' : cleaned;
  }
}

class _MobileChromeSurface extends StatelessWidget {
  const _MobileChromeSurface({
    required this.child,
    this.padding = const EdgeInsets.all(2),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}

enum _MobileAppMenuAction {
  sync,
  forceReuploadAllNotes,
  account,
  noteTextSize,
  importObsidianNotes,
  showAttachmentsFolder,
}

class _FolderSidebar extends StatelessWidget {
  const _FolderSidebar({
    required this.stream,
    required this.selectedFolderPath,
    required this.selectedSection,
    required this.onSelectFolder,
    required this.onSelectSection,
    required this.onShowRootMenu,
    required this.onCreateNoteInFolder,
    required this.onDeleteFolder,
    required this.onCreateFolder,
    required this.onRenameFolder,
    required this.onMoveFolder,
  });

  final Stream<List<Folder>> stream;
  final String? selectedFolderPath;
  final _WorkspaceSection selectedSection;
  final ValueChanged<String?> onSelectFolder;
  final ValueChanged<_WorkspaceSection> onSelectSection;
  final Future<void> Function(Offset position) onShowRootMenu;
  final Future<void> Function(String? path) onCreateNoteInFolder;
  final Future<void> Function(Folder folder) onDeleteFolder;
  final Future<void> Function(String? parentPath) onCreateFolder;
  final Future<void> Function(Folder folder) onRenameFolder;
  final Future<void> Function(Folder folder) onMoveFolder;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                Text(
                  'Folders',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
          ListTile(
            selected: selectedSection == _WorkspaceSection.trash,
            leading: const Icon(Icons.delete_outline),
            title: const Text('Trash'),
            onTap: () => onSelectSection(_WorkspaceSection.trash),
          ),
          Expanded(
            child: StreamBuilder<List<Folder>>(
              stream: stream,
              builder: (context, snapshot) {
                final folders = snapshot.data ?? const <Folder>[];
                if (folders.isEmpty) {
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onSecondaryTapDown: (details) =>
                        onShowRootMenu(details.globalPosition),
                    onLongPressStart: (details) =>
                        onShowRootMenu(details.globalPosition),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No folders yet.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: folders.length,
                  itemBuilder: (context, index) {
                    final folder = folders[index];
                    return _FolderListTile(
                      folder: folder,
                      selected: selectedSection == _WorkspaceSection.notes &&
                          folder.path == selectedFolderPath,
                      onSelectFolder: onSelectFolder,
                      onCreateNote: () => onCreateNoteInFolder(folder.path),
                      onCreateFolder: () => onCreateFolder(folder.path),
                      onRenameFolder: () => onRenameFolder(folder),
                      onMoveFolder: () => onMoveFolder(folder),
                      onDeleteFolder: onDeleteFolder,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FolderListTile extends StatelessWidget {
  const _FolderListTile({
    required this.folder,
    required this.selected,
    required this.onSelectFolder,
    required this.onCreateNote,
    required this.onCreateFolder,
    required this.onRenameFolder,
    required this.onMoveFolder,
    required this.onDeleteFolder,
  });

  final Folder folder;
  final bool selected;
  final ValueChanged<String?> onSelectFolder;
  final Future<void> Function() onCreateNote;
  final Future<void> Function() onCreateFolder;
  final Future<void> Function() onRenameFolder;
  final Future<void> Function() onMoveFolder;
  final Future<void> Function(Folder folder) onDeleteFolder;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) =>
          _showFolderMenu(context, details.globalPosition),
      onLongPressStart: (details) =>
          _showFolderMenu(context, details.globalPosition),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: ListTile(
          selected: selected,
          hoverColor: Theme.of(context).colorScheme.primary.withValues(
                alpha: 0.18,
              ),
          leading: const Icon(Icons.folder_outlined),
          minLeadingWidth: 24,
          contentPadding: EdgeInsets.only(
            left: 16 + (folder.depth * 16),
            right: 4,
          ),
          title: Text(folder.name),
          subtitle: folder.parentPath == null
              ? null
              : Text(
                  folder.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          onTap: () => onSelectFolder(folder.path),
          trailing: PopupMenuButton<_FolderMenuAction>(
            tooltip: 'Folder actions',
            onSelected: (action) => _handleFolderAction(action),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _FolderMenuAction.createNote,
                child: Text('New note'),
              ),
              PopupMenuItem(
                value: _FolderMenuAction.createFolder,
                child: Text('New folder'),
              ),
              PopupMenuItem(
                value: _FolderMenuAction.move,
                child: Text('Move'),
              ),
              PopupMenuItem(
                value: _FolderMenuAction.rename,
                child: Text('Rename'),
              ),
              PopupMenuItem(
                value: _FolderMenuAction.delete,
                child: Text('Delete'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showFolderMenu(BuildContext context, Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<_FolderMenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(position, position),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(
          value: _FolderMenuAction.createNote,
          child: Text('New note'),
        ),
        PopupMenuItem(
          value: _FolderMenuAction.createFolder,
          child: Text('New folder'),
        ),
        PopupMenuItem(
          value: _FolderMenuAction.move,
          child: Text('Move'),
        ),
        PopupMenuItem(
          value: _FolderMenuAction.rename,
          child: Text('Rename'),
        ),
        PopupMenuItem(
          value: _FolderMenuAction.delete,
          child: Text('Delete'),
        ),
      ],
    );

    if (!context.mounted || action == null) {
      return;
    }

    await _handleFolderAction(action);
  }

  Future<void> _handleFolderAction(_FolderMenuAction action) async {
    switch (action) {
      case _FolderMenuAction.createNote:
        await onCreateNote();
      case _FolderMenuAction.createFolder:
        await onCreateFolder();
      case _FolderMenuAction.move:
        await onMoveFolder();
      case _FolderMenuAction.rename:
        await onRenameFolder();
      case _FolderMenuAction.delete:
        await onDeleteFolder(folder);
    }
  }
}

class _SyncStatusChip extends StatelessWidget {
  const _SyncStatusChip({
    required this.status,
  });

  final SyncStatus status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (label, backgroundColor, foregroundColor) = switch (status) {
      SyncStatus.synced => (
          'Synced',
          colorScheme.secondaryContainer,
          colorScheme.onSecondaryContainer,
        ),
      SyncStatus.pendingUpload => (
          'Local',
          colorScheme.primaryContainer,
          colorScheme.onPrimaryContainer,
        ),
      SyncStatus.pendingDelete => (
          'Deleted',
          colorScheme.errorContainer,
          colorScheme.onErrorContainer,
        ),
      SyncStatus.conflicted => (
          'Conflict',
          colorScheme.tertiaryContainer,
          colorScheme.onTertiaryContainer,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foregroundColor,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _MobileNoteActionsSheet extends StatelessWidget {
  const _MobileNoteActionsSheet({
    required this.note,
    required this.showMoveAction,
    required this.showResolveConflictAction,
  });

  final Note note;
  final bool showMoveAction;
  final bool showResolveConflictAction;

  @override
  Widget build(BuildContext context) {
    final title = note.title.isEmpty ? 'Untitled note' : note.title;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            _MobileActionTile(
              icon: Icons.open_in_new,
              label: 'Open',
              onTap: () => Navigator.of(context).pop(_NoteMenuAction.open),
            ),
            if (showMoveAction)
              _MobileActionTile(
                icon: Icons.drive_file_move_outline,
                label: 'Move to folder',
                onTap: () => Navigator.of(context).pop(_NoteMenuAction.move),
              ),
            if (showResolveConflictAction)
              _MobileActionTile(
                icon: Icons.rule_folder_outlined,
                label: 'Resolve conflict',
                onTap: () =>
                    Navigator.of(context).pop(_NoteMenuAction.resolveConflict),
              ),
            _MobileActionTile(
              icon: Icons.delete_outline,
              label: 'Delete',
              destructive: true,
              onTap: () => Navigator.of(context).pop(_NoteMenuAction.delete),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileActionTile extends StatelessWidget {
  const _MobileActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? Theme.of(context).colorScheme.error : null;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: color == null ? null : TextStyle(color: color),
      ),
      onTap: onTap,
    );
  }
}

class _MoveNoteFolderSheet extends StatelessWidget {
  const _MoveNoteFolderSheet({
    required this.foldersStream,
    required this.currentFolderPath,
  });

  final Stream<List<Folder>> foldersStream;
  final String? currentFolderPath;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Folder>>(
      stream: foldersStream,
      builder: (context, snapshot) {
        final folders = List<Folder>.from(snapshot.data ?? const <Folder>[])
          ..sort((a, b) => a.path.compareTo(b.path));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Text(
                'Move note',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Choose a destination folder',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  _FolderDestinationTile(
                    label: 'All notes',
                    subtitle: 'Move note to root',
                    selected: currentFolderPath == null,
                    depth: 0,
                    onTap: () => Navigator.of(context).pop(''),
                  ),
                  for (final folder in folders)
                    _FolderDestinationTile(
                      label: folder.name,
                      subtitle: folder.parentPath == null ? null : folder.path,
                      selected: currentFolderPath == folder.path,
                      depth: folder.depth,
                      onTap: () =>
                          Navigator.of(context).pop<String?>(folder.path),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ConflictResolutionSheet extends StatelessWidget {
  const _ConflictResolutionSheet({
    required this.conflictNote,
    required this.originalNote,
    required this.baseTitle,
  });

  final Note conflictNote;
  final Note? originalNote;
  final String baseTitle;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                'Resolve conflict',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                originalNote == null
                    ? 'This conflict copy can be converted back into a normal note.'
                    : 'Choose which version to keep. The other one will be moved to trash.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            _MobileActionTile(
              icon: Icons.open_in_new,
              label: 'Open conflict copy',
              onTap: () => Navigator.of(context).pop(
                _ConflictResolutionAction.openConflictCopy,
              ),
            ),
            if (originalNote != null)
              _MobileActionTile(
                icon: Icons.article_outlined,
                label: 'Open original',
                onTap: () => Navigator.of(context)
                    .pop(_ConflictResolutionAction.openOriginal),
              ),
            if (originalNote != null)
              _MobileActionTile(
                icon: Icons.check_circle_outline,
                label: 'Keep original',
                onTap: () => Navigator.of(context)
                    .pop(_ConflictResolutionAction.keepOriginal),
              ),
            _MobileActionTile(
              icon: Icons.check_circle,
              label: originalNote == null
                  ? 'Convert to normal note'
                  : 'Keep conflict copy',
              onTap: () => Navigator.of(context).pop(
                _ConflictResolutionAction.keepConflictCopy,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Text(
                'Resolved title: $baseTitle',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FolderDestinationTile extends StatelessWidget {
  const _FolderDestinationTile({
    required this.label,
    required this.selected,
    required this.depth,
    required this.onTap,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final bool selected;
  final int depth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: ValueKey('move-note-folder-$label'),
      selected: selected,
      contentPadding: EdgeInsets.only(
        left: 20 + (depth * 20),
        right: 16,
      ),
      leading: Icon(selected ? Icons.check : Icons.folder_outlined),
      title: Text(label),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      onTap: onTap,
    );
  }
}

class _TextEntryDialog extends StatefulWidget {
  const _TextEntryDialog({
    required this.title,
    required this.labelText,
    required this.hintText,
    required this.actionLabel,
    required this.initialValue,
  });

  final String title;
  final String labelText;
  final String hintText;
  final String actionLabel;
  final String initialValue;

  @override
  State<_TextEntryDialog> createState() => _TextEntryDialogState();
}

class _TextEntryDialogState extends State<_TextEntryDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextFormField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: widget.labelText,
          hintText: widget.hintText,
        ),
        onFieldSubmitted: (_) {
          Navigator.of(context).pop(_controller.text.trim());
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }
}

String _formatTimestamp(Note note) {
  final timestamp = note.deletedAt ?? note.updatedAt;
  return _formatDateTime(timestamp);
}

String _formatDateTime(DateTime timestamp) {
  final month = _monthNames[timestamp.month - 1];
  final day = timestamp.day.toString().padLeft(2, '0');
  final hour = timestamp.hour.toString().padLeft(2, '0');
  final minute = timestamp.minute.toString().padLeft(2, '0');

  return '$month $day, $hour:$minute';
}

const _monthNames = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

enum _NoteMenuAction {
  open,
  resolveConflict,
  move,
  delete,
  restore,
}

enum _ConflictResolutionAction {
  openConflictCopy,
  openOriginal,
  keepOriginal,
  keepConflictCopy,
}

enum _FolderMenuAction {
  createNote,
  createFolder,
  move,
  rename,
  delete,
}

enum _RootSidebarMenuAction {
  createNote,
  createFolder,
}

enum _WorkspaceSection {
  notes,
  trash,
}

sealed class _DesktopSidebarDragData {
  const _DesktopSidebarDragData();
}

class _DesktopSidebarDragDataNote extends _DesktopSidebarDragData {
  const _DesktopSidebarDragDataNote(this.note);

  final Note note;
}

class _DesktopSidebarDragDataFolder extends _DesktopSidebarDragData {
  const _DesktopSidebarDragDataFolder(this.folder);

  final Folder folder;
}

class _CreateNoteIntent extends Intent {
  const _CreateNoteIntent();
}

class _SearchNotesIntent extends Intent {
  const _SearchNotesIntent();
}
