import 'dart:async';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/clipboard_image_service.dart';
import '../../../core/utils/attachments.dart';
import '../../../core/utils/markdown_title.dart';
import '../../../core/utils/note_document.dart';
import 'attachment_image_preview.dart';
import '../application/create_note.dart';
import '../application/update_note.dart';
import '../domain/note.dart';
import '../domain/note_repository.dart';
import '../domain/sync_status.dart';

class NoteEditorPage extends StatefulWidget {
  const NoteEditorPage({
    required this.createNote,
    required this.updateNote,
    required this.noteRepository,
    this.note,
    this.initialFolderPath,
    this.embedded = false,
    this.showInlineStatus = true,
    this.mobileTextScale = 0.92,
    this.onClose,
    this.onPersisted,
    this.onStatusChanged,
    super.key,
  });

  final CreateNote createNote;
  final UpdateNote updateNote;
  final NoteRepository noteRepository;
  final Note? note;
  final String? initialFolderPath;
  final bool embedded;
  final bool showInlineStatus;
  final double mobileTextScale;
  final VoidCallback? onClose;
  final ValueChanged<Note>? onPersisted;
  final ValueChanged<NoteEditorStatusSnapshot>? onStatusChanged;

  bool get isEditing => note != null;

  @override
  State<NoteEditorPage> createState() => NoteEditorPageState();
}

class NoteEditorPageState extends State<NoteEditorPage>
    with WidgetsBindingObserver {
  static const Duration _autosaveDelay = Duration(milliseconds: 800);

  final GlobalKey<_DocumentBlocksEditorState> _documentEditorKey =
      GlobalKey<_DocumentBlocksEditorState>();
  late final TextEditingController _titleController;
  late final _MarkdownEditingController _contentController;
  late final FocusNode _titleFocusNode;
  late final FocusNode _contentFocusNode;
  Note? _persistedNote;
  _EditorSnapshot? _lastPersistedSnapshot;
  Timer? _autosaveTimer;
  bool _isSaving = false;
  bool _saveQueued = false;
  bool _isClosing = false;
  bool _isApplyingExternalNoteUpdate = false;
  String? _saveErrorMessage;
  TextSelection _lastKnownContentSelection =
      const TextSelection.collapsed(offset: 0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _titleController = TextEditingController(text: widget.note?.title ?? '');
    final initialContent =
        widget.note == null ? '' : _editableContentForNote(widget.note!);
    _contentController = _MarkdownEditingController(
      text: initialContent,
    );
    _contentController.clearHistory();
    _lastKnownContentSelection = _contentController.selection.isValid
        ? _contentController.selection
        : TextSelection.collapsed(offset: initialContent.length);
    _titleFocusNode = FocusNode();
    _contentFocusNode = FocusNode(skipTraversal: true);
    _persistedNote = widget.note;
    _lastPersistedSnapshot =
        widget.note == null ? null : _snapshotFromNote(widget.note!);
    _titleController.addListener(_handleTextChanged);
    _contentController.addListener(_handleTextChanged);
    _titleFocusNode.addListener(_handleEditorFocusChanged);
    _contentFocusNode.addListener(_handleEditorFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _notifyStatusChanged();
    });
  }

  @override
  void dispose() {
    widget.onStatusChanged?.call(const NoteEditorStatusSnapshot.hidden());
    WidgetsBinding.instance.removeObserver(this);
    _autosaveTimer?.cancel();
    _titleController.removeListener(_handleTextChanged);
    _contentController.removeListener(_handleTextChanged);
    _titleFocusNode.removeListener(_handleEditorFocusChanged);
    _contentFocusNode.removeListener(_handleEditorFocusChanged);
    _titleController.dispose();
    _contentController.dispose();
    _titleFocusNode.dispose();
    _contentFocusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant NoteEditorPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    final incomingNote = widget.note;
    if (incomingNote == null) {
      return;
    }

    final incomingSnapshot = _snapshotFromNote(incomingNote);
    final lastPersistedSnapshot = _lastPersistedSnapshot;
    final persistedNote = _persistedNote;
    final isSamePersistedSnapshot = persistedNote?.id == incomingNote.id &&
        lastPersistedSnapshot == incomingSnapshot;

    if (isSamePersistedSnapshot) {
      _persistedNote = incomingNote;
      _notifyStatusChanged();
      return;
    }

    if (_hasUnsavedChanges) {
      return;
    }

    _applyExternalNoteUpdate(
      incomingNote,
      snapshot: incomingSnapshot,
    );
  }

  void _handleTextChanged() {
    if (_isApplyingExternalNoteUpdate) {
      return;
    }

    if (_contentController.selection.isValid) {
      _lastKnownContentSelection = _contentController.selection;
    }

    _autosaveTimer?.cancel();
    if (_hasUnsavedChanges) {
      _autosaveTimer = Timer(_autosaveDelay, () {
        unawaited(_flushPendingChanges());
      });
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _saveErrorMessage = null;
    });
  }

  void _handleEditorFocusChanged() {
    if (mounted) {
      setState(() {});
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      if (!_titleFocusNode.hasFocus && !_contentFocusNode.hasFocus) {
        unawaited(_flushPendingChanges());
      }
    });
  }

  void _handleContentTap() {
    return;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_flushPendingChanges());
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isEditing ? 'Edit Note' : 'New Note';
    final manualTitle = _titleController.text.trim();
    final derivedTitle = deriveTitleFromMarkdown(_contentController.text);
    final effectiveTitle = manualTitle.isNotEmpty ? manualTitle : derivedTitle;
    final isMobileLayout = MediaQuery.sizeOf(context).width < 900;

    final content = Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyS, control: true):
            _SaveNoteIntent(),
        SingleActivator(LogicalKeyboardKey.keyS, meta: true): _SaveNoteIntent(),
        SingleActivator(LogicalKeyboardKey.keyZ, control: true):
            _UndoEditIntent(),
        SingleActivator(LogicalKeyboardKey.keyZ, meta: true): _UndoEditIntent(),
        SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ): _RedoEditIntent(),
        SingleActivator(
          LogicalKeyboardKey.keyZ,
          meta: true,
          shift: true,
        ): _RedoEditIntent(),
        SingleActivator(LogicalKeyboardKey.keyY, control: true):
            _RedoEditIntent(),
        SingleActivator(LogicalKeyboardKey.keyY, meta: true): _RedoEditIntent(),
        SingleActivator(LogicalKeyboardKey.keyB, control: true):
            _ToggleBoldIntent(),
        SingleActivator(LogicalKeyboardKey.keyB, meta: true):
            _ToggleBoldIntent(),
        SingleActivator(LogicalKeyboardKey.keyI, control: true):
            _ToggleItalicIntent(),
        SingleActivator(LogicalKeyboardKey.keyI, meta: true):
            _ToggleItalicIntent(),
        SingleActivator(LogicalKeyboardKey.digit1, control: true):
            _ApplyHeadingIntent(1),
        SingleActivator(LogicalKeyboardKey.digit1, meta: true):
            _ApplyHeadingIntent(1),
        SingleActivator(LogicalKeyboardKey.digit2, control: true):
            _ApplyHeadingIntent(2),
        SingleActivator(LogicalKeyboardKey.digit2, meta: true):
            _ApplyHeadingIntent(2),
        SingleActivator(LogicalKeyboardKey.digit3, control: true):
            _ApplyHeadingIntent(3),
        SingleActivator(LogicalKeyboardKey.digit3, meta: true):
            _ApplyHeadingIntent(3),
        SingleActivator(LogicalKeyboardKey.escape): _CloseEditorIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _SaveNoteIntent: CallbackAction<_SaveNoteIntent>(
            onInvoke: (_) {
              if (_isSaving) {
                return null;
              }
              return _flushPendingChanges();
            },
          ),
          _ApplyHeadingIntent: CallbackAction<_ApplyHeadingIntent>(
            onInvoke: (intent) {
              _applyHeading(intent.level);
              return null;
            },
          ),
          _UndoEditIntent: CallbackAction<_UndoEditIntent>(
            onInvoke: (_) {
              _undoEdit();
              return null;
            },
          ),
          _RedoEditIntent: CallbackAction<_RedoEditIntent>(
            onInvoke: (_) {
              _redoEdit();
              return null;
            },
          ),
          _ToggleBoldIntent: CallbackAction<_ToggleBoldIntent>(
            onInvoke: (_) {
              _toggleInlineMarkdown('**', placeholder: 'bold text');
              return null;
            },
          ),
          _ToggleItalicIntent: CallbackAction<_ToggleItalicIntent>(
            onInvoke: (_) {
              _toggleInlineMarkdown('*', placeholder: 'italic text');
              return null;
            },
          ),
          _CloseEditorIntent: CallbackAction<_CloseEditorIntent>(
            onInvoke: (_) {
              unawaited(_requestClose());
              return null;
            },
          ),
        },
        child: _NoteEditorContent(
          editorKey: _documentEditorKey,
          title: effectiveTitle.isEmpty ? title : effectiveTitle,
          derivedTitle: derivedTitle,
          manualTitleIsEmpty: manualTitle.isEmpty,
          titleController: _titleController,
          contentController: _contentController,
          titleFocusNode: _titleFocusNode,
          contentFocusNode: _contentFocusNode,
          isSaving: _isSaving,
          status: _saveStatus,
          noteSyncStatus: _persistedNote?.syncStatus,
          canRetrySave: _saveErrorMessage != null,
          embedded: widget.embedded,
          showInlineStatus: widget.showInlineStatus,
          mobileLayout: isMobileLayout,
          mobileTextScale: widget.mobileTextScale,
          mobileFormattingToolbarVisible: _contentFocusNode.hasFocus,
          onRetrySave: _flushPendingChanges,
          undoEdit: _undoEdit,
          redoEdit: _redoEdit,
          applyHeading: _applyHeading,
          toggleBold: () =>
              _toggleInlineMarkdown('**', placeholder: 'bold text'),
          toggleItalic: () =>
              _toggleInlineMarkdown('*', placeholder: 'italic text'),
          toggleChecklist: _toggleChecklist,
          toggleBulletList: _toggleBulletList,
          toggleQuote: _toggleQuote,
          insertCodeSnippet: _insertCodeSnippet,
          attachImage: _attachImageFromFile,
          deleteAttachmentFile: _deleteAttachmentFileWithConfirmation,
          onContentTap: _handleContentTap,
        ),
      ),
    );

    if (widget.embedded) {
      return content;
    }

    return WillPopScope(
      onWillPop: _handleWillPop,
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: SafeArea(
          child: isMobileLayout
              ? content
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: content,
                ),
        ),
      ),
    );
  }

  _EditorSnapshot get _currentSnapshot {
    final manualTitle = _titleController.text.trim();
    final content = _contentController.text;
    return _EditorSnapshot(
      manualTitle: manualTitle,
      title:
          manualTitle.isEmpty ? deriveTitleFromMarkdown(content) : manualTitle,
      content: content,
      folderPath: _effectiveFolderPath,
    );
  }

  _EditorSnapshot _snapshotFromNote(Note note) {
    final editableContent = _editableContentForNote(note);
    return _EditorSnapshot(
      manualTitle: note.title,
      title: note.title,
      content: editableContent,
      folderPath: note.folderPath,
    );
  }

  String _editableContentForNote(Note note) {
    final editableText = editableTextFromDocument(note.document);
    return editableText.isEmpty ? note.content : editableText;
  }

  void _applyExternalNoteUpdate(
    Note note, {
    required _EditorSnapshot snapshot,
  }) {
    final clampedTitleSelection = TextSelection.collapsed(
      offset: math
          .min(_titleController.selection.baseOffset, note.title.length)
          .clamp(0, note.title.length),
    );
    final content = snapshot.content;
    final currentContentSelection = _contentController.selection;
    final clampedContentSelection = currentContentSelection.isValid
        ? TextSelection(
            baseOffset: currentContentSelection.baseOffset.clamp(
              0,
              content.length,
            ),
            extentOffset: currentContentSelection.extentOffset.clamp(
              0,
              content.length,
            ),
          )
        : TextSelection.collapsed(offset: content.length);

    _isApplyingExternalNoteUpdate = true;
    try {
      _titleController.value = TextEditingValue(
        text: note.title,
        selection: clampedTitleSelection,
      );
      _contentController.value = TextEditingValue(
        text: content,
        selection: clampedContentSelection,
      );
      _contentController.clearHistory();
      _persistedNote = note;
      _lastPersistedSnapshot = snapshot;
      if (mounted) {
        setState(() {
          _saveErrorMessage = null;
        });
      } else {
        _saveErrorMessage = null;
      }
      _notifyStatusChanged();
    } finally {
      _isApplyingExternalNoteUpdate = false;
    }
  }

  bool get _hasUnsavedChanges {
    final lastPersistedSnapshot = _lastPersistedSnapshot;
    final currentSnapshot = _currentSnapshot;

    if (lastPersistedSnapshot == null) {
      return currentSnapshot.isMeaningfullyNonEmpty;
    }

    return currentSnapshot != lastPersistedSnapshot;
  }

  _EditorSaveStatus get _saveStatus {
    if (_saveErrorMessage != null) {
      return _EditorSaveStatus(
        icon: Icons.error_outline,
        label: _saveErrorMessage!,
        compactLabel: 'Save failed',
        color: Theme.of(context).colorScheme.error,
      );
    }

    if (_isSaving) {
      return _EditorSaveStatus(
        icon: Icons.sync,
        label: 'Saving locally...',
        compactLabel: 'Saving',
        color: Theme.of(context).colorScheme.primary,
      );
    }

    if (_hasUnsavedChanges) {
      return _EditorSaveStatus(
        icon: Icons.edit_outlined,
        label: 'Unsaved changes',
        compactLabel: 'Unsaved',
        color: Theme.of(context).colorScheme.primary,
      );
    }

    if (_persistedNote == null) {
      return _EditorSaveStatus(
        icon: Icons.edit_note_outlined,
        label: 'Start typing to create this note',
        compactLabel: 'Draft',
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );
    }

    return _EditorSaveStatus(
      icon: Icons.check_circle_outline,
      label: 'All changes saved',
      compactLabel: 'Saved locally',
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }

  NoteEditorStatusSnapshot get _statusSnapshot {
    final saveStatus = _saveStatus;
    return NoteEditorStatusSnapshot(
      saveIcon: saveStatus.icon,
      saveLabel: saveStatus.label,
      saveCompactLabel: saveStatus.compactLabel,
      saveColor: saveStatus.color,
      showSaveBadge: _shouldShowSaveBadge,
      noteSyncStatus: _persistedNote?.syncStatus,
      visible: widget.embedded && !widget.showInlineStatus,
    );
  }

  bool get _shouldShowSaveBadge {
    if (_saveErrorMessage != null || _isSaving || _hasUnsavedChanges) {
      return true;
    }

    return _persistedNote == null;
  }

  Future<bool> _flushPendingChanges() async {
    _autosaveTimer?.cancel();
    final snapshot = _currentSnapshot;
    if (!_shouldPersistSnapshot(snapshot)) {
      if (mounted) {
        setState(() {
          _saveErrorMessage = null;
        });
      }
      _notifyStatusChanged();
      return true;
    }

    _saveQueued = true;
    if (_isSaving) {
      return true;
    }

    var completedSuccessfully = true;
    if (mounted) {
      setState(() {
        _isSaving = true;
        _saveErrorMessage = null;
      });
    } else {
      _isSaving = true;
      _saveErrorMessage = null;
    }

    try {
      while (_saveQueued) {
        _saveQueued = false;
        final pendingSnapshot = _currentSnapshot;
        if (!_shouldPersistSnapshot(pendingSnapshot)) {
          continue;
        }

        try {
          final savedNote = await _persistSnapshot(pendingSnapshot);
          _persistedNote = savedNote;
          _lastPersistedSnapshot = _snapshotFromNote(savedNote);
          widget.onPersisted?.call(savedNote);

          if (mounted) {
            setState(() {
              _saveErrorMessage = null;
            });
          } else {
            _saveErrorMessage = null;
          }
        } catch (_) {
          completedSuccessfully = false;
          if (mounted) {
            setState(() {
              _saveErrorMessage = 'Autosave failed';
            });
          } else {
            _saveErrorMessage = 'Autosave failed';
          }
          break;
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      } else {
        _isSaving = false;
      }
      _notifyStatusChanged();
    }

    return completedSuccessfully;
  }

  bool _shouldPersistSnapshot(_EditorSnapshot snapshot) {
    final lastPersistedSnapshot = _lastPersistedSnapshot;
    if (lastPersistedSnapshot == null) {
      return snapshot.isMeaningfullyNonEmpty;
    }

    return snapshot != lastPersistedSnapshot;
  }

  Future<Note> _persistSnapshot(_EditorSnapshot snapshot) async {
    final persistedNote = _persistedNote;
    if (persistedNote == null) {
      return widget.createNote(
        title: snapshot.title,
        content: snapshot.content,
        folderPath: snapshot.folderPath,
      );
    }

    return widget.updateNote(
      original: persistedNote,
      title: snapshot.title,
      content: snapshot.content,
      folderPath: snapshot.folderPath,
    );
  }

  Future<bool> _handleWillPop() async {
    final savedSuccessfully = await _flushPendingChanges();
    if (!savedSuccessfully) {
      return false;
    }

    return true;
  }

  Future<int> _countAttachmentReferences(String attachmentUri) async {
    final persistedCount = countAttachmentReferencesInText(
      _persistedNote?.content ?? '',
      attachmentUri,
    );
    final currentCount = countAttachmentReferencesInText(
      _contentController.text,
      attachmentUri,
    );
    final repositoryCount =
        await widget.noteRepository.countAttachmentReferences(
      attachmentUri,
    );

    return math.max(0, repositoryCount - persistedCount + currentCount);
  }

  Future<bool> _deleteAttachmentFileWithConfirmation(
      String attachmentUri) async {
    final fileName = attachmentFileNameFromUri(attachmentUri) ?? attachmentUri;
    final referenceCount = await _countAttachmentReferences(attachmentUri);
    if (!mounted) {
      return false;
    }

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) {
            final willUseTrash =
                !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;
            final referenceLabel = referenceCount == 1
                ? 'There is currently 1 link pointing to this file.'
                : 'There are currently $referenceCount links pointing to this file.';

            return AlertDialog(
              title: const Text('Delete file'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Are you sure you want to delete "$fileName"?'),
                  const SizedBox(height: 12),
                  Text(
                    willUseTrash
                        ? 'It will be moved to your system trash when possible.'
                        : 'It will be deleted from local app storage.',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    referenceLabel,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Delete'),
                ),
              ],
            );
          },
        ) ??
        false;
    if (!confirmed) {
      return false;
    }

    final result = await deleteAttachmentFile(attachmentUri);
    if (!mounted) {
      return result.existed;
    }

    setState(() {});
    final messenger = ScaffoldMessenger.of(context);
    final message = !result.existed
        ? '$fileName was already missing.'
        : result.movedToTrash
            ? '$fileName moved to trash.'
            : '$fileName deleted from local storage.';
    messenger.showSnackBar(SnackBar(content: Text(message)));
    return result.existed;
  }

  Future<void> _requestClose() async {
    if (_isClosing) {
      return;
    }

    if (mounted) {
      setState(() {
        _isClosing = true;
      });
    } else {
      _isClosing = true;
    }

    try {
      final savedSuccessfully = await _flushPendingChanges();
      if (!savedSuccessfully) {
        return;
      }

      _closeEditor();
    } finally {
      if (mounted) {
        setState(() {
          _isClosing = false;
        });
      } else {
        _isClosing = false;
      }
    }
  }

  @visibleForTesting
  Future<void> debugRequestClose() => _requestClose();

  Future<bool> flushPendingChanges() => _flushPendingChanges();

  void _notifyStatusChanged() {
    final callback = widget.onStatusChanged;
    if (!mounted || callback == null) {
      return;
    }

    final snapshot = _statusSnapshot;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      callback(snapshot);
    });
  }

  @visibleForTesting
  void debugSetBodySelection(TextSelection selection) {
    final clampedSelection = TextSelection(
      baseOffset: selection.baseOffset.clamp(0, _contentController.text.length),
      extentOffset:
          selection.extentOffset.clamp(0, _contentController.text.length),
    );
    _contentController.selection = clampedSelection;
    _lastKnownContentSelection = clampedSelection;

    if (_documentEditorKey.currentState case final editor?) {
      editor.debugSetPrimaryParagraphSelection(clampedSelection);
    }
  }

  void _applyHeading(int level) {
    _applySelectedLinesTransform((lines) {
      final nonEmptyLines = lines.where((line) => line.trim().isNotEmpty);
      final allAlreadyAtLevel = nonEmptyLines.isNotEmpty &&
          nonEmptyLines.every(
            (line) => line.trimLeft().startsWith('${'#' * level} '),
          );

      return lines.map((line) {
        if (line.trim().isEmpty) {
          return line;
        }

        final indent = _leadingWhitespace(line);
        final withoutHeading =
            line.trimLeft().replaceFirst(RegExp(r'^#{1,6}\s+'), '');

        if (allAlreadyAtLevel) {
          return '$indent$withoutHeading'.trimRight();
        }

        final prefix = '${'#' * level} ';
        return '$indent$prefix$withoutHeading'.trimRight();
      }).toList(growable: false);
    });
  }

  void _toggleBulletList() {
    _applySelectedLinesTransform((lines) {
      final nonEmptyLines =
          lines.where((line) => line.trim().isNotEmpty).toList(growable: false);
      final allBulleted = nonEmptyLines.isNotEmpty &&
          nonEmptyLines.every((line) => line.trimLeft().startsWith('- '));

      return lines.map((line) {
        if (line.trim().isEmpty) {
          return allBulleted ? line : '${_leadingWhitespace(line)}- ';
        }

        final indent = _leadingWhitespace(line);
        final trimmed = line.trimLeft();
        if (allBulleted) {
          return '$indent${trimmed.substring(2)}';
        }
        return '$indent- $trimmed';
      }).toList(growable: false);
    });
  }

  void _toggleChecklist() {
    _applySelectedLinesTransform((lines) {
      final nonEmptyLines =
          lines.where((line) => line.trim().isNotEmpty).toList(growable: false);
      final allChecklistItems = nonEmptyLines.isNotEmpty &&
          nonEmptyLines.every((line) => _parseTaskListLine(line) != null);

      return lines.map((line) {
        if (line.trim().isEmpty) {
          return allChecklistItems ? line : '${_leadingWhitespace(line)}- [ ] ';
        }

        final indent = _leadingWhitespace(line);
        final trimmed = line.trimLeft();
        final taskMatch = _parseTaskListLine(line);

        if (allChecklistItems && taskMatch != null) {
          return '$indent${taskMatch.content}'.trimRight();
        }

        final bulletMatch = RegExp(r'^-\s+(.*)$').firstMatch(trimmed);
        final content = taskMatch?.content ?? bulletMatch?.group(1) ?? trimmed;
        return '$indent- [ ] $content'.trimRight();
      }).toList(growable: false);
    });
  }

  void _toggleQuote() {
    _applySelectedLinesTransform((lines) {
      final nonEmptyLines =
          lines.where((line) => line.trim().isNotEmpty).toList(growable: false);
      final allQuoted = nonEmptyLines.isNotEmpty &&
          nonEmptyLines.every((line) => line.trimLeft().startsWith('> '));

      return lines.map((line) {
        if (line.trim().isEmpty) {
          return line;
        }

        final indent = _leadingWhitespace(line);
        final trimmed = line.trimLeft();
        if (allQuoted) {
          return '$indent${trimmed.substring(2)}';
        }
        return '$indent> $trimmed';
      }).toList(growable: false);
    });
  }

  void _toggleInlineMarkdown(
    String marker, {
    required String placeholder,
  }) {
    final text = _contentController.text;
    final rawSelection = _validSelection(text);
    final collapsedSpan = rawSelection.isCollapsed
        ? _enclosingInlineMarkdownContentRange(
            text,
            marker: marker,
            cursorOffset: rawSelection.extentOffset.clamp(0, text.length),
          )
        : null;
    final selection = collapsedSpan ??
        (rawSelection.isCollapsed
            ? (_collapsedSelectionForCurrentWord(
                  text,
                  cursorOffset: rawSelection.extentOffset.clamp(0, text.length),
                ) ??
                rawSelection)
            : rawSelection);
    final start =
        math.min(selection.start, selection.end).clamp(0, text.length);
    final end = math.max(selection.start, selection.end).clamp(0, text.length);
    final hasSelectedContent = start != end;

    if (rawSelection.isCollapsed &&
        collapsedSpan == null &&
        !hasSelectedContent) {
      final replacement = '$marker$placeholder$marker';
      final updatedText = text.replaceRange(start, end, replacement);
      final placeholderStart = start + marker.length;
      _contentFocusNode.requestFocus();
      _contentController.value = TextEditingValue(
        text: updatedText,
        selection: TextSelection(
          baseOffset: placeholderStart,
          extentOffset: placeholderStart + placeholder.length,
        ),
      );
      return;
    }

    final isWrappedSelection = start >= marker.length &&
        end + marker.length <= text.length &&
        text.substring(start - marker.length, start) == marker &&
        text.substring(end, end + marker.length) == marker;
    final updatedText = isWrappedSelection
        ? text.replaceRange(start - marker.length, end + marker.length,
            text.substring(start, end))
        : text.replaceRange(
            start, end, '$marker${text.substring(start, end)}$marker');
    _contentFocusNode.requestFocus();
    _contentController.value = TextEditingValue(
      text: updatedText,
      selection: TextSelection(
        baseOffset:
            isWrappedSelection ? start - marker.length : start + marker.length,
        extentOffset:
            isWrappedSelection ? end - marker.length : end + marker.length,
      ),
    );
  }

  TextSelection? _collapsedSelectionForCurrentWord(
    String text, {
    required int cursorOffset,
  }) {
    if (text.isEmpty) {
      return null;
    }

    int? anchorIndex;
    if (cursorOffset < text.length &&
        _isInlineWordCharacter(text[cursorOffset])) {
      anchorIndex = cursorOffset;
    } else if (cursorOffset > 0 &&
        _isInlineWordCharacter(text[cursorOffset - 1])) {
      anchorIndex = cursorOffset - 1;
    }

    if (anchorIndex == null) {
      return null;
    }

    var start = anchorIndex;
    var end = anchorIndex + 1;
    while (start > 0 && _isInlineWordCharacter(text[start - 1])) {
      start -= 1;
    }
    while (end < text.length && _isInlineWordCharacter(text[end])) {
      end += 1;
    }

    return TextSelection(baseOffset: start, extentOffset: end);
  }

  TextSelection? _enclosingInlineMarkdownContentRange(
    String text, {
    required String marker,
    required int cursorOffset,
  }) {
    if (text.isEmpty || cursorOffset < 0 || cursorOffset > text.length) {
      return null;
    }

    final openingSearchStart =
        (cursorOffset - marker.length).clamp(0, text.length);
    final openingStart = text.lastIndexOf(marker, openingSearchStart);
    if (openingStart == -1) {
      return null;
    }

    final contentStart = openingStart + marker.length;
    final closingStart = text.indexOf(marker, contentStart);
    if (closingStart == -1 || closingStart < cursorOffset) {
      return null;
    }

    if (cursorOffset < contentStart || contentStart == closingStart) {
      return null;
    }

    return TextSelection(
      baseOffset: contentStart,
      extentOffset: closingStart,
    );
  }

  bool _isInlineWordCharacter(String character) {
    return RegExp(r'[A-Za-z0-9_]').hasMatch(character);
  }

  void _insertCodeSnippet() {
    if (_documentEditorKey.currentState case final editor?) {
      editor.insertCodeBlock();
      return;
    }

    _contentFocusNode.requestFocus();
    final text = _contentController.text;
    final selection = _validSelection(text);
    final selectedText = selection.textInside(text);
    final replacement =
        selectedText.isEmpty ? '```\n\n```' : '```\n$selectedText\n```';
    final updatedText =
        selection.textBefore(text) + replacement + selection.textAfter(text);
    final cursorOffset = selectedText.isEmpty
        ? selection.start + 4
        : selection.start + replacement.length;

    _contentController.value = TextEditingValue(
      text: updatedText,
      selection: TextSelection.collapsed(offset: cursorOffset),
    );
  }

  Future<void> _attachImageFromFile() async {
    const imageTypes = XTypeGroup(
      label: 'images',
      extensions: <String>['png', 'jpg', 'jpeg', 'gif', 'webp'],
      mimeTypes: <String>[
        'image/png',
        'image/jpeg',
        'image/gif',
        'image/webp',
      ],
    );

    XFile? file;
    try {
      file = await openFile(
        acceptedTypeGroups: const <XTypeGroup>[imageTypes],
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the image picker.')),
      );
      return;
    }

    if (file == null) {
      return;
    }

    final fileName = file.name;
    final extensionIndex = fileName.lastIndexOf('.');
    final extension = extensionIndex == -1
        ? 'png'
        : fileName.substring(extensionIndex + 1).toLowerCase();

    try {
      final bytes = await file.readAsBytes();
      final savedImage = await saveAttachmentImageBytes(
        bytes,
        extension: extension,
      );
      final markdown = buildAttachmentImageMarkdown(savedImage.attachmentUri);
      final replacement = _normalizeImageInsertion(markdown);
      _replaceSelectionWithText(replacement);
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not attach the selected image.')),
      );
    }
  }

  String _normalizeImageInsertion(String markdown) {
    final text = _contentController.text;
    final selection = _contentController.selection;
    final start = selection.start.clamp(0, text.length);
    final end = selection.end.clamp(0, text.length);
    final needsLeadingBreak = start > 0 && text[start - 1] != '\n';
    final trailingBreak = end < text.length && text[end] == '\n' ? '' : '\n';

    return '${needsLeadingBreak ? '\n' : ''}$markdown$trailingBreak';
  }

  void _replaceSelectionWithText(String replacement) {
    final text = _contentController.text;
    final selection = _validSelection(text);
    final start =
        math.min(selection.start, selection.end).clamp(0, text.length);
    final end = math.max(selection.start, selection.end).clamp(0, text.length);
    final updatedText = text.replaceRange(start, end, replacement);
    final nextOffset = start + replacement.length;

    _contentController.value = TextEditingValue(
      text: updatedText,
      selection: TextSelection.collapsed(offset: nextOffset),
    );
    _contentFocusNode.requestFocus();
  }

  void _applySelectedLinesTransform(
    List<String> Function(List<String> lines) transform,
  ) {
    _contentFocusNode.requestFocus();
    final text = _contentController.text;
    final selection = _validSelection(text);
    final blockStart = _lineStartForOffset(text, selection.start);
    final blockEnd = _lineEndForSelection(text, selection);
    final originalBlock = text.substring(blockStart, blockEnd);
    final originalLines = originalBlock.split('\n');
    final updatedLines = transform(originalLines);
    final updatedBlock = updatedLines.join('\n');
    final updatedText = text.replaceRange(blockStart, blockEnd, updatedBlock);

    final updatedSelection = selection.isCollapsed
        ? TextSelection.collapsed(
            offset:
                (selection.start + (updatedBlock.length - originalBlock.length))
                    .clamp(0, updatedText.length),
          )
        : TextSelection(
            baseOffset: blockStart,
            extentOffset:
                (blockStart + updatedBlock.length).clamp(0, updatedText.length),
          );

    _contentController.value = TextEditingValue(
      text: updatedText,
      selection: updatedSelection,
    );
  }

  int _lineStartForOffset(String text, int offset) {
    final safeOffset = offset.clamp(0, text.length);
    if (safeOffset == 0) {
      return 0;
    }
    return text.lastIndexOf('\n', safeOffset - 1) + 1;
  }

  int _lineEndForSelection(String text, TextSelection selection) {
    if (text.isEmpty) {
      return 0;
    }

    final anchorOffset = selection.isCollapsed
        ? selection.end
        : (selection.end > selection.start && text[selection.end - 1] == '\n'
            ? selection.end - 1
            : selection.end);
    final safeOffset = anchorOffset.clamp(0, text.length);
    final nextBreak = text.indexOf('\n', safeOffset);
    return nextBreak == -1 ? text.length : nextBreak;
  }

  TextSelection _validSelection(String text) {
    final selection = _contentController.selection;
    if (!_contentFocusNode.hasFocus && _lastKnownContentSelection.isValid) {
      return TextSelection(
        baseOffset: _lastKnownContentSelection.baseOffset.clamp(0, text.length),
        extentOffset:
            _lastKnownContentSelection.extentOffset.clamp(0, text.length),
      );
    }
    if (!selection.isValid) {
      return TextSelection(
        baseOffset: _lastKnownContentSelection.baseOffset.clamp(0, text.length),
        extentOffset:
            _lastKnownContentSelection.extentOffset.clamp(0, text.length),
      );
    }
    _lastKnownContentSelection = selection;
    return selection;
  }

  String _leadingWhitespace(String text) {
    final match = RegExp(r'^\s*').firstMatch(text);
    return match?.group(0) ?? '';
  }

  void _undoEdit() {
    _contentFocusNode.requestFocus();
    _contentController.undo();
  }

  void _redoEdit() {
    _contentFocusNode.requestFocus();
    _contentController.redo();
  }

  String? get _effectiveFolderPath =>
      _persistedNote?.folderPath ?? widget.initialFolderPath;

  void _closeEditor() {
    if (widget.onClose case final onClose?) {
      onClose();
      return;
    }

    Navigator.of(context).maybePop();
  }
}

class _NoteEditorContent extends StatelessWidget {
  const _NoteEditorContent({
    required this.editorKey,
    required this.title,
    required this.derivedTitle,
    required this.manualTitleIsEmpty,
    required this.titleController,
    required this.titleFocusNode,
    required this.contentController,
    required this.contentFocusNode,
    required this.isSaving,
    required this.status,
    required this.noteSyncStatus,
    required this.canRetrySave,
    required this.embedded,
    required this.showInlineStatus,
    required this.mobileLayout,
    required this.mobileTextScale,
    required this.mobileFormattingToolbarVisible,
    required this.onRetrySave,
    required this.undoEdit,
    required this.redoEdit,
    required this.applyHeading,
    required this.toggleBold,
    required this.toggleItalic,
    required this.toggleChecklist,
    required this.toggleBulletList,
    required this.toggleQuote,
    required this.insertCodeSnippet,
    required this.attachImage,
    required this.deleteAttachmentFile,
    required this.onContentTap,
  });

  final GlobalKey<_DocumentBlocksEditorState> editorKey;
  final String title;
  final String derivedTitle;
  final bool manualTitleIsEmpty;
  final TextEditingController titleController;
  final FocusNode titleFocusNode;
  final _MarkdownEditingController contentController;
  final FocusNode contentFocusNode;
  final bool isSaving;
  final _EditorSaveStatus status;
  final SyncStatus? noteSyncStatus;
  final bool canRetrySave;
  final bool embedded;
  final bool showInlineStatus;
  final bool mobileLayout;
  final double mobileTextScale;
  final bool mobileFormattingToolbarVisible;
  final Future<bool> Function() onRetrySave;
  final VoidCallback undoEdit;
  final VoidCallback redoEdit;
  final void Function(int level) applyHeading;
  final VoidCallback toggleBold;
  final VoidCallback toggleItalic;
  final VoidCallback toggleChecklist;
  final VoidCallback toggleBulletList;
  final VoidCallback toggleQuote;
  final VoidCallback insertCodeSnippet;
  final Future<void> Function() attachImage;
  final Future<bool> Function(String attachmentUri) deleteAttachmentFile;
  final VoidCallback onContentTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDesktopEmbedded = embedded;
    final isMobile = mobileLayout;
    final mobileBodyStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
          fontSize: 15.0 * mobileTextScale,
          height: 1.5,
        );
    final mobileTitleStyle =
        Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontSize: 26.0 * mobileTextScale,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.0,
              height: 1.02,
            );

    return Column(
      children: [
        TextField(
          controller: titleController,
          focusNode: titleFocusNode,
          decoration: isDesktopEmbedded
              ? const InputDecoration(
                  hintText: 'Untitled',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                )
              : isMobile
                  ? const InputDecoration(
                      hintText: 'Untitled',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    )
                  : const InputDecoration(
                      labelText: 'Title',
                      helperText:
                          'Optional. Leave empty to use the first Markdown heading.',
                      border: OutlineInputBorder(),
                    ),
          style: isDesktopEmbedded
              ? Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  )
              : isMobile
                  ? mobileTitleStyle
                  : null,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => contentFocusNode.requestFocus(),
        ),
        if (manualTitleIsEmpty && derivedTitle.isNotEmpty) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Title will default to: $derivedTitle',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
        if (showInlineStatus) ...[
          SizedBox(height: isMobile ? 10 : 12),
          _EditorStatusStrip(
            saveStatus: status,
            noteSyncStatus: noteSyncStatus,
            canRetrySave: canRetrySave,
            isSaving: isSaving,
            onRetrySave: onRetrySave,
            mobileLayout: isMobile,
          ),
          SizedBox(height: isMobile ? 8 : 16),
        ] else
          const SizedBox(height: 12),
        if (!isDesktopEmbedded && !isMobile)
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _EditorCommandButton(
                  label: 'H1',
                  onPressed: () => applyHeading(1),
                ),
                _EditorCommandButton(
                  label: 'H2',
                  onPressed: () => applyHeading(2),
                ),
                _EditorCommandButton(
                  label: 'H3',
                  onPressed: () => applyHeading(3),
                ),
                _EditorCommandButton(
                  label: 'Bold',
                  onPressed: toggleBold,
                ),
                _EditorCommandButton(
                  label: 'Italic',
                  onPressed: toggleItalic,
                ),
                _EditorCommandButton(
                  label: 'Checklist',
                  onPressed: toggleChecklist,
                ),
                _EditorCommandButton(
                  label: 'List',
                  onPressed: toggleBulletList,
                ),
                _EditorCommandButton(
                  label: 'Quote',
                  onPressed: toggleQuote,
                ),
              ],
            ),
          ),
        SizedBox(height: isDesktopEmbedded ? 8 : (isMobile ? 4 : 16)),
        Expanded(
          child: DecoratedBox(
            decoration: isMobile
                ? const BoxDecoration()
                : BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(20),
                  ),
            child: _MarkdownEditorPane(
              controller: contentController,
              documentEditorKey: editorKey,
              focusNode: contentFocusNode,
              embedded: embedded,
              mobileLayout: mobileLayout,
              mobileTextScale: mobileTextScale,
              mobileBodyStyle: mobileBodyStyle,
              deleteAttachmentFile: deleteAttachmentFile,
              onTap: onContentTap,
            ),
          ),
        ),
        SizedBox(height: isMobile ? 12 : 16),
        if (isMobile)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: mobileFormattingToolbarVisible
                ? _MobileEditorToolbar(
                    key: const ValueKey('mobile-editor-toolbar'),
                    undoEdit: undoEdit,
                    redoEdit: redoEdit,
                    toggleBold: toggleBold,
                    toggleItalic: toggleItalic,
                    toggleChecklist: toggleChecklist,
                    toggleBulletList: toggleBulletList,
                    toggleQuote: toggleQuote,
                    insertCodeSnippet: insertCodeSnippet,
                    attachImage: attachImage,
                  )
                : const SizedBox.shrink(
                    key: ValueKey('mobile-editor-toolbar-hidden')),
          )
        else
          const SizedBox.shrink(),
      ],
    );
  }
}

class _MobileEditorToolbar extends StatelessWidget {
  const _MobileEditorToolbar({
    super.key,
    required this.undoEdit,
    required this.redoEdit,
    required this.toggleBold,
    required this.toggleItalic,
    required this.toggleChecklist,
    required this.toggleBulletList,
    required this.toggleQuote,
    required this.insertCodeSnippet,
    required this.attachImage,
  });

  final VoidCallback undoEdit;
  final VoidCallback redoEdit;
  final VoidCallback toggleBold;
  final VoidCallback toggleItalic;
  final VoidCallback toggleChecklist;
  final VoidCallback toggleBulletList;
  final VoidCallback toggleQuote;
  final VoidCallback insertCodeSnippet;
  final Future<void> Function() attachImage;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                _MobileToolbarButton(
                  tooltip: 'Undo',
                  icon: Icons.undo_rounded,
                  onPressed: undoEdit,
                ),
                _MobileToolbarButton(
                  tooltip: 'Redo',
                  icon: Icons.redo_rounded,
                  onPressed: redoEdit,
                ),
                _MobileToolbarDivider(color: colorScheme.outlineVariant),
                _MobileToolbarButton(
                  tooltip: 'Bold',
                  icon: Icons.format_bold_rounded,
                  onPressed: toggleBold,
                ),
                _MobileToolbarButton(
                  tooltip: 'Italic',
                  icon: Icons.format_italic_rounded,
                  onPressed: toggleItalic,
                ),
                _MobileToolbarButton(
                  tooltip: 'Checklist',
                  icon: Icons.check_box_outlined,
                  onPressed: toggleChecklist,
                ),
                _MobileToolbarButton(
                  tooltip: 'Bullet list',
                  icon: Icons.format_list_bulleted_rounded,
                  onPressed: toggleBulletList,
                ),
                _MobileToolbarDivider(color: colorScheme.outlineVariant),
                _MobileToolbarButton(
                  tooltip: 'Quote',
                  icon: Icons.format_quote_rounded,
                  onPressed: toggleQuote,
                ),
                _MobileToolbarButton(
                  tooltip: 'Code block',
                  icon: Icons.data_object_rounded,
                  onPressed: insertCodeSnippet,
                ),
                _MobileToolbarButton(
                  tooltip: 'Attach image',
                  icon: Icons.image_outlined,
                  onPressed: () {
                    attachImage();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EditorStatusStrip extends StatelessWidget {
  const _EditorStatusStrip({
    required this.saveStatus,
    required this.noteSyncStatus,
    required this.canRetrySave,
    required this.isSaving,
    required this.onRetrySave,
    required this.mobileLayout,
  });

  final _EditorSaveStatus saveStatus;
  final SyncStatus? noteSyncStatus;
  final bool canRetrySave;
  final bool isSaving;
  final Future<bool> Function() onRetrySave;
  final bool mobileLayout;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        _EditorStatusBadge(
          icon: saveStatus.icon,
          label: mobileLayout ? saveStatus.compactLabel : saveStatus.label,
          foregroundColor: saveStatus.color,
          backgroundColor: saveStatus.color.withValues(alpha: 0.12),
          borderColor: saveStatus.color.withValues(alpha: 0.2),
        ),
        if (noteSyncStatus != null)
          _NoteSyncBadge(
            status: noteSyncStatus!,
            compact: mobileLayout,
          ),
        if (canRetrySave)
          TextButton(
            onPressed: isSaving ? null : onRetrySave,
            child: const Text('Retry'),
          ),
      ],
    );
  }
}

class _EditorStatusBadge extends StatelessWidget {
  const _EditorStatusBadge({
    required this.icon,
    required this.label,
    required this.foregroundColor,
    required this.backgroundColor,
    required this.borderColor,
  });

  final IconData icon;
  final String label;
  final Color foregroundColor;
  final Color backgroundColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: foregroundColor,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: foregroundColor,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _NoteSyncBadge extends StatelessWidget {
  const _NoteSyncBadge({
    required this.status,
    required this.compact,
  });

  final SyncStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (label, compactLabel, icon, foregroundColor, backgroundColor) =
        switch (status) {
      SyncStatus.synced => (
          'Synced',
          'Synced',
          Icons.cloud_done_outlined,
          colorScheme.onSecondaryContainer,
          colorScheme.secondaryContainer,
        ),
      SyncStatus.pendingUpload => (
          'Not synced',
          'Not synced',
          Icons.cloud_upload_outlined,
          colorScheme.onPrimaryContainer,
          colorScheme.primaryContainer,
        ),
      SyncStatus.pendingDelete => (
          'Not synced',
          'Not synced',
          Icons.delete_outline,
          colorScheme.onErrorContainer,
          colorScheme.errorContainer,
        ),
      SyncStatus.conflicted => (
          'Not synced',
          'Not synced',
          Icons.warning_amber_outlined,
          colorScheme.onTertiaryContainer,
          colorScheme.tertiaryContainer,
        ),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: foregroundColor,
          ),
          const SizedBox(width: 8),
          Text(
            compact ? compactLabel : label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: foregroundColor,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _MobileToolbarDivider extends StatelessWidget {
  const _MobileToolbarDivider({
    required this.color,
  });

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: color.withValues(alpha: 0.7),
    );
  }
}

class _MobileToolbarButton extends StatelessWidget {
  const _MobileToolbarButton({
    required this.tooltip,
    required this.onPressed,
    this.icon,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final content = Icon(icon, size: 22);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: content,
        splashRadius: 22,
        constraints: const BoxConstraints(
          minWidth: 42,
          minHeight: 42,
        ),
      ),
    );
  }
}

class NoteEditorStatusSnapshot {
  const NoteEditorStatusSnapshot({
    required this.saveIcon,
    required this.saveLabel,
    required this.saveCompactLabel,
    required this.saveColor,
    required this.showSaveBadge,
    required this.noteSyncStatus,
    required this.visible,
  });

  const NoteEditorStatusSnapshot.hidden()
      : saveIcon = Icons.check_circle_outline,
        saveLabel = '',
        saveCompactLabel = '',
        saveColor = Colors.transparent,
        showSaveBadge = false,
        noteSyncStatus = null,
        visible = false;

  final IconData saveIcon;
  final String saveLabel;
  final String saveCompactLabel;
  final Color saveColor;
  final bool showSaveBadge;
  final SyncStatus? noteSyncStatus;
  final bool visible;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is NoteEditorStatusSnapshot &&
        other.saveIcon == saveIcon &&
        other.saveLabel == saveLabel &&
        other.saveCompactLabel == saveCompactLabel &&
        other.saveColor == saveColor &&
        other.showSaveBadge == showSaveBadge &&
        other.noteSyncStatus == noteSyncStatus &&
        other.visible == visible;
  }

  @override
  int get hashCode => Object.hash(
        saveIcon,
        saveLabel,
        saveCompactLabel,
        saveColor,
        showSaveBadge,
        noteSyncStatus,
        visible,
      );
}

class _EditorSaveStatus {
  const _EditorSaveStatus({
    required this.icon,
    required this.label,
    required this.compactLabel,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String compactLabel;
  final Color color;
}

class _EditorSnapshot {
  const _EditorSnapshot({
    required this.manualTitle,
    required this.title,
    required this.content,
    required this.folderPath,
  });

  final String manualTitle;
  final String title;
  final String content;
  final String? folderPath;

  bool get isMeaningfullyNonEmpty =>
      manualTitle.isNotEmpty || content.trim().isNotEmpty;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is _EditorSnapshot &&
        other.title == title &&
        other.content == content &&
        other.folderPath == folderPath;
  }

  @override
  int get hashCode => Object.hash(title, content, folderPath);
}

class _SaveNoteIntent extends Intent {
  const _SaveNoteIntent();
}

class _CloseEditorIntent extends Intent {
  const _CloseEditorIntent();
}

class _ApplyHeadingIntent extends Intent {
  const _ApplyHeadingIntent(this.level);

  final int level;
}

class _ToggleBoldIntent extends Intent {
  const _ToggleBoldIntent();
}

class _ToggleItalicIntent extends Intent {
  const _ToggleItalicIntent();
}

class _UndoEditIntent extends Intent {
  const _UndoEditIntent();
}

class _RedoEditIntent extends Intent {
  const _RedoEditIntent();
}

class _SelectAllDocumentIntent extends Intent {
  const _SelectAllDocumentIntent();
}

class _ClearSelectedDocumentIntent extends Intent {
  const _ClearSelectedDocumentIntent();
}

class _MarkdownEditingController extends TextEditingController {
  _MarkdownEditingController({
    super.text,
    this.onToggleTaskCheckbox,
  });

  ValueChanged<int>? onToggleTaskCheckbox;
  Map<String, Size> attachmentImageSizes = const <String, Size>{};
  double attachmentImageMaxWidth = 320;
  double attachmentImageMaxHeight = 240;
  bool showActiveMarkdownLine = true;
  int? selectedAttachmentLineIndex;
  final List<TextEditingValue> _undoHistory = <TextEditingValue>[];
  final List<TextEditingValue> _redoHistory = <TextEditingValue>[];
  bool _isApplyingHistoryChange = false;

  @override
  set value(TextEditingValue newValue) {
    final previousValue = super.value;
    if (!_isApplyingHistoryChange && previousValue.text != newValue.text) {
      _undoHistory.add(previousValue);
      if (_undoHistory.length > 100) {
        _undoHistory.removeAt(0);
      }
      _redoHistory.clear();
    }
    super.value = newValue;
  }

  bool get canUndo => _undoHistory.isNotEmpty;
  bool get canRedo => _redoHistory.isNotEmpty;

  void undo() {
    if (!canUndo) {
      return;
    }

    final previousValue = _undoHistory.removeLast();
    _redoHistory.add(value);
    _isApplyingHistoryChange = true;
    try {
      super.value = previousValue;
    } finally {
      _isApplyingHistoryChange = false;
    }
  }

  void redo() {
    if (!canRedo) {
      return;
    }

    final nextValue = _redoHistory.removeLast();
    _undoHistory.add(value);
    _isApplyingHistoryChange = true;
    try {
      super.value = nextValue;
    } finally {
      _isApplyingHistoryChange = false;
    }
  }

  void clearHistory() {
    _undoHistory.clear();
    _redoHistory.clear();
  }

  _CodeSnippetSelection? get currentCodeSnippet {
    if (text.isEmpty) {
      return null;
    }

    final selection = value.selection;
    final offset = selection.isValid
        ? selection.extentOffset.clamp(0, text.length)
        : text.length;

    for (final snippet in _parseFencedCodeSnippets(text)) {
      if (snippet.containsOffset(offset)) {
        return _CodeSnippetSelection(
          language: snippet.language,
          code: snippet.code,
        );
      }
    }

    return null;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final baseStyle = style ?? DefaultTextStyle.of(context).style;
    final spans = <InlineSpan>[];
    final lines = text.split('\n');
    var activeLineIndex = showActiveMarkdownLine ? _activeLineIndex : -1;
    if (activeLineIndex == selectedAttachmentLineIndex) {
      activeLineIndex = -1;
    }
    var isInsideCodeSnippet = false;
    var lineStartOffset = 0;

    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final lineState = _classifyCodeSnippetLine(
        line.trim(),
        isInsideCodeSnippet: isInsideCodeSnippet,
      );
      spans.add(
        _buildLineSpan(
          line,
          baseStyle,
          context,
          isActiveLine: index == activeLineIndex,
          isInsideCodeSnippet: lineState.kind == _CodeSnippetLineKind.body,
          isCodeSnippetOpeningTag:
              lineState.kind == _CodeSnippetLineKind.opening,
          isCodeSnippetClosingTag:
              lineState.kind == _CodeSnippetLineKind.closing,
          codeSnippetLanguage: lineState.language,
          lineIndex: index,
          lineStartOffset: lineStartOffset,
        ),
      );
      switch (lineState.kind) {
        case _CodeSnippetLineKind.opening:
          isInsideCodeSnippet = true;
        case _CodeSnippetLineKind.closing:
          isInsideCodeSnippet = false;
        case _CodeSnippetLineKind.body:
        case _CodeSnippetLineKind.none:
          break;
      }
      if (index < lines.length - 1) {
        spans.add(TextSpan(text: '\n', style: baseStyle));
        lineStartOffset += line.length + 1;
      } else {
        lineStartOffset += line.length;
      }
    }

    return TextSpan(style: baseStyle, children: spans);
  }

  TextSpan buildLayoutTextSpan({
    required BuildContext context,
    TextStyle? style,
  }) {
    final baseStyle = style ?? DefaultTextStyle.of(context).style;
    final spans = <InlineSpan>[];
    final lines = text.split('\n');
    var activeLineIndex = showActiveMarkdownLine ? _activeLineIndex : -1;
    if (activeLineIndex == selectedAttachmentLineIndex) {
      activeLineIndex = -1;
    }
    var isInsideCodeSnippet = false;
    var lineStartOffset = 0;

    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final lineState = _classifyCodeSnippetLine(
        line.trim(),
        isInsideCodeSnippet: isInsideCodeSnippet,
      );
      spans.add(
        _buildLayoutLineSpan(
          line,
          baseStyle,
          context,
          isActiveLine: index == activeLineIndex,
          isInsideCodeSnippet: lineState.kind == _CodeSnippetLineKind.body,
          isCodeSnippetOpeningTag:
              lineState.kind == _CodeSnippetLineKind.opening,
          isCodeSnippetClosingTag:
              lineState.kind == _CodeSnippetLineKind.closing,
          codeSnippetLanguage: lineState.language,
          lineIndex: index,
          lineStartOffset: lineStartOffset,
        ),
      );
      switch (lineState.kind) {
        case _CodeSnippetLineKind.opening:
          isInsideCodeSnippet = true;
        case _CodeSnippetLineKind.closing:
          isInsideCodeSnippet = false;
        case _CodeSnippetLineKind.body:
        case _CodeSnippetLineKind.none:
          break;
      }
      if (index < lines.length - 1) {
        spans.add(TextSpan(text: '\n', style: baseStyle));
        lineStartOffset += line.length + 1;
      } else {
        lineStartOffset += line.length;
      }
    }

    return TextSpan(style: baseStyle, children: spans);
  }

  InlineSpan _buildLineSpan(
    String line,
    TextStyle baseStyle,
    BuildContext context, {
    required bool isActiveLine,
    required bool isInsideCodeSnippet,
    required bool isCodeSnippetOpeningTag,
    required bool isCodeSnippetClosingTag,
    required String codeSnippetLanguage,
    required int lineIndex,
    required int lineStartOffset,
  }) {
    if (isActiveLine) {
      final activeHeadingSpan = _buildActiveHeadingLineSpan(
        line,
        baseStyle: baseStyle,
        colorScheme: Theme.of(context).colorScheme,
      );
      if (activeHeadingSpan != null) {
        return activeHeadingSpan;
      }
      return TextSpan(text: line, style: baseStyle);
    }

    return TextSpan(
      children: buildInactiveMarkdownLineSpans(
        line,
        baseStyle: baseStyle,
        colorScheme: Theme.of(context).colorScheme,
        isInsideCodeSnippet: isInsideCodeSnippet,
        isCodeSnippetOpeningTag: isCodeSnippetOpeningTag,
        isCodeSnippetClosingTag: isCodeSnippetClosingTag,
        codeSnippetLanguage: codeSnippetLanguage,
        taskCheckboxBuilder: onToggleTaskCheckbox == null
            ? null
            : (taskMatch) => _buildTaskCheckboxSpan(
                  taskMatch: taskMatch,
                  baseStyle: baseStyle,
                  lineIndex: lineIndex,
                  checkedCharacterOffset:
                      lineStartOffset + taskMatch.checkedCharacterIndex,
                ),
        attachmentImageBuilder: (image) => _buildAttachmentPlaceholderSpan(
          image,
          baseStyle: baseStyle,
        ),
      ),
    );
  }

  InlineSpan _buildLayoutLineSpan(
    String line,
    TextStyle baseStyle,
    BuildContext context, {
    required bool isActiveLine,
    required bool isInsideCodeSnippet,
    required bool isCodeSnippetOpeningTag,
    required bool isCodeSnippetClosingTag,
    required String codeSnippetLanguage,
    required int lineIndex,
    required int lineStartOffset,
  }) {
    if (isActiveLine) {
      final activeHeadingSpan = _buildActiveHeadingLineSpan(
        line,
        baseStyle: baseStyle,
        colorScheme: Theme.of(context).colorScheme,
      );
      if (activeHeadingSpan != null) {
        return activeHeadingSpan;
      }
      return TextSpan(text: line, style: baseStyle);
    }

    return TextSpan(
      children: buildInactiveMarkdownLineSpans(
        line,
        baseStyle: baseStyle,
        colorScheme: Theme.of(context).colorScheme,
        isInsideCodeSnippet: isInsideCodeSnippet,
        isCodeSnippetOpeningTag: isCodeSnippetOpeningTag,
        isCodeSnippetClosingTag: isCodeSnippetClosingTag,
        codeSnippetLanguage: codeSnippetLanguage,
        taskCheckboxBuilder: (taskMatch) => TextSpan(
          text: taskMatch.markerText,
          style: _hiddenMarkdownMarkerWidthPreservingStyle(baseStyle),
        ),
        attachmentImageBuilder: (image) => _buildAttachmentPlaceholderSpan(
          image,
          baseStyle: baseStyle,
        ),
      ),
    );
  }

  InlineSpan _buildTaskCheckboxSpan({
    required _TaskListLineMatch taskMatch,
    required TextStyle baseStyle,
    required int lineIndex,
    required int checkedCharacterOffset,
  }) {
    final checkboxSize =
        (((baseStyle.fontSize ?? 16) * 0.95).clamp(16.0, 18.0)) as double;
    final markerPrefix = taskMatch.markerText.substring(0, 3);
    final markerSuffix = taskMatch.markerText.substring(4);

    return TextSpan(
      children: [
        TextSpan(
          text: markerPrefix,
          style: _hiddenMarkdownMarkerStyle(baseStyle),
        ),
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _TaskCheckboxInline(
            key: ValueKey('task-checkbox-overlay-$lineIndex'),
            checked: taskMatch.checked,
            size: checkboxSize,
            onTap: () => onToggleTaskCheckbox?.call(checkedCharacterOffset),
          ),
        ),
        TextSpan(
          text: markerSuffix,
          style: _hiddenMarkdownMarkerStyle(baseStyle),
        ),
      ],
    );
  }

  InlineSpan _buildAttachmentPlaceholderSpan(
    AttachmentImageMarkdown image, {
    required TextStyle baseStyle,
  }) {
    return TextSpan(
      text: _attachmentPlaceholderText(
        rawLength: math.max(1, image.rawText.length),
        lineHeight: (baseStyle.fontSize ?? 16) * (baseStyle.height ?? 1.2),
        previewBlockHeight: _attachmentPreviewBlockHeight(
          image.attachmentUri,
          attachmentImageSizes: attachmentImageSizes,
          attachmentImageMaxWidth: attachmentImageMaxWidth,
          attachmentImageMaxHeight: attachmentImageMaxHeight,
        ),
      ),
      style: _hiddenMarkdownMarkerWidthPreservingStyle(baseStyle),
    );
  }

  InlineSpan? _buildActiveHeadingLineSpan(
    String line, {
    required TextStyle baseStyle,
    required ColorScheme colorScheme,
  }) {
    final trimmedLeft = line.trimLeft();
    final headingMatch = RegExp(r'^(#{1,3})(\s+)(.*)$').firstMatch(trimmedLeft);
    if (headingMatch == null) {
      return null;
    }

    final level = headingMatch.group(1)!.length;
    final headingStyle = _inactiveHeadingStyle(baseStyle, level);

    return TextSpan(
      text: line,
      style: headingStyle.copyWith(color: colorScheme.onSurface),
    );
  }

  int get _activeLineIndex {
    final selection = value.selection;
    if (!selection.isValid) {
      return text.split('\n').length - 1;
    }

    final safeOffset = selection.extentOffset.clamp(0, text.length);
    return '\n'.allMatches(text.substring(0, safeOffset)).length;
  }
}

double _attachmentPreviewBlockHeight(
  String attachmentUri, {
  required Map<String, Size> attachmentImageSizes,
  required double attachmentImageMaxWidth,
  required double attachmentImageMaxHeight,
}) {
  return _attachmentDisplaySize(
        attachmentUri,
        attachmentImageSizes: attachmentImageSizes,
        maxWidth: attachmentImageMaxWidth,
        maxHeight: attachmentImageMaxHeight,
      ).height +
      _UnifiedMarkdownEditorState._imagePreviewVerticalInset;
}

String _attachmentPlaceholderText({
  required int rawLength,
  required double lineHeight,
  required double previewBlockHeight,
}) {
  if (rawLength <= 1) {
    return ' ';
  }

  final targetLineCount = math.max(1, (previewBlockHeight / lineHeight).ceil());
  final maxLineBreaks = math.max(0, rawLength - 2);
  final lineBreakCount = math.min(targetLineCount - 1, maxLineBreaks);
  final fillerCount = rawLength - lineBreakCount - 2;

  return ' ' +
      ('\n' * lineBreakCount) +
      ' ' +
      ('\u200B' * math.max(0, fillerCount));
}

Size _attachmentDisplaySize(
  String attachmentUri, {
  required Map<String, Size> attachmentImageSizes,
  required double maxWidth,
  required double maxHeight,
}) {
  final intrinsic = attachmentImageSizes[attachmentUri];
  final safeMaxWidth = math.max(1.0, maxWidth);
  final safeMaxHeight = math.max(1.0, maxHeight);
  final fallback = const Size(
    _UnifiedMarkdownEditorState._imagePreviewFallbackWidth,
    _UnifiedMarkdownEditorState._imagePreviewFallbackHeight,
  );
  final source =
      intrinsic == null || intrinsic.width <= 0 || intrinsic.height <= 0
          ? fallback
          : intrinsic;

  final widthScale = safeMaxWidth / source.width;
  final heightScale = safeMaxHeight / source.height;
  final scale = math.min(1.0, math.min(widthScale, heightScale));
  return Size(source.width * scale, source.height * scale);
}

@visibleForTesting
List<InlineSpan> buildInactiveMarkdownLineSpans(
  String line, {
  required TextStyle baseStyle,
  required ColorScheme colorScheme,
  bool isInsideCodeSnippet = false,
  bool isCodeSnippetOpeningTag = false,
  bool isCodeSnippetClosingTag = false,
  String codeSnippetLanguage = '',
  InlineSpan Function(_TaskListLineMatch taskMatch)? taskCheckboxBuilder,
  InlineSpan Function(AttachmentImageMarkdown image)? attachmentImageBuilder,
}) {
  if (isCodeSnippetOpeningTag ||
      isCodeSnippetClosingTag ||
      isInsideCodeSnippet) {
    return _buildInactiveCodeSnippetLineSpans(
      line,
      baseStyle: baseStyle,
      colorScheme: colorScheme,
      isCodeSnippetOpeningTag: isCodeSnippetOpeningTag,
      isCodeSnippetClosingTag: isCodeSnippetClosingTag,
      codeSnippetLanguage: codeSnippetLanguage,
    );
  }

  final trimmedLeft = line.trimLeft();
  final indent = line.substring(0, line.length - trimmedLeft.length);

  final imageMatch = parseAttachmentImageMarkdownLine(line);
  if (imageMatch != null) {
    return [
      attachmentImageBuilder?.call(imageMatch) ??
          TextSpan(
            text: imageMatch.rawText,
            style: _hiddenMarkdownMarkerWidthPreservingStyle(baseStyle),
          ),
    ];
  }

  final taskMatch = _parseTaskListLine(line);
  if (taskMatch != null) {
    return [
      if (taskMatch.indent.isNotEmpty)
        TextSpan(text: taskMatch.indent, style: baseStyle),
      taskCheckboxBuilder?.call(taskMatch) ??
          TextSpan(
            text: taskMatch.markerText,
            style: _hiddenMarkdownMarkerWidthPreservingStyle(baseStyle),
          ),
      if (taskMatch.content.isNotEmpty)
        ..._buildInactiveInlineMarkdownSpans(
          taskMatch.content,
          baseStyle: baseStyle.copyWith(color: colorScheme.onSurface),
          colorScheme: colorScheme,
        ),
    ];
  }

  final headingMatch = RegExp(r'^(#{1,3})(\s+)(.*)$').firstMatch(trimmedLeft);
  if (headingMatch != null) {
    final hashes = headingMatch.group(1)!;
    final spacing = headingMatch.group(2)!;
    final content = headingMatch.group(3)!;
    final level = hashes.length;
    final headingStyle = _inactiveHeadingStyle(baseStyle, level);

    return [
      if (indent.isNotEmpty) TextSpan(text: indent, style: baseStyle),
      TextSpan(
        text: '$hashes$spacing',
        style: _hiddenMarkdownMarkerStyle(headingStyle),
      ),
      ..._buildInactiveInlineMarkdownSpans(
        content,
        baseStyle: headingStyle.copyWith(color: colorScheme.onSurface),
        colorScheme: colorScheme,
      ),
    ];
  }

  final bulletMatch = RegExp(r'^(\s*)-\s+(.*)$').firstMatch(line);
  if (bulletMatch != null) {
    final bulletIndent = bulletMatch.group(1)!;
    final content = bulletMatch.group(2)!;
    final bulletStyle = baseStyle.copyWith(
      color: colorScheme.onSurface,
      fontWeight: FontWeight.w700,
    );

    return [
      if (bulletIndent.isNotEmpty)
        TextSpan(text: bulletIndent, style: baseStyle),
      TextSpan(text: '• ', style: bulletStyle),
      ..._buildInactiveInlineMarkdownSpans(
        content,
        baseStyle: baseStyle.copyWith(color: colorScheme.onSurface),
        colorScheme: colorScheme,
      ),
    ];
  }

  final quoteMatch = RegExp(r'^(\s*)>\s?(.*)$').firstMatch(line);
  if (quoteMatch != null) {
    final quoteIndent = quoteMatch.group(1)!;
    final content = quoteMatch.group(2)!;
    final quoteMarkerStyle = baseStyle.copyWith(
      color: colorScheme.primary,
      fontWeight: FontWeight.w700,
    );

    return [
      if (quoteIndent.isNotEmpty) TextSpan(text: quoteIndent, style: baseStyle),
      TextSpan(text: '│ ', style: quoteMarkerStyle),
      ..._buildInactiveInlineMarkdownSpans(
        content,
        baseStyle: baseStyle.copyWith(
          color: colorScheme.onSurface,
          fontStyle: FontStyle.italic,
        ),
        colorScheme: colorScheme,
      ),
    ];
  }

  return _buildInactiveInlineMarkdownSpans(
    line,
    baseStyle: baseStyle.copyWith(color: colorScheme.onSurface),
    colorScheme: colorScheme,
  );
}

TextStyle _inactiveHeadingStyle(TextStyle baseStyle, int level) {
  return switch (level) {
    1 => baseStyle.copyWith(
        fontSize: (baseStyle.fontSize ?? 16) * 1.7,
        fontWeight: FontWeight.w800,
        height: 1.2,
      ),
    2 => baseStyle.copyWith(
        fontSize: (baseStyle.fontSize ?? 16) * 1.35,
        fontWeight: FontWeight.w700,
        height: 1.28,
      ),
    _ => baseStyle.copyWith(
        fontSize: (baseStyle.fontSize ?? 16) * 1.15,
        fontWeight: FontWeight.w700,
        height: 1.35,
      ),
  };
}

List<InlineSpan> _buildInactiveCodeSnippetLineSpans(
  String line, {
  required TextStyle baseStyle,
  required ColorScheme colorScheme,
  required bool isCodeSnippetOpeningTag,
  required bool isCodeSnippetClosingTag,
  required String codeSnippetLanguage,
}) {
  final trimmedLeft = line.trimLeft();
  final indent = line.substring(0, line.length - trimmedLeft.length);
  final chipStyle = baseStyle.copyWith(
    color: colorScheme.primary,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.5,
  );
  final codeStyle = baseStyle.copyWith(color: colorScheme.onSurface);

  if (isCodeSnippetOpeningTag) {
    return [
      if (indent.isNotEmpty) TextSpan(text: indent, style: baseStyle),
      TextSpan(
        text: codeSnippetLanguage.isEmpty ? '```' : '```$codeSnippetLanguage',
        style: chipStyle,
      ),
    ];
  }

  if (isCodeSnippetClosingTag) {
    return [
      if (indent.isNotEmpty) TextSpan(text: indent, style: baseStyle),
      TextSpan(text: '```', style: chipStyle),
    ];
  }

  return [
    if (indent.isNotEmpty) TextSpan(text: indent, style: baseStyle),
    TextSpan(text: trimmedLeft, style: codeStyle),
  ];
}

List<InlineSpan> _buildInactiveInlineMarkdownSpans(
  String text, {
  required TextStyle baseStyle,
  required ColorScheme colorScheme,
}) {
  final spans = <InlineSpan>[];
  final pattern = RegExp(
    r'((?<!`)`[^`\n]+`(?!`)|\*\*[^*\n]+\*\*|\*[^*\n]+\*)',
  );
  var currentIndex = 0;

  for (final match in pattern.allMatches(text)) {
    if (match.start > currentIndex) {
      spans.add(
        TextSpan(
          text: text.substring(currentIndex, match.start),
          style: baseStyle,
        ),
      );
    }

    final token = match.group(0)!;
    final marker = token.startsWith('**')
        ? '**'
        : token.startsWith('`')
            ? '`'
            : '*';
    final content =
        token.substring(marker.length, token.length - marker.length);

    spans.add(
      TextSpan(
        text: marker,
        style: _hiddenMarkdownMarkerStyle(baseStyle),
      ),
    );
    spans.add(
      TextSpan(
        text: content,
        style: token.startsWith('**')
            ? baseStyle.copyWith(fontWeight: FontWeight.w700)
            : token.startsWith('`')
                ? baseStyle.copyWith(
                    backgroundColor: colorScheme.surfaceContainerHighest,
                  )
                : baseStyle.copyWith(fontStyle: FontStyle.italic),
      ),
    );
    spans.add(
      TextSpan(
        text: marker,
        style: _hiddenMarkdownMarkerStyle(baseStyle),
      ),
    );

    currentIndex = match.end;
  }

  if (currentIndex < text.length) {
    spans.add(TextSpan(text: text.substring(currentIndex), style: baseStyle));
  }

  return spans;
}

TextStyle _hiddenMarkdownMarkerStyle(TextStyle baseStyle) {
  return baseStyle.copyWith(
    color: Colors.transparent,
    fontSize: 0.1,
    height: 1,
  );
}

TextStyle _hiddenMarkdownMarkerWidthPreservingStyle(TextStyle baseStyle) {
  return baseStyle.copyWith(color: Colors.transparent);
}

class _TaskListLineMatch {
  const _TaskListLineMatch({
    required this.indent,
    required this.checked,
    required this.markerText,
    required this.content,
    required this.checkboxTokenStartIndex,
    required this.checkedCharacterIndex,
  });

  final String indent;
  final bool checked;
  final String markerText;
  final String content;
  final int checkboxTokenStartIndex;
  final int checkedCharacterIndex;
}

_TaskListLineMatch? _parseTaskListLine(String line) {
  final match = RegExp(r'^(\s*)- \[( |x|X)\](?:\s|$)').firstMatch(line);
  if (match == null) {
    return null;
  }

  return _TaskListLineMatch(
    indent: match.group(1)!,
    checked: (match.group(2) ?? '').toLowerCase() == 'x',
    markerText: line.substring(match.group(1)!.length, match.end),
    content: line.substring(match.end),
    checkboxTokenStartIndex: match.group(1)!.length + 2,
    checkedCharacterIndex: match.group(1)!.length + 3,
  );
}

class _CodeSnippetSelection {
  const _CodeSnippetSelection({
    required this.language,
    required this.code,
  });

  final String language;
  final String code;
}

class _FencedCodeSnippet {
  const _FencedCodeSnippet({
    required this.language,
    required this.code,
    required this.startOffset,
    required this.codeStartOffset,
    required this.closingStartOffset,
    required this.endOffset,
  });

  final String language;
  final String code;
  final int startOffset;
  final int codeStartOffset;
  final int closingStartOffset;
  final int endOffset;

  bool containsOffset(int offset) {
    return offset >= startOffset && offset <= endOffset;
  }
}

enum _CodeSnippetLineKind {
  none,
  opening,
  body,
  closing,
}

class _CodeSnippetLineState {
  const _CodeSnippetLineState({
    required this.kind,
    this.language = '',
  });

  final _CodeSnippetLineKind kind;
  final String language;
}

_CodeSnippetLineState _classifyCodeSnippetLine(
  String line, {
  required bool isInsideCodeSnippet,
}) {
  if (isInsideCodeSnippet) {
    if (_isFencedCodeSnippetDelimiter(line)) {
      return const _CodeSnippetLineState(kind: _CodeSnippetLineKind.closing);
    }
    return const _CodeSnippetLineState(kind: _CodeSnippetLineKind.body);
  }

  final language = _codeSnippetLanguage(line);
  if (language != null) {
    return _CodeSnippetLineState(
      kind: _CodeSnippetLineKind.opening,
      language: language,
    );
  }

  return const _CodeSnippetLineState(kind: _CodeSnippetLineKind.none);
}

bool _isCodeSnippetClosingTag(String line) {
  return _isFencedCodeSnippetDelimiter(line);
}

String? _codeSnippetLanguage(String line) {
  final fencedMatch = RegExp(r'^```([^\s`]+)?$').firstMatch(line);
  if (fencedMatch != null) {
    return fencedMatch.group(1)?.trim() ?? '';
  }
  return null;
}

bool _isFencedCodeSnippetDelimiter(String line) {
  return RegExp(r'^```([^\s`]+)?$').hasMatch(line);
}

List<_FencedCodeSnippet> _parseFencedCodeSnippets(String text) {
  final lines = text.split('\n');
  if (lines.isEmpty) {
    return const <_FencedCodeSnippet>[];
  }

  final lineStartOffsets = <int>[];
  var offset = 0;
  for (var index = 0; index < lines.length; index++) {
    lineStartOffsets.add(offset);
    offset += lines[index].length;
    if (index < lines.length - 1) {
      offset += 1;
    }
  }

  final snippets = <_FencedCodeSnippet>[];
  var index = 0;
  while (index < lines.length) {
    final openingLine = lines[index].trim();
    final language = _codeSnippetLanguage(openingLine);
    if (language == null) {
      index++;
      continue;
    }

    var closingIndex = -1;
    for (var scan = index + 1; scan < lines.length; scan++) {
      if (_isFencedCodeSnippetDelimiter(lines[scan].trim())) {
        closingIndex = scan;
        break;
      }
    }

    if (closingIndex == -1) {
      index++;
      continue;
    }

    final openingStartOffset = lineStartOffsets[index];
    final openingEndOffset = openingStartOffset + lines[index].length;
    final codeStartOffset =
        closingIndex > index ? openingEndOffset + 1 : openingEndOffset;
    final closingStartOffset = lineStartOffsets[closingIndex];
    final closingEndOffset = closingStartOffset + lines[closingIndex].length;

    snippets.add(
      _FencedCodeSnippet(
        language: language,
        code: lines.sublist(index + 1, closingIndex).join('\n'),
        startOffset: openingStartOffset,
        codeStartOffset: codeStartOffset,
        closingStartOffset: closingStartOffset,
        endOffset: closingEndOffset,
      ),
    );

    index = closingIndex + 1;
  }

  return List<_FencedCodeSnippet>.unmodifiable(snippets);
}

class _MarkdownEditorPane extends StatelessWidget {
  const _MarkdownEditorPane({
    required this.controller,
    required this.documentEditorKey,
    required this.focusNode,
    required this.embedded,
    required this.mobileLayout,
    required this.mobileTextScale,
    required this.mobileBodyStyle,
    required this.deleteAttachmentFile,
    required this.onTap,
  });

  final _MarkdownEditingController controller;
  final GlobalKey<_DocumentBlocksEditorState> documentEditorKey;
  final FocusNode focusNode;
  final bool embedded;
  final bool mobileLayout;
  final double mobileTextScale;
  final TextStyle? mobileBodyStyle;
  final Future<bool> Function(String attachmentUri) deleteAttachmentFile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color:
            embedded ? Colors.transparent : colorScheme.surfaceContainerLowest,
        borderRadius: embedded ? BorderRadius.zero : BorderRadius.circular(16),
        border: embedded ? null : Border.all(color: colorScheme.outlineVariant),
      ),
      child: _UnifiedMarkdownEditor(
        key: const ValueKey('document-block-editor'),
        controller: controller,
        focusNode: focusNode,
        mobileLayout: mobileLayout,
        mobileTextScale: mobileTextScale,
        mobileBodyStyle: mobileBodyStyle,
        deleteAttachmentFile: deleteAttachmentFile,
        onTap: onTap,
      ),
    );
  }
}

class _UnifiedMarkdownEditor extends StatefulWidget {
  const _UnifiedMarkdownEditor({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.mobileLayout,
    required this.mobileTextScale,
    required this.mobileBodyStyle,
    required this.deleteAttachmentFile,
    required this.onTap,
  });

  final _MarkdownEditingController controller;
  final FocusNode focusNode;
  final bool mobileLayout;
  final double mobileTextScale;
  final TextStyle? mobileBodyStyle;
  final Future<bool> Function(String attachmentUri) deleteAttachmentFile;
  final VoidCallback onTap;

  @override
  State<_UnifiedMarkdownEditor> createState() => _UnifiedMarkdownEditorState();
}

class _UnifiedMarkdownEditorState extends State<_UnifiedMarkdownEditor> {
  static const EdgeInsets _editorContentPadding = EdgeInsets.all(18);
  static const double _snippetHorizontalInset = 6;
  static const double _snippetTopInset = 4;
  static const double _imagePreviewFallbackWidth = 320;
  static const double _imagePreviewFallbackHeight = 180;
  static const double _imagePreviewVerticalInset = 8;
  int _selectedSlashCommandIndex = 0;
  late final ScrollController _editorScrollController;
  final Map<String, Size> _attachmentImageSizes = <String, Size>{};
  final Set<String> _loadingAttachmentImageSizes = <String>{};
  _SelectedAttachmentImage? _selectedAttachmentImage;
  TextSelection? _pendingAttachmentTapSelection;
  TextSelection? _lastStableEditorSelection;
  bool _suppressNextEditorTap = false;

  @override
  void initState() {
    super.initState();
    widget.controller.onToggleTaskCheckbox = _toggleTaskCheckboxAt;
    _editorScrollController = ScrollController()
      ..addListener(_handleScrollChanged);
    _lastRenderedText = widget.controller.text;
    _lastRenderedSlashQuery = _slashCommandQuery;
    widget.controller.addListener(_handleControllerChanged);
    widget.focusNode.addListener(_handleFocusChanged);
    _ensureAttachmentImageSizes();
  }

  @override
  void didUpdateWidget(covariant _UnifiedMarkdownEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      oldWidget.controller.onToggleTaskCheckbox = null;
      widget.controller.addListener(_handleControllerChanged);
      widget.controller.onToggleTaskCheckbox = _toggleTaskCheckboxAt;
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_handleFocusChanged);
      widget.focusNode.addListener(_handleFocusChanged);
    }
  }

  @override
  void dispose() {
    _editorScrollController
      ..removeListener(_handleScrollChanged)
      ..dispose();
    widget.controller.onToggleTaskCheckbox = null;
    widget.controller.removeListener(_handleControllerChanged);
    widget.focusNode.removeListener(_handleFocusChanged);
    super.dispose();
  }

  String _lastRenderedText = '';
  String? _lastRenderedSlashQuery;

  void _handleScrollChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handleFocusChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handleControllerChanged() {
    final textChanged = widget.controller.text != _lastRenderedText;
    if (textChanged && _selectedAttachmentImage != null) {
      _clearSelectedAttachmentImage();
    }
    _ensureAttachmentImageSizes();
    _syncSelectedAttachmentImageWithText();
    _rememberStableEditorSelection();
    if (_keepCaretOutOfSelectedAttachmentImage()) {
      return;
    }
    final commands = _matchingSlashCommands;
    final nextIndex = commands.isEmpty
        ? 0
        : _selectedSlashCommandIndex.clamp(0, commands.length - 1);
    final nextSlashQuery = _slashCommandQuery;
    final shouldRebuild = widget.controller.text != _lastRenderedText ||
        nextSlashQuery != _lastRenderedSlashQuery ||
        nextIndex != _selectedSlashCommandIndex;

    _lastRenderedText = widget.controller.text;
    _lastRenderedSlashQuery = nextSlashQuery;
    if (!shouldRebuild) {
      return;
    }

    if (nextIndex != _selectedSlashCommandIndex) {
      setState(() {
        _selectedSlashCommandIndex = nextIndex;
      });
      return;
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _rememberStableEditorSelection() {
    if (_pendingAttachmentTapSelection != null) {
      return;
    }

    final selection = widget.controller.selection;
    if (!selection.isValid) {
      return;
    }

    final selectedImage = _selectedAttachmentImage;
    if (selectedImage != null && selection.isCollapsed) {
      final offset =
          selection.extentOffset.clamp(0, widget.controller.text.length);
      if (offset >= selectedImage.deleteStart &&
          offset < selectedImage.deleteEnd) {
        return;
      }
    }

    _lastStableEditorSelection = selection;
  }

  bool _keepCaretOutOfSelectedAttachmentImage() {
    final selectedImage = _selectedAttachmentImage;
    final selection = widget.controller.selection;
    if (selectedImage == null ||
        !selection.isValid ||
        !selection.isCollapsed ||
        widget.controller.text.isEmpty) {
      return false;
    }

    final offset =
        selection.extentOffset.clamp(0, widget.controller.text.length);
    if (offset == selectedImage.focusOffset ||
        offset < selectedImage.deleteStart ||
        offset >= selectedImage.deleteEnd) {
      return false;
    }

    widget.controller.selection = TextSelection.collapsed(
      offset: selectedImage.focusOffset.clamp(0, widget.controller.text.length),
    );
    return true;
  }

  bool get _isWholeDocumentSelected {
    final selection = widget.controller.selection;
    return selection.isValid &&
        !selection.isCollapsed &&
        selection.start == 0 &&
        selection.end == widget.controller.text.length;
  }

  TextSelection get _selection => widget.controller.selection;

  _LineRange? get _selectedLineRange {
    final selection = _selection;
    if (!selection.isValid || !selection.isCollapsed) {
      return null;
    }

    final text = widget.controller.text;
    final offset = selection.extentOffset.clamp(0, text.length);
    final start = offset == 0
        ? 0
        : (() {
            final lineStart = text.lastIndexOf('\n', offset - 1);
            return lineStart == -1 ? 0 : lineStart + 1;
          })();
    final lineEnd = text.indexOf('\n', offset);
    final end = lineEnd == -1 ? text.length : lineEnd;
    return _LineRange(start: start, end: end);
  }

  String? get _slashCommandQuery {
    final lineRange = _selectedLineRange;
    if (lineRange == null) {
      return null;
    }

    final lineText =
        widget.controller.text.substring(lineRange.start, lineRange.end).trim();
    if (!lineText.startsWith('/')) {
      return null;
    }
    return lineText.substring(1).toLowerCase();
  }

  List<_SlashCommand> get _matchingSlashCommands {
    final query = _slashCommandQuery;
    if (query == null) {
      return const <_SlashCommand>[];
    }

    return _slashCommands
        .where((command) =>
            query.isEmpty ||
            command.label.toLowerCase().contains(query) ||
            command.aliases.any((alias) => alias.contains(query)))
        .toList(growable: false);
  }

  void _applySlashCommand(_SlashCommand command) {
    final lineRange = _selectedLineRange;
    if (lineRange == null) {
      return;
    }

    switch (command.type) {
      case _SlashCommandType.code:
        final text = widget.controller.text;
        const replacement = '```\n\n```';
        final updatedText =
            text.replaceRange(lineRange.start, lineRange.end, replacement);
        final codeStart = lineRange.start + 4;
        widget.controller.value = TextEditingValue(
          text: updatedText,
          selection: TextSelection.collapsed(offset: codeStart),
        );
        _selectedSlashCommandIndex = 0;
        _focusEditorAt(codeStart);
      case _SlashCommandType.checklist:
        final text = widget.controller.text;
        const replacement = '- [ ] ';
        final updatedText =
            text.replaceRange(lineRange.start, lineRange.end, replacement);
        final checklistOffset = lineRange.start + replacement.length;
        widget.controller.value = TextEditingValue(
          text: updatedText,
          selection: TextSelection.collapsed(offset: checklistOffset),
        );
        _selectedSlashCommandIndex = 0;
        _focusEditorAt(checklistOffset);
    }
  }

  void _toggleTaskCheckboxAt(int checkedCharacterOffset) {
    final text = widget.controller.text;
    if (checkedCharacterOffset < 0 || checkedCharacterOffset >= text.length) {
      return;
    }

    final currentMarker = text[checkedCharacterOffset];
    if (currentMarker != ' ' && currentMarker.toLowerCase() != 'x') {
      return;
    }

    final replacement = currentMarker == ' ' ? 'x' : ' ';
    final updatedText = text.replaceRange(
      checkedCharacterOffset,
      checkedCharacterOffset + 1,
      replacement,
    );
    widget.controller.value = widget.controller.value.copyWith(
      text: updatedText,
      selection: widget.controller.selection,
      composing: TextRange.empty,
    );
  }

  Future<void> _handlePasteFromClipboard() async {
    final image = await ClipboardImageService.readImage();
    if (image != null) {
      final savedImage = await saveAttachmentImageBytes(
        image.bytes,
        extension: image.extension,
      );
      final decodedSize = await decodeImageSize(image.bytes);
      if (decodedSize != null && mounted) {
        setState(() {
          _attachmentImageSizes[savedImage.attachmentUri] = decodedSize;
        });
      }
      final markdown = buildAttachmentImageMarkdown(savedImage.attachmentUri);
      final replacement = _normalizeImageInsertion(markdown);
      _replaceSelectionWithText(replacement);
      return;
    }

    final textData = await Clipboard.getData(Clipboard.kTextPlain);
    final pastedText = textData?.text;
    if (pastedText == null || pastedText.isEmpty) {
      return;
    }

    _replaceSelectionWithText(pastedText);
  }

  String _normalizeImageInsertion(String markdown) {
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    final start = selection.start.clamp(0, text.length);
    final end = selection.end.clamp(0, text.length);
    final needsLeadingBreak = start > 0 && text[start - 1] != '\n';
    final trailingBreak = end < text.length && text[end] == '\n' ? '' : '\n';

    return '${needsLeadingBreak ? '\n' : ''}$markdown$trailingBreak';
  }

  void _replaceSelectionWithText(String replacement) {
    _clearSelectedAttachmentImage();
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    final start =
        math.min(selection.start, selection.end).clamp(0, text.length);
    final end = math.max(selection.start, selection.end).clamp(0, text.length);
    final updatedText = text.replaceRange(start, end, replacement);
    final nextOffset = start + replacement.length;

    widget.controller.value = TextEditingValue(
      text: updatedText,
      selection: TextSelection.collapsed(offset: nextOffset),
    );
    _focusEditorAt(nextOffset);
  }

  void _focusEditorAt(int offset) {
    final clampedOffset = offset.clamp(0, widget.controller.text.length);
    widget.controller.selection =
        TextSelection.collapsed(offset: clampedOffset);
    FocusManager.instance.primaryFocus?.unfocus();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      FocusScope.of(context).requestFocus(widget.focusNode);
      widget.focusNode.requestFocus();
      widget.controller.selection =
          TextSelection.collapsed(offset: clampedOffset);
    });
  }

  void _focusEditorPreservingSelection() {
    _focusEditorWithSelection(widget.controller.selection);
  }

  void _focusEditorWithSelection(TextSelection selection) {
    final textLength = widget.controller.text.length;
    final clampedSelection = selection.isValid
        ? TextSelection(
            baseOffset: selection.baseOffset.clamp(0, textLength),
            extentOffset: selection.extentOffset.clamp(0, textLength),
          )
        : TextSelection.collapsed(offset: textLength);

    widget.controller.selection = clampedSelection;
    FocusScope.of(context).requestFocus(widget.focusNode);
    widget.focusNode.requestFocus();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      FocusScope.of(context).requestFocus(widget.focusNode);
      widget.focusNode.requestFocus();
      widget.controller.selection = clampedSelection;
    });
  }

  void _selectAttachmentImage(
    _AttachmentImageOverlayGeometry overlay, {
    TextSelection? preservedSelection,
  }) {
    final selectionData = _prepareAttachmentImageSelection(overlay);
    if (_selectedAttachmentImage?.lineIndex == overlay.lineIndex &&
        _selectedAttachmentImage?.attachmentUri == overlay.attachmentUri) {
      _focusEditorAt(selectionData.focusOffset);
      return;
    }

    setState(() {
      _selectedAttachmentImage = _SelectedAttachmentImage(
        lineIndex: overlay.lineIndex,
        attachmentUri: overlay.attachmentUri,
        deleteStart: selectionData.deleteStart,
        deleteEnd: selectionData.deleteEnd,
        focusOffset: selectionData.focusOffset,
      );
    });
    _focusEditorAt(selectionData.focusOffset);
  }

  _PreparedAttachmentImageSelection _prepareAttachmentImageSelection(
    _AttachmentImageOverlayGeometry overlay,
  ) {
    var deleteStart = overlay.deleteStart;
    var deleteEnd = overlay.deleteEnd;
    var focusOffset = overlay.focusOffset;
    var text = widget.controller.text;

    final lines = text.split('\n');
    final hasAdjacentAttachmentBelow = overlay.lineIndex < lines.length - 1 &&
        parseAttachmentImageMarkdownLine(lines[overlay.lineIndex + 1]) != null;
    if (hasAdjacentAttachmentBelow) {
      final updatedText = text.replaceRange(focusOffset, focusOffset, '\n');
      widget.controller.text = updatedText;
      text = updatedText;
      focusOffset = overlay.focusOffset;
    }

    final isTrailingAttachmentLine = deleteEnd == text.length;
    if (isTrailingAttachmentLine && !text.endsWith('\n')) {
      final updatedText = '$text\n';
      widget.controller.text = updatedText;
      deleteEnd = updatedText.length;
      focusOffset = updatedText.length;
      text = updatedText;
    }

    return _PreparedAttachmentImageSelection(
      deleteStart: deleteStart,
      deleteEnd: deleteEnd,
      focusOffset: focusOffset,
    );
  }

  void _clearSelectedAttachmentImage() {
    if (_selectedAttachmentImage == null) {
      return;
    }
    setState(() {
      _selectedAttachmentImage = null;
    });
  }

  void _syncSelectedAttachmentImageWithText() {
    final selectedImage = _selectedAttachmentImage;
    if (selectedImage == null) {
      return;
    }

    final text = widget.controller.text;
    if (selectedImage.deleteStart < 0 ||
        selectedImage.deleteStart >= text.length ||
        selectedImage.deleteEnd > text.length ||
        selectedImage.deleteStart >= selectedImage.deleteEnd) {
      _selectedAttachmentImage = null;
      return;
    }

    final selectedText =
        text.substring(selectedImage.deleteStart, selectedImage.deleteEnd);
    final lineText = selectedText.replaceFirst(RegExp(r'^\n'), '').replaceFirst(
          RegExp(r'\n$'),
          '',
        );
    final imageMatch = parseAttachmentImageMarkdownLine(lineText);
    if (imageMatch == null ||
        imageMatch.attachmentUri != selectedImage.attachmentUri) {
      _selectedAttachmentImage = null;
    }
  }

  bool _deleteSelectedAttachmentImage() {
    final selectedImage = _selectedAttachmentImage;
    if (selectedImage == null) {
      return false;
    }

    final text = widget.controller.text;
    final deleteStart = selectedImage.deleteStart.clamp(0, text.length);
    final deleteEnd = selectedImage.deleteEnd.clamp(0, text.length);
    if (deleteStart >= deleteEnd) {
      _clearSelectedAttachmentImage();
      return false;
    }

    final updatedText = text.replaceRange(deleteStart, deleteEnd, '');
    final nextOffset = deleteStart.clamp(0, updatedText.length);
    widget.controller.value = TextEditingValue(
      text: updatedText,
      selection: TextSelection.collapsed(offset: nextOffset),
    );
    setState(() {
      _selectedAttachmentImage = null;
    });
    _focusEditorAt(nextOffset);
    return true;
  }

  bool _removeAttachmentReferencesFromCurrentNote(String attachmentUri) {
    final lines = widget.controller.text.split('\n');
    final filteredLines = lines
        .where(
          (line) =>
              parseAttachmentImageMarkdownLine(line)?.attachmentUri !=
              attachmentUri,
        )
        .toList(growable: false);
    if (filteredLines.length == lines.length) {
      return false;
    }

    final updatedText = filteredLines.join('\n');
    final currentSelection = widget.controller.selection;
    final nextOffset = currentSelection.isValid
        ? currentSelection.extentOffset.clamp(0, updatedText.length)
        : updatedText.length;

    _attachmentImageSizes.remove(attachmentUri);
    setState(() {
      _selectedAttachmentImage = null;
    });
    widget.controller.value = TextEditingValue(
      text: updatedText,
      selection: TextSelection.collapsed(offset: nextOffset),
    );
    _focusEditorPreservingSelection();
    return true;
  }

  void _handleEditorTap() {
    if (_suppressNextEditorTap) {
      return;
    }
    _clearSelectedAttachmentImage();
    widget.onTap();
  }

  Future<void> _handleSelectedAttachmentAction(
    _SelectedAttachmentAction action,
    _AttachmentImageOverlayGeometry overlay,
  ) async {
    switch (action) {
      case _SelectedAttachmentAction.removeFromNote:
        _deleteSelectedAttachmentImage();
        return;
      case _SelectedAttachmentAction.deleteFile:
        final deleted =
            await widget.deleteAttachmentFile(overlay.attachmentUri);
        if (!mounted || !deleted) {
          return;
        }
        _removeAttachmentReferencesFromCurrentNote(overlay.attachmentUri);
        return;
    }
  }

  bool _handleCodeFenceWordJump(KeyEvent event) {
    final selection = widget.controller.selection;
    if (!selection.isValid || !selection.isCollapsed) {
      return false;
    }

    final isWordJump = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (!isWordJump ||
        (event.logicalKey != LogicalKeyboardKey.arrowLeft &&
            event.logicalKey != LogicalKeyboardKey.arrowRight)) {
      return false;
    }

    final lineRange = _selectedLineRange;
    if (lineRange == null) {
      return false;
    }

    final lineText =
        widget.controller.text.substring(lineRange.start, lineRange.end);
    if (!_isFencedCodeSnippetDelimiter(lineText.trim())) {
      return false;
    }

    final offset =
        selection.extentOffset.clamp(0, widget.controller.text.length);
    final nextOffset = event.logicalKey == LogicalKeyboardKey.arrowLeft
        ? lineRange.start
        : lineRange.end;
    if (offset == nextOffset) {
      return false;
    }

    widget.controller.selection = TextSelection.collapsed(offset: nextOffset);
    return true;
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final isPasteShortcut = (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed) &&
        event.logicalKey == LogicalKeyboardKey.keyV;
    if (isPasteShortcut) {
      unawaited(_handlePasteFromClipboard());
      return KeyEventResult.handled;
    }

    if ((event.logicalKey == LogicalKeyboardKey.backspace ||
            event.logicalKey == LogicalKeyboardKey.delete) &&
        _deleteSelectedAttachmentImage()) {
      return KeyEventResult.handled;
    }

    if (_isWholeDocumentSelected &&
        (event.logicalKey == LogicalKeyboardKey.backspace ||
            event.logicalKey == LogicalKeyboardKey.delete)) {
      widget.controller.value = const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
      _focusEditorAt(0);
      return KeyEventResult.handled;
    }

    if (_handleCodeFenceWordJump(event)) {
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _clearSelectedAttachmentImage();
      widget.controller.selection = widget.controller.selection.copyWith(
        baseOffset: widget.controller.selection.extentOffset,
      );
      return KeyEventResult.handled;
    }

    final commands = _matchingSlashCommands;
    if (commands.isEmpty) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selectedSlashCommandIndex =
            (_selectedSlashCommandIndex + 1) % commands.length;
      });
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedSlashCommandIndex =
            (_selectedSlashCommandIndex - 1 + commands.length) %
                commands.length;
      });
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _applySlashCommand(commands[_selectedSlashCommandIndex]);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final commands = _matchingSlashCommands;
    final style = widget.mobileLayout
        ? widget.mobileBodyStyle
        : Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final contentWidth = math.max(
                0.0,
                constraints.maxWidth - _editorContentPadding.horizontal,
              );
              final contentHeight = math.max(
                0.0,
                constraints.maxHeight - _editorContentPadding.vertical,
              );
              widget.controller.attachmentImageSizes = _attachmentImageSizes;
              widget.controller.attachmentImageMaxWidth = contentWidth;
              widget.controller.attachmentImageMaxHeight = contentHeight;
              widget.controller.showActiveMarkdownLine =
                  widget.focusNode.hasFocus && _selectedAttachmentImage == null;
              widget.controller.selectedAttachmentLineIndex =
                  _selectedAttachmentImage?.lineIndex;
              final overlayTextSpan = style == null
                  ? null
                  : widget.controller.buildLayoutTextSpan(
                      context: context,
                      style: style,
                    );
              final snippetOverlays = style == null || overlayTextSpan == null
                  ? const <_SnippetOverlayGeometry>[]
                  : _buildSnippetOverlayGeometry(
                      context,
                      text: widget.controller.text,
                      textSpan: overlayTextSpan,
                      maxWidth: constraints.maxWidth,
                      scrollOffset: _editorScrollController.hasClients
                          ? _editorScrollController.offset
                          : 0,
                    );
              final imageOverlays = style == null || overlayTextSpan == null
                  ? const <_AttachmentImageOverlayGeometry>[]
                  : _buildAttachmentImageOverlayGeometry(
                      context,
                      text: widget.controller.text,
                      textSpan: overlayTextSpan,
                      maxWidth: constraints.maxWidth,
                      maxHeight: constraints.maxHeight,
                      activeLineIndex: widget.focusNode.hasFocus &&
                              _selectedAttachmentImage == null &&
                              widget.controller._activeLineIndex !=
                                  _selectedAttachmentImage?.lineIndex
                          ? widget.controller._activeLineIndex
                          : -1,
                      attachmentImageSizes: _attachmentImageSizes,
                      scrollOffset: _editorScrollController.hasClients
                          ? _editorScrollController.offset
                          : 0,
                    );
              return Stack(
                children: [
                  for (final overlay in snippetOverlays)
                    Positioned(
                      left: overlay.left,
                      right: overlay.right,
                      top: overlay.top,
                      height: overlay.height,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: widget.mobileLayout
                                ? Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHigh
                                    .withValues(alpha: 0.76)
                                : Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(
                              widget.mobileLayout ? 20 : 14,
                            ),
                            border: Border.all(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant
                                  .withValues(
                                    alpha: widget.mobileLayout ? 0.38 : 0.7,
                                  ),
                            ),
                            boxShadow: widget.mobileLayout
                                ? [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.03),
                                      blurRadius: 14,
                                      offset: const Offset(0, 8),
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      ),
                    ),
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTapDown: (details) {
                        final tappedAttachmentPreview = imageOverlays.any(
                          (overlay) => Rect.fromLTWH(
                            overlay.left,
                            overlay.top,
                            overlay.hitboxWidth,
                            overlay.height,
                          ).contains(details.localPosition),
                        );
                        if (tappedAttachmentPreview) {
                          return;
                        }
                        _clearSelectedAttachmentImage();
                        if (widget.controller.text.isEmpty) {
                          _focusEditorAt(0);
                        }
                      },
                      child: Focus(
                        canRequestFocus: false,
                        skipTraversal: true,
                        onKeyEvent: (_, event) => _handleKeyEvent(event),
                        child: TextField(
                          controller: widget.controller,
                          focusNode: widget.focusNode,
                          scrollController: _editorScrollController,
                          onTap: _handleEditorTap,
                          inputFormatters: const [
                            _MarkdownListEditingFormatter(),
                          ],
                          decoration: const InputDecoration(
                            hintText:
                                '# Untitled note\n\nStart writing in Markdown...',
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: _editorContentPadding,
                          ),
                          style: style,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          textAlignVertical: TextAlignVertical.top,
                          minLines: null,
                          maxLines: null,
                          expands: true,
                        ),
                      ),
                    ),
                  ),
                  for (final overlay in imageOverlays)
                    Positioned(
                      left: overlay.left,
                      top: overlay.top,
                      width: overlay.hitboxWidth,
                      height: overlay.height,
                      child: MouseRegion(
                        key: ValueKey(
                          'attachment-image-hitbox-${overlay.lineIndex}',
                        ),
                        cursor: SystemMouseCursors.basic,
                        opaque: false,
                        child: Listener(
                          behavior: HitTestBehavior.opaque,
                          onPointerDown: (event) {
                            _pendingAttachmentTapSelection =
                                TextSelection.collapsed(
                              offset: overlay.focusOffset,
                            );
                            if (event.kind == PointerDeviceKind.mouse &&
                                event.buttons == kPrimaryMouseButton) {
                              _suppressNextEditorTap = true;
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                _suppressNextEditorTap = false;
                              });
                              _selectAttachmentImage(overlay);
                            }
                          },
                          onPointerUp: (_) {},
                          onPointerCancel: (_) {
                            _pendingAttachmentTapSelection = null;
                          },
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapCancel: () {
                              _pendingAttachmentTapSelection = null;
                            },
                            onTap: () {
                              final preservedSelection =
                                  _pendingAttachmentTapSelection;
                              _pendingAttachmentTapSelection = null;
                              _suppressNextEditorTap = true;
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                _suppressNextEditorTap = false;
                              });
                              _selectAttachmentImage(
                                overlay,
                                preservedSelection: preservedSelection,
                              );
                            },
                            onSecondaryTap: _clearSelectedAttachmentImage,
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: _UnifiedMarkdownEditorState
                                          ._imagePreviewVerticalInset /
                                      2,
                                ),
                                child: AttachmentImagePreview(
                                  key: ValueKey(
                                    'attachment-image-overlay-${overlay.lineIndex}',
                                  ),
                                  attachmentUri: overlay.attachmentUri,
                                  altText: overlay.altText,
                                  maxWidth: overlay.previewWidth,
                                  maxHeight: overlay.previewHeight,
                                  ignorePointer: true,
                                  selected:
                                      _selectedAttachmentImage?.lineIndex ==
                                          overlay.lineIndex,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  for (final overlay in imageOverlays)
                    if (_selectedAttachmentImage?.lineIndex ==
                        overlay.lineIndex)
                      Positioned(
                        top: overlay.top +
                            (_UnifiedMarkdownEditorState
                                    ._imagePreviewVerticalInset /
                                2) +
                            8,
                        left: math.max(
                          overlay.left,
                          overlay.left + overlay.previewWidth - 44,
                        ),
                        child: Material(
                          color: Theme.of(context).colorScheme.surface,
                          elevation: 2,
                          borderRadius: BorderRadius.circular(12),
                          child: PopupMenuButton<_SelectedAttachmentAction>(
                            tooltip: 'Attachment actions',
                            onSelected: (action) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (!mounted) {
                                  return;
                                }
                                unawaited(
                                  _handleSelectedAttachmentAction(
                                    action,
                                    overlay,
                                  ),
                                );
                              });
                            },
                            itemBuilder: (context) => const <PopupMenuEntry<
                                _SelectedAttachmentAction>>[
                              PopupMenuItem<_SelectedAttachmentAction>(
                                value: _SelectedAttachmentAction.removeFromNote,
                                child: Text('Remove from note'),
                              ),
                              PopupMenuItem<_SelectedAttachmentAction>(
                                value: _SelectedAttachmentAction.deleteFile,
                                child: Text('Delete file...'),
                              ),
                            ],
                            icon: const Icon(Icons.more_horiz, size: 18),
                          ),
                        ),
                      ),
                  for (final overlay in snippetOverlays)
                    Positioned(
                      top: overlay.top + 6,
                      right: overlay.right + 6,
                      child: IconButton(
                        tooltip: 'Copy code',
                        style: widget.mobileLayout
                            ? IconButton.styleFrom(
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .surface
                                    .withValues(alpha: 0.92),
                              )
                            : null,
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: overlay.snippet.code),
                          );
                          if (!context.mounted) {
                            return;
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                overlay.snippet.language.isEmpty
                                    ? 'Code snippet copied'
                                    : '${overlay.snippet.language.toUpperCase()} snippet copied',
                              ),
                            ),
                          );
                        },
                        icon: const Icon(
                          Icons.content_copy_outlined,
                          size: 18,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        if (commands.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: _SlashCommandMenu(
              commands: commands,
              selectedIndex: _selectedSlashCommandIndex,
              onSelected: _applySlashCommand,
            ),
          ),
      ],
    );
  }

  void _ensureAttachmentImageSizes() {
    final attachmentUris = widget.controller.text
        .split('\n')
        .map(parseAttachmentImageMarkdownLine)
        .whereType<AttachmentImageMarkdown>()
        .map((image) => image.attachmentUri)
        .toSet();

    for (final attachmentUri in attachmentUris) {
      if (_attachmentImageSizes.containsKey(attachmentUri) ||
          _loadingAttachmentImageSizes.contains(attachmentUri)) {
        continue;
      }
      _loadingAttachmentImageSizes.add(attachmentUri);
      unawaited(_loadAttachmentImageSize(attachmentUri));
    }
  }

  Future<void> _loadAttachmentImageSize(String attachmentUri) async {
    final size = await readAttachmentImageSize(attachmentUri);
    _loadingAttachmentImageSizes.remove(attachmentUri);
    if (!mounted || size == null) {
      return;
    }

    setState(() {
      _attachmentImageSizes[attachmentUri] = size;
    });
  }
}

List<_AttachmentImageOverlayGeometry> _buildAttachmentImageOverlayGeometry(
  BuildContext context, {
  required String text,
  required InlineSpan textSpan,
  required double maxWidth,
  required double maxHeight,
  required int activeLineIndex,
  required Map<String, Size> attachmentImageSizes,
  required double scrollOffset,
}) {
  if (text.isEmpty || maxWidth <= 0) {
    return const <_AttachmentImageOverlayGeometry>[];
  }

  final contentWidth = math.max(
    0.0,
    maxWidth - _UnifiedMarkdownEditorState._editorContentPadding.horizontal,
  );
  final contentHeight = math.max(
    0.0,
    maxHeight - _UnifiedMarkdownEditorState._editorContentPadding.vertical,
  );
  if (contentWidth == 0 || contentHeight == 0) {
    return const <_AttachmentImageOverlayGeometry>[];
  }

  final painter = TextPainter(
    text: textSpan,
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout(maxWidth: contentWidth);

  final overlays = <_AttachmentImageOverlayGeometry>[];
  final lines = text.split('\n');
  var lineStartOffset = 0;
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    final imageMatch = parseAttachmentImageMarkdownLine(line);
    if (imageMatch != null && index != activeLineIndex) {
      if (line.isNotEmpty) {
        final boxes = painter.getBoxesForSelection(
          TextSelection(
            baseOffset: lineStartOffset,
            extentOffset: lineStartOffset + line.length,
          ),
        );
        if (boxes.isNotEmpty) {
          final firstBox = boxes.first;
          final lastBox = boxes.last;
          final displaySize = _attachmentDisplaySize(
            imageMatch.attachmentUri,
            attachmentImageSizes: attachmentImageSizes,
            maxWidth: contentWidth - firstBox.left,
            maxHeight: contentHeight,
          );
          if (displaySize.width > 0) {
            final deleteStart = lineStartOffset;
            final deleteEnd = index < lines.length - 1
                ? lineStartOffset + line.length + 1
                : (lineStartOffset > 0
                    ? lineStartOffset + line.length
                    : line.length);
            final focusOffset = index < lines.length - 1
                ? lineStartOffset + line.length + 1
                : lineStartOffset + line.length;
            overlays.add(
              _AttachmentImageOverlayGeometry(
                lineIndex: index,
                attachmentUri: imageMatch.attachmentUri,
                altText: imageMatch.altText,
                focusOffset: focusOffset,
                deleteStart: index < lines.length - 1
                    ? deleteStart
                    : (lineStartOffset > 0 ? lineStartOffset - 1 : deleteStart),
                deleteEnd: deleteEnd,
                left: firstBox.left +
                    _UnifiedMarkdownEditorState._editorContentPadding.left,
                top: firstBox.top +
                    _UnifiedMarkdownEditorState._editorContentPadding.top -
                    scrollOffset,
                hitboxWidth: contentWidth - firstBox.left,
                previewWidth: displaySize.width,
                height: displaySize.height +
                    _UnifiedMarkdownEditorState._imagePreviewVerticalInset,
                previewHeight: displaySize.height,
              ),
            );
          }
        }
      }
    }

    lineStartOffset += line.length;
    if (index < lines.length - 1) {
      lineStartOffset += 1;
    }
  }

  return List<_AttachmentImageOverlayGeometry>.unmodifiable(overlays);
}

List<_SnippetOverlayGeometry> _buildSnippetOverlayGeometry(
  BuildContext context, {
  required String text,
  required InlineSpan textSpan,
  required double maxWidth,
  required double scrollOffset,
}) {
  if (text.isEmpty || maxWidth <= 0) {
    return const <_SnippetOverlayGeometry>[];
  }

  final snippets = _parseFencedCodeSnippets(text);
  if (snippets.isEmpty) {
    return const <_SnippetOverlayGeometry>[];
  }

  final contentWidth = math.max(0.0,
      maxWidth - _UnifiedMarkdownEditorState._editorContentPadding.horizontal);
  if (contentWidth == 0) {
    return const <_SnippetOverlayGeometry>[];
  }

  final painter = TextPainter(
    text: textSpan,
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout(maxWidth: contentWidth);

  final overlays = <_SnippetOverlayGeometry>[];
  for (final snippet in snippets) {
    final boxes = painter.getBoxesForSelection(
      TextSelection(
        baseOffset: snippet.startOffset,
        extentOffset: snippet.endOffset,
      ),
    );
    if (boxes.isEmpty) {
      continue;
    }

    final topBox = boxes.first;
    final bottomBox = boxes.last;

    final top = topBox.top +
        _UnifiedMarkdownEditorState._editorContentPadding.top -
        scrollOffset -
        _UnifiedMarkdownEditorState._snippetTopInset;
    final bottom = snippetOverlayBottomForClosingFence(
      closingFenceBox: bottomBox,
      contentPaddingTop: _UnifiedMarkdownEditorState._editorContentPadding.top,
      scrollOffset: scrollOffset,
    );

    overlays.add(
      _SnippetOverlayGeometry(
        snippet: snippet,
        left: _UnifiedMarkdownEditorState._snippetHorizontalInset,
        right: _UnifiedMarkdownEditorState._snippetHorizontalInset,
        top: top,
        height: math.max(0, bottom - top),
      ),
    );
  }

  return List<_SnippetOverlayGeometry>.unmodifiable(overlays);
}

@visibleForTesting
double snippetOverlayBottomForClosingFence({
  required TextBox closingFenceBox,
  required double contentPaddingTop,
  required double scrollOffset,
}) {
  return ((closingFenceBox.top + closingFenceBox.bottom) / 2) +
      contentPaddingTop -
      scrollOffset;
}

class _SnippetOverlayGeometry {
  const _SnippetOverlayGeometry({
    required this.snippet,
    required this.left,
    required this.right,
    required this.top,
    required this.height,
  });

  final _FencedCodeSnippet snippet;
  final double left;
  final double right;
  final double top;
  final double height;
}

enum _SelectedAttachmentAction {
  removeFromNote,
  deleteFile,
}

class _AttachmentImageOverlayGeometry {
  const _AttachmentImageOverlayGeometry({
    required this.lineIndex,
    required this.attachmentUri,
    required this.altText,
    required this.focusOffset,
    required this.deleteStart,
    required this.deleteEnd,
    required this.left,
    required this.top,
    required this.hitboxWidth,
    required this.previewWidth,
    required this.height,
    required this.previewHeight,
  });

  final int lineIndex;
  final String attachmentUri;
  final String altText;
  final int focusOffset;
  final int deleteStart;
  final int deleteEnd;
  final double left;
  final double top;
  final double hitboxWidth;
  final double previewWidth;
  final double height;
  final double previewHeight;
}

class _SelectedAttachmentImage {
  const _SelectedAttachmentImage({
    required this.lineIndex,
    required this.attachmentUri,
    required this.deleteStart,
    required this.deleteEnd,
    required this.focusOffset,
  });

  final int lineIndex;
  final String attachmentUri;
  final int deleteStart;
  final int deleteEnd;
  final int focusOffset;
}

class _PreparedAttachmentImageSelection {
  const _PreparedAttachmentImageSelection({
    required this.deleteStart,
    required this.deleteEnd,
    required this.focusOffset,
  });

  final int deleteStart;
  final int deleteEnd;
  final int focusOffset;
}

class _TaskCheckboxInline extends StatelessWidget {
  const _TaskCheckboxInline({
    required this.onTap,
    required this.checked,
    required this.size,
    super.key,
  });

  final VoidCallback onTap;
  final bool checked;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor = colorScheme.onSurface.withValues(alpha: 0.8);
    final fillColor = colorScheme.onSurface.withValues(alpha: 0.82);
    final checkColor = colorScheme.surface;

    return Tooltip(
      message: checked
          ? 'Mark checklist item incomplete'
          : 'Mark checklist item complete',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: size + 8,
            height: size,
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox.square(
                dimension: size,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: checked ? fillColor : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: checked ? fillColor : borderColor,
                      width: 1.8,
                    ),
                  ),
                  child: checked
                      ? Icon(
                          Icons.check,
                          size: size * 0.72,
                          color: checkColor,
                        )
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DocumentBlocksEditor extends StatefulWidget {
  const _DocumentBlocksEditor({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.embedded,
    required this.onTap,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool embedded;
  final VoidCallback onTap;

  @override
  State<_DocumentBlocksEditor> createState() => _DocumentBlocksEditorState();
}

class _DocumentBlocksEditorState extends State<_DocumentBlocksEditor> {
  final List<_DocumentEditorBlock> _blocks = <_DocumentEditorBlock>[];
  bool _syncingFromMaster = false;
  bool _syncingToMaster = false;
  bool _rebuildScheduled = false;
  int? _slashMenuBlockIndex;
  int _selectedSlashCommandIndex = 0;

  @override
  void initState() {
    super.initState();
    _rebuildBlocksFromMasterText();
    HardwareKeyboard.instance.addHandler(_handleHardwareKeyEvent);
    widget.controller.addListener(_handleMasterChanged);
    widget.focusNode.addListener(_handleExternalFocusRequest);
    widget.focusNode.addListener(_syncMasterFromBlocks);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareKeyEvent);
    widget.controller.removeListener(_handleMasterChanged);
    widget.focusNode.removeListener(_handleExternalFocusRequest);
    widget.focusNode.removeListener(_syncMasterFromBlocks);
    for (final block in _blocks) {
      block.dispose();
    }
    super.dispose();
  }

  void _handleMasterChanged() {
    if (_syncingToMaster) {
      return;
    }
    final parsedBlocks = blocksFromEditableText(widget.controller.text);
    if (!_requiresRebuild(parsedBlocks)) {
      _syncBlockTextsFromMaster(parsedBlocks);
      return;
    }
    if (_rebuildScheduled) {
      return;
    }
    _rebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rebuildScheduled = false;
      if (!mounted) {
        return;
      }
      _rebuildBlocksFromMasterText();
    });
  }

  void _rebuildBlocksFromMasterText() {
    final parsedBlocks = blocksFromEditableText(widget.controller.text);
    if (!_requiresRebuild(parsedBlocks)) {
      _syncBlockTextsFromMaster(parsedBlocks);
      _syncSelectionsFromMaster();
      return;
    }

    _syncingFromMaster = true;
    try {
      for (final block in _blocks) {
        block.dispose();
      }
      _blocks
        ..clear()
        ..addAll(
          [
            for (final block in parsedBlocks)
              _DocumentEditorBlock.fromNoteBlock(
                block,
                focusNode: FocusNode(),
              ),
          ],
        );

      for (final block in _blocks) {
        _attachBlockListeners(block);
      }
      _syncSelectionsFromMaster();
    } finally {
      _syncingFromMaster = false;
    }

    if (mounted) {
      setState(() {});
    }
  }

  bool _requiresRebuild(List<NoteBlock> parsedBlocks) {
    final currentStructure = _blocks
        .map((block) => block.structureSignature)
        .toList(growable: false);
    final nextStructure = parsedBlocks
        .map(_DocumentEditorBlock.structureSignatureForNoteBlock)
        .toList(growable: false);
    return !_listEquals(currentStructure, nextStructure);
  }

  void _syncBlockTextsFromMaster(List<NoteBlock> parsedBlocks) {
    _syncingFromMaster = true;
    try {
      for (var index = 0;
          index < _blocks.length && index < parsedBlocks.length;
          index++) {
        _blocks[index].syncFromNoteBlock(parsedBlocks[index]);
      }
    } finally {
      _syncingFromMaster = false;
    }
  }

  void _syncSelectionsFromMaster() {
    final selection = widget.controller.selection;
    final normalizedSelection = selection.isValid
        ? TextSelection(
            baseOffset:
                selection.baseOffset.clamp(0, widget.controller.text.length),
            extentOffset:
                selection.extentOffset.clamp(0, widget.controller.text.length),
          )
        : TextSelection.collapsed(offset: widget.controller.text.length);

    var consumed = 0;
    for (var index = 0; index < _blocks.length; index++) {
      final block = _blocks[index];
      final length = block.rawText.length;
      final isLast = index == _blocks.length - 1;
      final blockEnd = consumed + length;
      final separatorLength = isLast ? 0 : 2;
      final rangeEnd = blockEnd + separatorLength;

      if (normalizedSelection.isCollapsed) {
        final targetOffset = normalizedSelection.extentOffset;
        if (targetOffset <= rangeEnd || isLast) {
          final localOffset = block
              .localSelectionOffset((targetOffset - consumed).clamp(0, length));
          if (block.controller.selection.baseOffset != localOffset ||
              block.controller.selection.extentOffset != localOffset) {
            block.controller.selection =
                TextSelection.collapsed(offset: localOffset);
          }
        } else if (!block.controller.selection.isCollapsed ||
            block.controller.selection.extentOffset != 0) {
          block.controller.selection = const TextSelection.collapsed(offset: 0);
        }
      } else {
        final localBase = block.localSelectionOffset(
          (normalizedSelection.baseOffset - consumed).clamp(0, length),
        );
        final localExtent = block.localSelectionOffset(
          (normalizedSelection.extentOffset - consumed).clamp(0, length),
        );
        final nextSelection = TextSelection(
          baseOffset: localBase,
          extentOffset: localExtent,
        );
        if (block.controller.selection != nextSelection) {
          block.controller.selection = nextSelection;
        }
      }

      consumed = rangeEnd;
    }
  }

  void _syncMasterFromBlocks() {
    if (_syncingFromMaster) {
      return;
    }

    final text = _blocks.map((block) => block.rawText).join('\n\n');
    final effectiveFocusedIndex =
        _blocks.indexWhere((block) => block.focusNode.hasFocus);
    var nextSelection = widget.controller.selection.isValid
        ? TextSelection(
            baseOffset:
                widget.controller.selection.baseOffset.clamp(0, text.length),
            extentOffset:
                widget.controller.selection.extentOffset.clamp(0, text.length),
          )
        : TextSelection.collapsed(offset: text.length);

    if (effectiveFocusedIndex != -1) {
      var consumed = 0;
      for (var index = 0; index < effectiveFocusedIndex; index++) {
        consumed += _blocks[index].rawText.length + 2;
      }
      final activeSelection =
          _blocks[effectiveFocusedIndex].controller.selection;
      final textLength = _blocks[effectiveFocusedIndex].controller.text.length;
      final localBase = activeSelection.isValid
          ? activeSelection.baseOffset.clamp(0, textLength)
          : textLength;
      final localExtent = activeSelection.isValid
          ? activeSelection.extentOffset.clamp(0, textLength)
          : textLength;
      nextSelection = TextSelection(
        baseOffset: consumed +
            _blocks[effectiveFocusedIndex].rawSelectionOffset(localBase),
        extentOffset: consumed +
            _blocks[effectiveFocusedIndex].rawSelectionOffset(localExtent),
      );
    }

    _syncingToMaster = true;
    try {
      widget.controller.value = TextEditingValue(
        text: text,
        selection: nextSelection,
      );
    } finally {
      _syncingToMaster = false;
    }

    if (!_matchesMasterStructure(text)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _rebuildBlocksFromMasterText();
      });
    }
  }

  int _activeBlockIndex() {
    for (var index = 0; index < _blocks.length; index++) {
      if (_blocks[index].focusNode.hasFocus) {
        return index;
      }
    }

    return _blocks.isEmpty ? -1 : _blocks.length - 1;
  }

  void _handleExternalFocusRequest() {
    if (!widget.focusNode.hasFocus || _blocks.isEmpty) {
      return;
    }
    if (!_isMasterSelectionCollapsed) {
      return;
    }
    if (_blocks.any((block) => block.focusNode.hasFocus)) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.focusNode.hasFocus) {
        return;
      }
      _focusBlockForMasterSelection();
    });
  }

  void _attachBlockListeners(_DocumentEditorBlock block) {
    block.controller.addListener(() {
      if (block.controller.selection.isValid) {
        block.lastKnownSelection = block.controller.selection;
      }
      _syncMasterFromBlocks();
    });
    block.languageController.addListener(_syncMasterFromBlocks);
    block.focusNode.addListener(_syncMasterFromBlocks);
  }

  bool get _isMasterSelectionCollapsed {
    final selection = widget.controller.selection;
    return !selection.isValid || selection.isCollapsed;
  }

  bool get _isWholeDocumentSelected {
    final selection = widget.controller.selection;
    return selection.isValid &&
        !selection.isCollapsed &&
        selection.start == 0 &&
        selection.end == widget.controller.text.length;
  }

  bool get _hasEditorFocus {
    return widget.focusNode.hasFocus ||
        _blocks.any((block) => block.focusNode.hasFocus);
  }

  bool get _hasDocumentSelection {
    final selection = widget.controller.selection;
    return selection.isValid && !selection.isCollapsed;
  }

  void _selectAllBlocks() {
    widget.controller.selection = TextSelection(
        baseOffset: 0, extentOffset: widget.controller.text.length);
    for (final block in _blocks) {
      block.controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: block.controller.text.length,
      );
    }
    setState(() {});
    FocusScope.of(context).requestFocus(widget.focusNode);
  }

  void _clearDocumentSelection() {
    if (!_hasDocumentSelection) {
      return;
    }

    final selection = widget.controller.selection;
    final start = math.min(selection.start, selection.end);
    final end = math.max(selection.start, selection.end);
    final updatedText = widget.controller.text.replaceRange(start, end, '');

    widget.controller.value = TextEditingValue(
      text: updatedText,
      selection:
          TextSelection.collapsed(offset: start.clamp(0, updatedText.length)),
    );
    _rebuildBlocksFromMasterText();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _focusBlockForMasterSelection();
    });
  }

  void _collapseDocumentSelectionToExtent() {
    final selection = widget.controller.selection;
    if (!selection.isValid || selection.isCollapsed) {
      return;
    }

    final collapsed = TextSelection.collapsed(
      offset: selection.extentOffset.clamp(0, widget.controller.text.length),
    );
    widget.controller.selection = collapsed;
    _syncSelectionsFromMaster();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _focusBlockForMasterSelection();
    });
  }

  bool _handleHardwareKeyEvent(KeyEvent event) {
    if (!_hasEditorFocus || event is! KeyDownEvent) {
      return false;
    }

    final activeIndex = _activeBlockIndex();
    if (_isSelectAllShortcut(event)) {
      _selectAllBlocks();
      return true;
    }

    if (_hasDocumentSelection &&
        !HardwareKeyboard.instance.isShiftPressed &&
        (event.logicalKey == LogicalKeyboardKey.arrowRight ||
            event.logicalKey == LogicalKeyboardKey.arrowDown)) {
      _collapseDocumentSelectionToExtent();
      return true;
    }

    if (_hasDocumentSelection &&
        HardwareKeyboard.instance.isShiftPressed &&
        (event.logicalKey == LogicalKeyboardKey.arrowUp ||
            event.logicalKey == LogicalKeyboardKey.arrowDown)) {
      _extendDocumentSelectionByBlock(
        upward: event.logicalKey == LogicalKeyboardKey.arrowUp,
      );
      return true;
    }

    if (HardwareKeyboard.instance.isShiftPressed &&
        activeIndex != -1 &&
        !_blocks[activeIndex].isCode) {
      final block = _blocks[activeIndex];
      final selection = block.controller.selection;
      final previousIsCode = activeIndex > 0 && _blocks[activeIndex - 1].isCode;
      final nextIsCode =
          activeIndex < _blocks.length - 1 && _blocks[activeIndex + 1].isCode;

      if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
          previousIsCode &&
          _isCaretOnFirstLine(block)) {
        _extendSelectionToAdjacentBlock(activeIndex, upward: true);
        return true;
      }

      if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
          nextIsCode &&
          _isSelectionExtentAtBlockEnd(block)) {
        _extendSelectionToAdjacentBlock(activeIndex, upward: false);
        return true;
      }
    }

    if (_hasDocumentSelection &&
        (event.logicalKey == LogicalKeyboardKey.backspace ||
            event.logicalKey == LogicalKeyboardKey.delete)) {
      _clearDocumentSelection();
      return true;
    }

    return false;
  }

  void insertCodeBlock() {
    final activeIndex = _activeBlockIndex();
    if (activeIndex != -1 &&
        !_blocks[activeIndex].isCode &&
        _blocks[activeIndex].controller.text.trim().isEmpty) {
      convertBlockToCode(activeIndex, clearText: true);
      return;
    }

    final insertIndex = activeIndex == -1 ? 0 : activeIndex + 1;
    final block = _DocumentEditorBlock(
      controller: TextEditingController(),
      languageController: TextEditingController(),
      focusNode: FocusNode(),
      isCode: true,
    );
    _attachBlockListeners(block);

    setState(() {
      _blocks.insert(insertIndex, block);
    });
    _syncMasterFromBlocks();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _focusBlock(insertIndex.clamp(0, _blocks.length - 1), placeAtEnd: false);
    });
  }

  void toggleInlineMarkdown(
    String marker, {
    required String placeholder,
  }) {
    final targetIndex = _inlineMarkdownTargetBlockIndex();
    if (targetIndex == -1) {
      return;
    }

    final block = _blocks[targetIndex];
    if (block.isCode) {
      return;
    }

    final text = block.controller.text;
    final rawSelection = _validBlockSelection(block);
    final collapsedSpan = rawSelection.isCollapsed
        ? _enclosingBlockInlineMarkdownContentRange(
            text,
            marker: marker,
            cursorOffset: rawSelection.extentOffset.clamp(0, text.length),
          )
        : null;
    final selection = collapsedSpan ??
        (rawSelection.isCollapsed
            ? (_collapsedBlockSelectionForCurrentWord(
                  text,
                  cursorOffset: rawSelection.extentOffset.clamp(0, text.length),
                ) ??
                rawSelection)
            : rawSelection);
    final start =
        math.min(selection.start, selection.end).clamp(0, text.length);
    final end = math.max(selection.start, selection.end).clamp(0, text.length);

    if (rawSelection.isCollapsed && collapsedSpan == null) {
      final replacement = '$marker$placeholder$marker';
      final updatedText = text.replaceRange(start, end, replacement);
      final placeholderStart = start + marker.length;
      block.controller.value = TextEditingValue(
        text: updatedText,
        selection: TextSelection(
          baseOffset: placeholderStart,
          extentOffset: placeholderStart + placeholder.length,
        ),
      );
      block.focusNode.requestFocus();
      _syncMasterFromBlocks();
      return;
    }

    final isWrappedSelection = start >= marker.length &&
        end + marker.length <= text.length &&
        text.substring(start - marker.length, start) == marker &&
        text.substring(end, end + marker.length) == marker;
    final updatedText = isWrappedSelection
        ? text.replaceRange(
            start - marker.length,
            end + marker.length,
            text.substring(start, end),
          )
        : text.replaceRange(
            start,
            end,
            '$marker${text.substring(start, end)}$marker',
          );
    block.controller.value = TextEditingValue(
      text: updatedText,
      selection: TextSelection(
        baseOffset:
            isWrappedSelection ? start - marker.length : start + marker.length,
        extentOffset:
            isWrappedSelection ? end - marker.length : end + marker.length,
      ),
    );
    block.focusNode.requestFocus();
    _syncMasterFromBlocks();
  }

  int _inlineMarkdownTargetBlockIndex() {
    final focusedIndex = _activeBlockIndex();
    if (focusedIndex != -1) {
      return focusedIndex;
    }

    for (var index = 0; index < _blocks.length; index++) {
      final selection = _blocks[index].controller.selection;
      if (!selection.isValid) {
        continue;
      }
      if (!selection.isCollapsed || selection.extentOffset != 0) {
        return index;
      }
    }

    return _blocks.isEmpty ? -1 : 0;
  }

  TextSelection _validBlockSelection(_DocumentEditorBlock block) {
    final selection = block.controller.selection;
    if (!selection.isValid) {
      return TextSelection(
        baseOffset: block.lastKnownSelection.baseOffset
            .clamp(0, block.controller.text.length),
        extentOffset: block.lastKnownSelection.extentOffset
            .clamp(0, block.controller.text.length),
      );
    }
    block.lastKnownSelection = selection;
    return selection;
  }

  TextSelection? _collapsedBlockSelectionForCurrentWord(
    String text, {
    required int cursorOffset,
  }) {
    if (text.isEmpty) {
      return null;
    }

    int? anchorIndex;
    if (cursorOffset < text.length &&
        _isBlockInlineWordCharacter(text[cursorOffset])) {
      anchorIndex = cursorOffset;
    } else if (cursorOffset > 0 &&
        _isBlockInlineWordCharacter(text[cursorOffset - 1])) {
      anchorIndex = cursorOffset - 1;
    }

    if (anchorIndex == null) {
      return null;
    }

    var start = anchorIndex;
    var end = anchorIndex + 1;
    while (start > 0 && _isBlockInlineWordCharacter(text[start - 1])) {
      start -= 1;
    }
    while (end < text.length && _isBlockInlineWordCharacter(text[end])) {
      end += 1;
    }

    return TextSelection(baseOffset: start, extentOffset: end);
  }

  bool _isBlockInlineWordCharacter(String character) {
    return RegExp(r'[A-Za-z0-9_]').hasMatch(character);
  }

  TextSelection? _enclosingBlockInlineMarkdownContentRange(
    String text, {
    required String marker,
    required int cursorOffset,
  }) {
    if (text.isEmpty || cursorOffset < 0 || cursorOffset > text.length) {
      return null;
    }

    final openingSearchStart =
        (cursorOffset - marker.length).clamp(0, text.length);
    final openingStart = text.lastIndexOf(marker, openingSearchStart);
    if (openingStart == -1) {
      return null;
    }

    final contentStart = openingStart + marker.length;
    final closingStart = text.indexOf(marker, contentStart);
    if (closingStart == -1 || closingStart < cursorOffset) {
      return null;
    }

    if (cursorOffset < contentStart || contentStart == closingStart) {
      return null;
    }

    return TextSelection(
      baseOffset: contentStart,
      extentOffset: closingStart,
    );
  }

  void convertBlockToCode(
    int index, {
    bool clearText = false,
    bool ensureTrailingParagraph = false,
  }) {
    if (index < 0 || index >= _blocks.length || _blocks[index].isCode) {
      return;
    }

    final existing = _blocks[index];
    final replacement = _DocumentEditorBlock(
      controller: TextEditingController(
          text: clearText ? '' : existing.controller.text),
      languageController: TextEditingController(),
      focusNode: FocusNode(),
      isCode: true,
    );
    _attachBlockListeners(replacement);

    setState(() {
      _blocks[index] = replacement;
      if (ensureTrailingParagraph && index == _blocks.length - 1) {
        final trailingParagraph = _DocumentEditorBlock(
          controller: _MarkdownEditingController(text: ''),
          languageController: TextEditingController(),
          focusNode: FocusNode(),
          isCode: false,
        );
        _attachBlockListeners(trailingParagraph);
        _blocks.add(trailingParagraph);
      }
      _slashMenuBlockIndex = null;
      _selectedSlashCommandIndex = 0;
    });
    existing.dispose();
    _syncMasterFromBlocks();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _focusBlock(index.clamp(0, _blocks.length - 1), placeAtEnd: false);
    });
  }

  void removeBlock(int index) {
    if (index < 0 || index >= _blocks.length) {
      return;
    }

    final removed = _blocks.removeAt(index);
    if (_blocks.isEmpty) {
      final fallback = _DocumentEditorBlock(
        controller: _MarkdownEditingController(text: ''),
        languageController: TextEditingController(),
        focusNode: FocusNode(),
        isCode: false,
      );
      _attachBlockListeners(fallback);
      _blocks.add(fallback);
    }

    setState(() {});
    removed.dispose();
    _syncMasterFromBlocks();
  }

  void _removeBlockAndFocus(int index) {
    if (index < 0 || index >= _blocks.length) {
      return;
    }

    final targetIndex = index > 0 ? index - 1 : 0;
    final placeAtEnd = index > 0;
    removeBlock(index);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _focusBlock(targetIndex.clamp(0, _blocks.length - 1),
          placeAtEnd: placeAtEnd);
    });
  }

  void _insertParagraphAfter(int index) {
    final paragraph = _DocumentEditorBlock(
      controller: _MarkdownEditingController(text: ''),
      languageController: TextEditingController(),
      focusNode: FocusNode(),
      isCode: false,
    );
    _attachBlockListeners(paragraph);
    setState(() {
      _blocks.insert(index + 1, paragraph);
    });
    _syncMasterFromBlocks();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _focusBlock((index + 1).clamp(0, _blocks.length - 1), placeAtEnd: false);
    });
  }

  void _focusBlock(int index, {required bool placeAtEnd}) {
    if (index < 0 || index >= _blocks.length) {
      return;
    }

    final block = _blocks[index];
    block.focusNode.requestFocus();
    final offset = placeAtEnd ? block.controller.text.length : 0;
    block.controller.selection = TextSelection.collapsed(offset: offset);
  }

  void _focusBlockAtFirstLineEnd(int index) {
    if (index < 0 || index >= _blocks.length) {
      return;
    }

    final block = _blocks[index];
    final lineEnd = block.controller.text.indexOf('\n');
    final offset = lineEnd == -1 ? block.controller.text.length : lineEnd;
    block.focusNode.requestFocus();
    block.controller.selection = TextSelection.collapsed(offset: offset);
  }

  void _focusBlockForMasterSelection() {
    final selection = widget.controller.selection;
    final targetOffset = selection.isValid
        ? selection.extentOffset.clamp(0, widget.controller.text.length)
        : widget.controller.text.length;

    var consumed = 0;
    for (var index = 0; index < _blocks.length; index++) {
      final block = _blocks[index];
      final length = block.rawText.length;
      final isLast = index == _blocks.length - 1;
      final blockEnd = consumed + length;
      final separatorLength = isLast ? 0 : 2;
      final rangeEnd = blockEnd + separatorLength;

      if (targetOffset <= rangeEnd || isLast) {
        final localOffset = block
            .localSelectionOffset((targetOffset - consumed).clamp(0, length));
        block.focusNode.requestFocus();
        block.controller.selection =
            TextSelection.collapsed(offset: localOffset);
        return;
      }

      consumed = rangeEnd;
    }
  }

  void _handleParagraphChanged(int index, _DocumentEditorBlock block) {
    final commands = _matchingSlashCommands(block);
    final nextBlockIndex = commands.isEmpty ? null : index;
    final nextSelectedIndex = commands.isEmpty
        ? 0
        : (_slashMenuBlockIndex == index
            ? _selectedSlashCommandIndex.clamp(0, commands.length - 1)
            : 0);
    if (_slashMenuBlockIndex == nextBlockIndex &&
        _selectedSlashCommandIndex == nextSelectedIndex) {
      return;
    }
    setState(() {
      _slashMenuBlockIndex = nextBlockIndex;
      _selectedSlashCommandIndex = nextSelectedIndex;
    });
  }

  bool _isCaretOnFirstLine(_DocumentEditorBlock block) {
    final selection = block.controller.selection;
    if (!selection.isValid) {
      return false;
    }

    final offset =
        selection.extentOffset.clamp(0, block.controller.text.length);
    if (offset == 0) {
      return true;
    }

    return block.controller.text.lastIndexOf('\n', offset - 1) == -1;
  }

  bool _isSelectionExtentAtBlockEnd(_DocumentEditorBlock block) {
    final selection = block.controller.selection;
    if (!selection.isValid) {
      return false;
    }
    return selection.extentOffset == block.controller.text.length;
  }

  bool _isSelectAllShortcut(KeyEvent event) {
    return event.logicalKey == LogicalKeyboardKey.keyA &&
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed);
  }

  int _blockStartOffset(int index) {
    var consumed = 0;
    for (var scan = 0; scan < index; scan++) {
      consumed += _blocks[scan].rawText.length + 2;
    }
    return consumed;
  }

  int _blockEndOffset(int index) {
    return _blockStartOffset(index) + _blocks[index].rawText.length;
  }

  int _blockIndexForDocumentOffset(int offset) {
    var consumed = 0;
    for (var index = 0; index < _blocks.length; index++) {
      final length = _blocks[index].rawText.length;
      final isLast = index == _blocks.length - 1;
      final rangeEnd = consumed + length + (isLast ? 0 : 2);
      if (offset <= rangeEnd || isLast) {
        return index;
      }
      consumed = rangeEnd;
    }
    return _blocks.isEmpty ? -1 : _blocks.length - 1;
  }

  void _extendDocumentSelectionByBlock({required bool upward}) {
    final selection = widget.controller.selection;
    if (!selection.isValid || _blocks.isEmpty) {
      return;
    }

    final currentExtent =
        selection.extentOffset.clamp(0, widget.controller.text.length);
    final currentIndex = _blockIndexForDocumentOffset(currentExtent);
    if (currentIndex == -1) {
      return;
    }

    final currentBlockStart = _blockStartOffset(currentIndex);
    final currentBlockEnd = _blockEndOffset(currentIndex);

    final nextExtent = switch ((
      upward,
      currentExtent <= currentBlockStart,
      currentExtent >= currentBlockEnd
    )) {
      (true, true, _) when currentIndex > 0 =>
        _blockStartOffset(currentIndex - 1),
      (true, _, _) => currentBlockStart,
      (false, _, true) when currentIndex < _blocks.length - 1 =>
        _blockEndOffset(currentIndex + 1),
      (false, _, _) => currentBlockEnd,
    };

    widget.controller.selection = TextSelection(
      baseOffset: selection.baseOffset.clamp(0, widget.controller.text.length),
      extentOffset: nextExtent.clamp(0, widget.controller.text.length),
    );
    _syncSelectionsFromMaster();
    setState(() {});
  }

  void _extendSelectionToAdjacentBlock(int index, {required bool upward}) {
    final selection = widget.controller.selection;
    final activeBlock = _blocks[index];
    final blockStart = _blockStartOffset(index);
    final localSelection = activeBlock.controller.selection;
    final currentExtent = blockStart +
        activeBlock.rawSelectionOffset(
          localSelection.isValid
              ? localSelection.extentOffset
                  .clamp(0, activeBlock.controller.text.length)
              : activeBlock.controller.text.length,
        );
    final nextExtent = upward
        ? _blockStartOffset(index - 1)
        : _blockStartOffset(index + 1) + _blocks[index + 1].rawText.length;

    final baseOffset = selection.isValid ? selection.baseOffset : currentExtent;
    widget.controller.selection = TextSelection(
      baseOffset: baseOffset.clamp(0, widget.controller.text.length),
      extentOffset: nextExtent.clamp(0, widget.controller.text.length),
    );
    _syncSelectionsFromMaster();
    setState(() {});
  }

  KeyEventResult _handleParagraphKeyEvent(
    int index,
    _DocumentEditorBlock block,
    KeyEvent event,
  ) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    if (_isSelectAllShortcut(event)) {
      _selectAllBlocks();
      return KeyEventResult.handled;
    }

    if (_hasDocumentSelection &&
        (event.logicalKey == LogicalKeyboardKey.backspace ||
            event.logicalKey == LogicalKeyboardKey.delete)) {
      _clearDocumentSelection();
      return KeyEventResult.handled;
    }

    final commands = _matchingSlashCommands(block);
    if (commands.isNotEmpty) {
      if (_slashMenuBlockIndex != index) {
        _slashMenuBlockIndex = index;
        _selectedSlashCommandIndex = 0;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        setState(() {
          _selectedSlashCommandIndex =
              (_selectedSlashCommandIndex + 1) % commands.length;
        });
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        setState(() {
          _selectedSlashCommandIndex =
              (_selectedSlashCommandIndex - 1 + commands.length) %
                  commands.length;
        });
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter) {
        _applySlashCommand(index, commands[_selectedSlashCommandIndex]);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        setState(() {
          _slashMenuBlockIndex = null;
          _selectedSlashCommandIndex = 0;
        });
        return KeyEventResult.handled;
      }
    }

    final selection = block.controller.selection;
    if (!selection.isValid || !selection.isCollapsed) {
      return KeyEventResult.ignored;
    }

    final shiftPressed = HardwareKeyboard.instance.isShiftPressed;
    final previousIsCode = index > 0 && _blocks[index - 1].isCode;
    if (shiftPressed &&
        event.logicalKey == LogicalKeyboardKey.arrowUp &&
        previousIsCode &&
        _isCaretOnFirstLine(block)) {
      _extendSelectionToAdjacentBlock(index, upward: true);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
        index > 0 &&
        ((previousIsCode && _isCaretOnFirstLine(block)) ||
            selection.extentOffset == 0)) {
      _focusBlock(index - 1, placeAtEnd: true);
      return KeyEventResult.handled;
    }

    final nextIsCode = index < _blocks.length - 1 && _blocks[index + 1].isCode;
    if (shiftPressed &&
        event.logicalKey == LogicalKeyboardKey.arrowDown &&
        nextIsCode &&
        _isSelectionExtentAtBlockEnd(block)) {
      _extendSelectionToAdjacentBlock(index, upward: false);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
        selection.extentOffset == block.controller.text.length &&
        index < _blocks.length - 1) {
      _focusBlock(index + 1, placeAtEnd: false);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  KeyEventResult _handleCodeKeyEvent(
    int index,
    _DocumentEditorBlock block,
    KeyEvent event,
  ) {
    if (event is! KeyDownEvent || !block.isCode) {
      return KeyEventResult.ignored;
    }

    if (_isSelectAllShortcut(event)) {
      _selectAllBlocks();
      return KeyEventResult.handled;
    }

    if (_hasDocumentSelection &&
        (event.logicalKey == LogicalKeyboardKey.backspace ||
            event.logicalKey == LogicalKeyboardKey.delete)) {
      _clearDocumentSelection();
      return KeyEventResult.handled;
    }

    final selection = block.controller.selection;
    if (!selection.isValid || !selection.isCollapsed) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
        selection.extentOffset == block.controller.text.length) {
      if (index == _blocks.length - 1) {
        _insertParagraphAfter(index);
      } else {
        final nextBlock = _blocks[index + 1];
        if (!nextBlock.isCode && nextBlock.controller.text.isNotEmpty) {
          _focusBlockAtFirstLineEnd(index + 1);
        } else {
          _focusBlock(index + 1, placeAtEnd: false);
        }
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
        selection.extentOffset == 0 &&
        index > 0) {
      _focusBlock(index - 1, placeAtEnd: true);
      return KeyEventResult.handled;
    }

    if ((event.logicalKey == LogicalKeyboardKey.backspace ||
            event.logicalKey == LogicalKeyboardKey.delete) &&
        block.controller.text.isEmpty) {
      _removeBlockAndFocus(index);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _applySlashCommand(int index, _SlashCommand command) {
    switch (command.type) {
      case _SlashCommandType.code:
        _convertSelectionLineToCode(index, ensureTrailingParagraph: true);
      case _SlashCommandType.checklist:
        _replaceSelectionLineWithChecklist(index);
    }
  }

  void _replaceSelectionLineWithChecklist(int index) {
    if (index < 0 || index >= _blocks.length) {
      return;
    }

    final block = _blocks[index];
    if (block.isCode) {
      return;
    }

    final lineRange = _selectedLineRange(block);
    if (lineRange == null) {
      return;
    }

    const replacement = '- [ ] ';
    final updatedText = block.controller.text.replaceRange(
      lineRange.start,
      lineRange.end,
      replacement,
    );
    block.controller.value = TextEditingValue(
      text: updatedText,
      selection: TextSelection.collapsed(
        offset: lineRange.start + replacement.length,
      ),
    );
    _focusBlock(index, placeAtEnd: false);
  }

  void _convertSelectionLineToCode(
    int index, {
    required bool ensureTrailingParagraph,
  }) {
    if (index < 0 || index >= _blocks.length) {
      return;
    }

    final existing = _blocks[index];
    if (existing.isCode) {
      return;
    }

    final lineRange = _selectedLineRange(existing);
    if (lineRange == null) {
      convertBlockToCode(
        index,
        clearText: true,
        ensureTrailingParagraph: ensureTrailingParagraph,
      );
      return;
    }

    final fullText = existing.controller.text;
    final beforeText = fullText
        .substring(0, lineRange.start)
        .replaceFirst(RegExp(r'\n+$'), '');
    final afterText =
        fullText.substring(lineRange.end).replaceFirst(RegExp(r'^\n+'), '');

    final replacementBlocks = <_DocumentEditorBlock>[
      if (beforeText.isNotEmpty)
        _DocumentEditorBlock(
          controller: _MarkdownEditingController(text: beforeText),
          languageController: TextEditingController(),
          focusNode: FocusNode(),
          isCode: false,
        ),
      _DocumentEditorBlock(
        controller: TextEditingController(),
        languageController: TextEditingController(),
        focusNode: FocusNode(),
        isCode: true,
      ),
      if (afterText.isNotEmpty)
        _DocumentEditorBlock(
          controller: _MarkdownEditingController(text: afterText),
          languageController: TextEditingController(),
          focusNode: FocusNode(),
          isCode: false,
        )
      else if (ensureTrailingParagraph && index == _blocks.length - 1)
        _DocumentEditorBlock(
          controller: _MarkdownEditingController(text: ''),
          languageController: TextEditingController(),
          focusNode: FocusNode(),
          isCode: false,
        ),
    ];

    for (final block in replacementBlocks) {
      _attachBlockListeners(block);
    }

    final codeBlockIndex = index + (beforeText.isNotEmpty ? 1 : 0);

    setState(() {
      _blocks
        ..removeAt(index)
        ..insertAll(index, replacementBlocks);
      _slashMenuBlockIndex = null;
      _selectedSlashCommandIndex = 0;
    });
    existing.dispose();
    _syncMasterFromBlocks();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _focusBlock(codeBlockIndex.clamp(0, _blocks.length - 1),
          placeAtEnd: false);
    });
  }

  Future<bool> copyFocusedCodeBlock(BuildContext context) async {
    final activeIndex = _activeBlockIndex();
    if (activeIndex == -1 || !_blocks[activeIndex].isCode) {
      return false;
    }

    final block = _blocks[activeIndex];
    await Clipboard.setData(ClipboardData(text: block.controller.text));
    if (!context.mounted) {
      return true;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          block.languageController.text.trim().isEmpty
              ? 'Code snippet copied'
              : '${block.languageController.text.trim().toUpperCase()} snippet copied',
        ),
      ),
    );
    return true;
  }

  @visibleForTesting
  void debugSetPrimaryParagraphSelection(TextSelection selection) {
    final index = _blocks.indexWhere((block) => !block.isCode);
    if (index == -1) {
      return;
    }

    final block = _blocks[index];
    final nextSelection = TextSelection(
      baseOffset: selection.baseOffset.clamp(0, block.controller.text.length),
      extentOffset:
          selection.extentOffset.clamp(0, block.controller.text.length),
    );
    block.lastKnownSelection = nextSelection;
    block.controller.selection = nextSelection;
    widget.focusNode.requestFocus();
    block.focusNode.requestFocus();
    _syncMasterFromBlocks();
  }

  bool _matchesMasterStructure(String text) {
    final parsedSignatures = blocksFromEditableText(text)
        .map(_DocumentEditorBlock.structureSignatureForNoteBlock)
        .toList(growable: false);
    final currentSignatures = _blocks
        .map((block) => block.structureSignature)
        .toList(growable: false);
    return _listEquals(currentSignatures, parsedSignatures);
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6);
    final colorScheme = Theme.of(context).colorScheme;
    final padding = widget.embedded
        ? const EdgeInsets.only(top: 8, right: 4, bottom: 8)
        : const EdgeInsets.all(18);
    final highlightAll = _isWholeDocumentSelected;

    return Actions(
      actions: <Type, Action<Intent>>{
        SelectAllTextIntent: CallbackAction<SelectAllTextIntent>(
          onInvoke: (_) {
            _selectAllBlocks();
            return null;
          },
        ),
      },
      child: Focus(
        key: const ValueKey('document-editor-focus'),
        focusNode: widget.focusNode,
        child: ListView.separated(
          key: const ValueKey('document-block-editor'),
          padding: padding,
          itemCount: _blocks.length,
          separatorBuilder: (context, _) => const SizedBox(height: 18),
          itemBuilder: (context, index) {
            final block = _blocks[index];
            final focusNode = block.focusNode;
            if (block.isCode) {
              return _CodeEditorBlockCard(
                block: block,
                focusNode: focusNode,
                onTap: widget.onTap,
                onKeyEvent: (event) => _handleCodeKeyEvent(index, block, event),
                highlightSelection: highlightAll,
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  decoration: BoxDecoration(
                    color: highlightAll
                        ? colorScheme.primary.withValues(alpha: 0.08)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Focus(
                    onKeyEvent: (_, event) =>
                        _handleParagraphKeyEvent(index, block, event),
                    child: TextField(
                      controller: block.controller,
                      focusNode: focusNode,
                      onTap: widget.onTap,
                      onChanged: (_) => _handleParagraphChanged(index, block),
                      inputFormatters: const [
                        _MarkdownListEditingFormatter(),
                      ],
                      decoration: InputDecoration(
                        hintText: index == 0
                            ? '# Untitled note\n\nStart writing in Markdown...'
                            : null,
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      style: style,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      textAlignVertical: TextAlignVertical.top,
                      minLines: 1,
                      maxLines: null,
                    ),
                  ),
                ),
                if (_matchingSlashCommands(block).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _SlashCommandMenu(
                      commands: _matchingSlashCommands(block),
                      selectedIndex: _slashMenuBlockIndex == index
                          ? _selectedSlashCommandIndex
                          : 0,
                      onSelected: (command) {
                        _applySlashCommand(index, command);
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  List<_SlashCommand> _matchingSlashCommands(_DocumentEditorBlock block) {
    if (block.isCode) {
      return const <_SlashCommand>[];
    }

    final query = _slashCommandQuery(block);
    if (query == null) {
      return const <_SlashCommand>[];
    }
    return _slashCommands
        .where((command) =>
            query.isEmpty ||
            command.label.toLowerCase().contains(query) ||
            command.aliases.any((alias) => alias.contains(query)))
        .toList(growable: false);
  }

  String? _slashCommandQuery(_DocumentEditorBlock block) {
    final lineRange = _selectedLineRange(block);
    if (lineRange == null) {
      return null;
    }

    final lineText =
        block.controller.text.substring(lineRange.start, lineRange.end);
    final trimmed = lineText.trim();
    if (!trimmed.startsWith('/')) {
      return null;
    }

    return trimmed.substring(1).toLowerCase();
  }

  _LineRange? _selectedLineRange(_DocumentEditorBlock block) {
    final selection = block.controller.selection;
    if (!selection.isValid || !selection.isCollapsed) {
      return null;
    }

    final text = block.controller.text;
    final offset = selection.extentOffset.clamp(0, text.length);
    final lineStart = text.lastIndexOf('\n', offset == 0 ? 0 : offset - 1);
    final start = lineStart == -1 ? 0 : lineStart + 1;
    final lineEnd = text.indexOf('\n', offset);
    final end = lineEnd == -1 ? text.length : lineEnd;
    return _LineRange(start: start, end: end);
  }
}

const List<_SlashCommand> _slashCommands = <_SlashCommand>[
  _SlashCommand(
    type: _SlashCommandType.code,
    label: 'Code block',
    description: 'Insert a code block',
    aliases: <String>['code', 'snippet', 'block'],
  ),
  _SlashCommand(
    type: _SlashCommandType.checklist,
    label: 'Checklist',
    description: 'Insert a checklist item',
    aliases: <String>['checklist', 'task', 'todo'],
  ),
];

enum _SlashCommandType {
  code,
  checklist,
}

class _SlashCommand {
  const _SlashCommand({
    required this.type,
    required this.label,
    required this.description,
    required this.aliases,
  });

  final _SlashCommandType type;
  final String label;
  final String description;
  final List<String> aliases;
}

class _LineRange {
  const _LineRange({
    required this.start,
    required this.end,
  });

  final int start;
  final int end;
}

class _DocumentEditorBlock {
  _DocumentEditorBlock({
    required this.controller,
    required this.languageController,
    required this.focusNode,
    required this.isCode,
  }) : lastKnownSelection = controller.selection.isValid
            ? controller.selection
            : TextSelection.collapsed(offset: controller.text.length);

  final TextEditingController controller;
  final TextEditingController languageController;
  final FocusNode focusNode;
  final bool isCode;
  TextSelection lastKnownSelection;

  factory _DocumentEditorBlock.fromNoteBlock(
    NoteBlock block, {
    required FocusNode focusNode,
  }) {
    return switch (block) {
      ParagraphBlock(:final text) => _DocumentEditorBlock(
          controller: _MarkdownEditingController(text: text),
          languageController: TextEditingController(),
          focusNode: focusNode,
          isCode: false,
        ),
      CodeBlock(:final language, :final code) => _DocumentEditorBlock(
          controller: TextEditingController(text: code),
          languageController: TextEditingController(text: language),
          focusNode: focusNode,
          isCode: true,
        ),
      _ => _DocumentEditorBlock(
          controller: _MarkdownEditingController(text: ''),
          languageController: TextEditingController(),
          focusNode: focusNode,
          isCode: false,
        ),
    };
  }

  static String signatureForNoteBlock(NoteBlock block) {
    return switch (block) {
      ParagraphBlock(:final text) => 'paragraph|$text',
      CodeBlock(:final language, :final code) => 'code|$language|$code',
      UnknownBlock(:final type) => 'unknown|$type',
    };
  }

  static String structureSignatureForNoteBlock(NoteBlock block) {
    return switch (block) {
      ParagraphBlock() => 'paragraph',
      CodeBlock(:final language) => 'code|$language',
      UnknownBlock(:final type) => 'unknown|$type',
    };
  }

  String get signature => isCode
      ? 'code|${languageController.text.trim()}|${controller.text}'
      : 'paragraph|${controller.text}';

  String get structureSignature =>
      isCode ? 'code|${languageController.text.trim()}' : 'paragraph';

  String get openingTag => languageController.text.trim().isEmpty
      ? '```'
      : '```${languageController.text.trim()}';

  String get rawText =>
      isCode ? '$openingTag\n${controller.text}\n```' : controller.text;

  int localSelectionOffset(int rawOffsetWithinBlock) {
    if (!isCode) {
      return rawOffsetWithinBlock.clamp(0, controller.text.length);
    }

    return (rawOffsetWithinBlock - openingTag.length - 1)
        .clamp(0, controller.text.length);
  }

  int rawSelectionOffset(int localOffset) {
    if (!isCode) {
      return localOffset.clamp(0, controller.text.length);
    }

    return openingTag.length + 1 + localOffset.clamp(0, controller.text.length);
  }

  void syncFromNoteBlock(NoteBlock block) {
    final nextText = switch (block) {
      ParagraphBlock(:final text) when !isCode => text,
      CodeBlock(:final code) when isCode => code,
      _ => controller.text,
    };
    final nextLanguage = switch (block) {
      CodeBlock(:final language) when isCode => language,
      _ => languageController.text,
    };

    if (controller.text == nextText) {
      if (languageController.text == nextLanguage) {
        return;
      }
    }

    if (languageController.text != nextLanguage) {
      languageController.value = TextEditingValue(
        text: nextLanguage,
        selection: TextSelection.collapsed(offset: nextLanguage.length),
      );
    }

    final safeOffset =
        controller.selection.extentOffset.clamp(0, nextText.length);
    if (controller.text != nextText) {
      controller.value = TextEditingValue(
        text: nextText,
        selection: TextSelection.collapsed(offset: safeOffset),
      );
    }
  }

  void dispose() {
    controller.dispose();
    languageController.dispose();
    focusNode.dispose();
  }
}

class _CodeEditorBlockCard extends StatelessWidget {
  const _CodeEditorBlockCard({
    required this.block,
    required this.focusNode,
    required this.onTap,
    required this.onKeyEvent,
    required this.highlightSelection,
  });

  final _DocumentEditorBlock block;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final KeyEventResult Function(KeyEvent event) onKeyEvent;
  final bool highlightSelection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isMobile = MediaQuery.sizeOf(context).width < 900;

    return Container(
      decoration: BoxDecoration(
        color: highlightSelection
            ? colorScheme.primary.withValues(alpha: isMobile ? 0.12 : 0.14)
            : (isMobile
                ? colorScheme.surfaceContainerLow
                : colorScheme.onSurface.withValues(alpha: 0.96)),
        borderRadius: BorderRadius.circular(isMobile ? 20 : 14),
        border: Border.all(
          color: highlightSelection
              ? colorScheme.primary.withValues(alpha: 0.42)
              : (isMobile
                  ? colorScheme.outlineVariant.withValues(alpha: 0.35)
                  : colorScheme.onSurface.withValues(alpha: 0.12)),
        ),
        boxShadow: isMobile
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      padding: EdgeInsets.all(isMobile ? 16 : 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (block.languageController.text.trim().isNotEmpty)
                Text(
                  block.languageController.text.trim().toUpperCase(),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: isMobile
                        ? colorScheme.onSurfaceVariant
                        : colorScheme.primary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
              const Spacer(),
              IconButton(
                tooltip: 'Copy code',
                style: isMobile
                    ? IconButton.styleFrom(
                        backgroundColor:
                            colorScheme.surface.withValues(alpha: 0.92),
                      )
                    : null,
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: block.controller.text),
                  );
                  if (!context.mounted) {
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        block.languageController.text.trim().isEmpty
                            ? 'Code snippet copied'
                            : '${block.languageController.text.trim().toUpperCase()} snippet copied',
                      ),
                    ),
                  );
                },
                icon: Icon(
                  Icons.content_copy_outlined,
                  size: 18,
                  color: isMobile
                      ? colorScheme.onSurfaceVariant
                      : colorScheme.onInverseSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (isMobile)
            Divider(
              height: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
          if (isMobile) const SizedBox(height: 10),
          Focus(
            onKeyEvent: (_, event) => onKeyEvent(event),
            child: TextField(
              controller: block.controller,
              focusNode: focusNode,
              onTap: onTap,
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
                fontSize: isMobile ? 13.5 : null,
                color: isMobile
                    ? colorScheme.onSurface
                    : colorScheme.onInverseSurface,
                height: isMobile ? 1.4 : 1.5,
              ),
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              textAlignVertical: TextAlignVertical.top,
              minLines: 1,
              maxLines: null,
            ),
          ),
        ],
      ),
    );
  }
}

class _SlashCommandMenu extends StatelessWidget {
  const _SlashCommandMenu({
    required this.commands,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<_SlashCommand> commands;
  final int selectedIndex;
  final ValueChanged<_SlashCommand> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < commands.length; index++)
            InkWell(
              onTap: () => onSelected(commands[index]),
              canRequestFocus: false,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: index == selectedIndex
                        ? colorScheme.surfaceContainerHigh
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.code,
                            size: 16,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                commands[index].label,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                commands[index].description,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MarkdownListEditingFormatter extends TextInputFormatter {
  const _MarkdownListEditingFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return applyMarkdownListEditBehavior(oldValue, newValue);
  }
}

@visibleForTesting
TextEditingValue applyMarkdownListEditBehavior(
  TextEditingValue oldValue,
  TextEditingValue newValue,
) {
  if (!oldValue.selection.isValid ||
      !newValue.selection.isValid ||
      !oldValue.selection.isCollapsed ||
      !newValue.selection.isCollapsed) {
    return newValue;
  }

  final lengthDelta = newValue.text.length - oldValue.text.length;
  if (lengthDelta == 1 &&
      oldValue.selection.extentOffset < newValue.text.length &&
      newValue.text[oldValue.selection.extentOffset] == '\n') {
    return _continueMarkdownList(oldValue, newValue);
  }

  if (lengthDelta == -1 &&
      newValue.selection.extentOffset == oldValue.selection.extentOffset - 1) {
    return _removeEmptyMarkdownListMarker(oldValue, newValue);
  }

  return newValue;
}

TextEditingValue _continueMarkdownList(
  TextEditingValue oldValue,
  TextEditingValue newValue,
) {
  final insertionOffset = oldValue.selection.extentOffset;
  final lineStart = oldValue.text.lastIndexOf('\n', insertionOffset - 1) + 1;
  final line = oldValue.text.substring(lineStart, insertionOffset);

  final taskMatch = _parseTaskListLine(line);
  if (taskMatch != null) {
    final prefix = '${taskMatch.indent}- [ ] ';
    return newValue.copyWith(
      text: newValue.text.replaceRange(
        newValue.selection.extentOffset,
        newValue.selection.extentOffset,
        prefix,
      ),
      selection: TextSelection.collapsed(
        offset: newValue.selection.extentOffset + prefix.length,
      ),
      composing: TextRange.empty,
    );
  }

  final bulletMatch = RegExp(r'^(\s*)([-*+])\s+(.*)$').firstMatch(line);
  if (bulletMatch != null) {
    final indent = bulletMatch.group(1)!;
    final marker = bulletMatch.group(2)!;
    final prefix = '$indent$marker ';
    return newValue.copyWith(
      text: newValue.text.replaceRange(
        newValue.selection.extentOffset,
        newValue.selection.extentOffset,
        prefix,
      ),
      selection: TextSelection.collapsed(
        offset: newValue.selection.extentOffset + prefix.length,
      ),
      composing: TextRange.empty,
    );
  }

  return newValue;
}

TextEditingValue _removeEmptyMarkdownListMarker(
  TextEditingValue oldValue,
  TextEditingValue newValue,
) {
  final oldCursorOffset = oldValue.selection.extentOffset;
  final lineStart = oldValue.text.lastIndexOf('\n', oldCursorOffset - 1) + 1;
  final lineEnd = oldValue.text.indexOf('\n', oldCursorOffset);
  final safeLineEnd = lineEnd == -1 ? oldValue.text.length : lineEnd;
  final oldLine = oldValue.text.substring(lineStart, safeLineEnd);

  if (RegExp(r'^\s*-\s+\[(?: |x|X)\]\s$').hasMatch(oldLine)) {
    final indent = RegExp(r'^\s*').firstMatch(oldLine)?.group(0) ?? '';
    return newValue.copyWith(
      text: newValue.text.replaceRange(lineStart, safeLineEnd - 1, indent),
      selection: TextSelection.collapsed(offset: lineStart + indent.length),
      composing: TextRange.empty,
    );
  }

  if (RegExp(r'^\s*[-*+] $').hasMatch(oldLine)) {
    final indent = RegExp(r'^\s*').firstMatch(oldLine)?.group(0) ?? '';
    return newValue.copyWith(
      text: newValue.text.replaceRange(lineStart, safeLineEnd - 1, indent),
      selection: TextSelection.collapsed(offset: lineStart + indent.length),
      composing: TextRange.empty,
    );
  }

  return newValue;
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }

  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

class _EditorCommandButton extends StatelessWidget {
  const _EditorCommandButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      child: Text(label),
    );
  }
}
