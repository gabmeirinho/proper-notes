import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../auth/application/auth_controller.dart';
import '../../auth/presentation/account_sheet.dart';
import '../../sync/application/sync_controller.dart';
import '../application/create_note.dart';
import '../application/delete_note.dart';
import '../application/restore_note.dart';
import '../application/search_notes.dart';
import '../application/update_note.dart';
import '../domain/note.dart';
import '../domain/note_repository.dart';
import '../domain/sync_status.dart';
import 'note_editor_page.dart';
import 'note_search_delegate.dart';

class NotesHomePage extends StatefulWidget {
  const NotesHomePage({
    required this.createNote,
    required this.updateNote,
    required this.deleteNote,
    required this.restoreNote,
    required this.searchNotes,
    required this.noteRepository,
    required this.authController,
    required this.syncController,
    super.key,
  });

  final CreateNote createNote;
  final UpdateNote updateNote;
  final DeleteNote deleteNote;
  final RestoreNote restoreNote;
  final SearchNotes searchNotes;
  final NoteRepository noteRepository;
  final AuthController authController;
  final SyncController syncController;

  @override
  State<NotesHomePage> createState() => _NotesHomePageState();
}

class _NotesHomePageState extends State<NotesHomePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = widget.authController;
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
        child: DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Proper Notes'),
              actions: [
                AnimatedBuilder(
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
                        isSignedIn
                            ? Icons.account_circle
                            : Icons.account_circle_outlined,
                      ),
                    );
                  },
                ),
                AnimatedBuilder(
                  animation: Listenable.merge([
                    widget.authController,
                    widget.syncController,
                  ]),
                  builder: (context, _) {
                    final isCheckingAccount =
                        !widget.authController.hasResolvedInitialSession &&
                            widget.authController.isBusy;
                    return IconButton(
                      onPressed:
                          widget.syncController.isSyncing || isCheckingAccount
                              ? null
                              : _runSync,
                      tooltip: 'Sync',
                      icon: widget.syncController.isSyncing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync),
                    );
                  },
                ),
                IconButton(
                  onPressed: _showSearch,
                  icon: const Icon(Icons.search),
                  tooltip: 'Search',
                ),
              ],
              bottom: TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'Notes'),
                  Tab(text: 'Deleted'),
                ],
              ),
            ),
            body: Column(
              children: [
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Shortcuts: Ctrl/Cmd+N for a new note, Ctrl/Cmd+F to search',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                AnimatedBuilder(
                  animation: Listenable.merge([
                    widget.authController,
                    widget.syncController,
                  ]),
                  builder: (context, _) {
                    final isCheckingAccount =
                        !authState.hasResolvedInitialSession &&
                            authState.isBusy;
                    final syncReady = authState.isSignedIn;
                    final lastCompletedAt =
                        widget.syncController.lastCompletedAt;
                    final lastSyncLabel = lastCompletedAt == null
                        ? 'No sync has completed yet'
                        : 'Last sync: ${_formatDateTime(lastCompletedAt)}';

                    return Container(
                      width: double.infinity,
                      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: syncReady
                            ? Theme.of(context).colorScheme.secondaryContainer
                            : Theme.of(context)
                                .colorScheme
                                .surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isCheckingAccount
                                ? 'Checking account'
                                : widget.syncController.isSyncing
                                    ? 'Syncing now'
                                    : (syncReady
                                        ? 'Sync ready'
                                        : 'Sync unavailable'),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isCheckingAccount
                                ? 'Restoring your Google session before enabling sync.'
                                : widget.syncController.isSyncing
                                    ? 'Checking for note changes and uploading local updates.'
                                    : (syncReady
                                        ? lastSyncLabel
                                        : 'Sign in to Google to enable Drive sync.'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    );
                  },
                ),
                AnimatedBuilder(
                  animation: widget.syncController,
                  builder: (context, _) {
                    final message = widget.syncController.lastMessage;
                    final error = widget.syncController.errorMessage;
                    if (message == null && error == null) {
                      return const SizedBox.shrink();
                    }

                    final isError = error != null;
                    final summary = error ?? message!;
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
                            : Theme.of(context).colorScheme.secondaryContainer,
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
                        ],
                      ),
                    );
                  },
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _NotesList(
                        stream: widget.noteRepository.watchActiveNotes(),
                        emptyState: 'No notes yet. Create your first note.',
                        onTap: _openEditor,
                        onRestoreConflictCopy: _restoreConflictCopy,
                        trailingBuilder: (context, note) {
                          return IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _delete(note),
                          );
                        },
                      ),
                      _NotesList(
                        stream: widget.noteRepository.watchDeletedNotes(),
                        emptyState: 'No deleted notes.',
                        onTap: (_) async {},
                        onRestoreConflictCopy: _restoreConflictCopy,
                        trailingBuilder: (context, note) {
                          return IconButton(
                            tooltip: 'Restore',
                            icon: const Icon(Icons.restore),
                            onPressed: () => _restore(note),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: _createNote,
              icon: const Icon(Icons.add),
              label: const Text('New note'),
            ),
          ),
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

  Future<void> _createNote() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => NoteEditorPage(
          createNote: widget.createNote,
          updateNote: widget.updateNote,
        ),
      ),
    );
  }

  Future<void> _showSearch() async {
    final selectedNote = await showSearch<Note?>(
      context: context,
      delegate: NoteSearchDelegate(
        searchNotes: widget.searchNotes,
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
    }
  }

  Future<void> _runSync() async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await widget.syncController.syncNow();
    if (!mounted || result == null) {
      final error = widget.syncController.errorMessage;
      if (error != null) {
        messenger.showSnackBar(
          SnackBar(content: Text(error)),
        );
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

  Future<void> _openEditor(Note note) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => NoteEditorPage(
          createNote: widget.createNote,
          updateNote: widget.updateNote,
          note: note,
        ),
      ),
    );
  }

  Future<void> _delete(Note note) async {
    await widget.deleteNote(note.id);
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            note.title.isEmpty ? 'Note deleted' : '"${note.title}" deleted'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            widget.restoreNote(note.id);
          },
        ),
      ),
    );
  }

  Future<void> _restore(Note note) async {
    await widget.restoreNote(note.id);
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          note.title.isEmpty ? 'Note restored' : '"${note.title}" restored',
        ),
      ),
    );
  }
}

class _NotesList extends StatelessWidget {
  const _NotesList({
    required this.stream,
    required this.emptyState,
    required this.onTap,
    required this.onRestoreConflictCopy,
    required this.trailingBuilder,
  });

  final Stream<List<Note>> stream;
  final String emptyState;
  final Future<void> Function(Note note) onTap;
  final Future<void> Function(Note note) onRestoreConflictCopy;
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
          padding: const EdgeInsets.all(12),
          itemCount: notes.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final note = notes[index];
            final title = note.title.isEmpty ? 'Untitled note' : note.title;
            final preview = note.content.trim().isEmpty
                ? 'No content'
                : note.content.trim().replaceAll('\n', ' ');
            final secondaryLine = _buildSecondaryLine(note);
            final isConflictCopy = note.syncStatus == SyncStatus.conflicted;

            return Card(
              elevation: 0,
              color: isConflictCopy
                  ? Theme.of(context).colorScheme.tertiaryContainer
                  : Theme.of(context).colorScheme.surface,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
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
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Text(
                        preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        secondaryLine,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                onTap: () =>
                    isConflictCopy ? onRestoreConflictCopy(note) : onTap(note),
                trailing: trailingBuilder(context, note),
              ),
            );
          },
        );
      },
    );
  }

  String _buildSecondaryLine(Note note) {
    final compactPreview = note.content
        .trim()
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .take(2)
        .join('  ');

    final timestamp = _formatTimestamp(note);
    if (compactPreview.isEmpty) {
      return timestamp;
    }

    return '$timestamp  •  $compactPreview';
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

class _CreateNoteIntent extends Intent {
  const _CreateNoteIntent();
}

class _SearchNotesIntent extends Intent {
  const _SearchNotesIntent();
}
