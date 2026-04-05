import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/markdown_title.dart';
import '../../../core/utils/note_document.dart';
import '../application/create_note.dart';
import '../application/update_note.dart';
import '../domain/note.dart';

class NoteEditorPage extends StatefulWidget {
  const NoteEditorPage({
    required this.createNote,
    required this.updateNote,
    this.note,
    this.initialFolderPath,
    this.embedded = false,
    this.onClose,
    this.onPersisted,
    super.key,
  });

  final CreateNote createNote;
  final UpdateNote updateNote;
  final Note? note;
  final String? initialFolderPath;
  final bool embedded;
  final VoidCallback? onClose;
  final ValueChanged<Note>? onPersisted;

  bool get isEditing => note != null;

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage>
    with WidgetsBindingObserver {
  static const Duration _autosaveDelay = Duration(milliseconds: 800);

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
  String? _saveErrorMessage;

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
    _titleFocusNode = FocusNode();
    _contentFocusNode = FocusNode();
    _persistedNote = widget.note;
    _lastPersistedSnapshot =
        widget.note == null ? null : _snapshotFromNote(widget.note!);
    _titleController.addListener(_handleTextChanged);
    _contentController.addListener(_handleTextChanged);
    _titleFocusNode.addListener(_handleEditorFocusChanged);
    _contentFocusNode.addListener(_handleEditorFocusChanged);
  }

  @override
  void dispose() {
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

  void _handleTextChanged() {
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

    final content = Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyS, control: true):
            _SaveNoteIntent(),
        SingleActivator(LogicalKeyboardKey.keyS, meta: true): _SaveNoteIntent(),
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
          _CloseEditorIntent: CallbackAction<_CloseEditorIntent>(
            onInvoke: (_) {
              unawaited(_requestClose());
              return null;
            },
          ),
        },
        child: _NoteEditorContent(
          title: effectiveTitle.isEmpty ? title : effectiveTitle,
          derivedTitle: derivedTitle,
          manualTitleIsEmpty: manualTitle.isEmpty,
          titleController: _titleController,
          contentController: _contentController,
          titleFocusNode: _titleFocusNode,
          contentFocusNode: _contentFocusNode,
          isSaving: _isSaving,
          status: _saveStatus,
          canRetrySave: _saveErrorMessage != null,
          embedded: widget.embedded,
          onRetrySave: _flushPendingChanges,
          onClose: widget.embedded ? _requestClose : null,
          applyHeading: _applyHeading,
          toggleBulletList: _toggleBulletList,
          toggleQuote: _toggleQuote,
          insertCodeSnippet: _insertCodeSnippet,
          copyCurrentCodeSnippet: _copyCurrentCodeSnippet,
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
        appBar: AppBar(
          title: Text(
            effectiveTitle.isEmpty ? title : effectiveTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: SafeArea(
          child: Padding(
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
        color: Theme.of(context).colorScheme.error,
      );
    }

    if (_isSaving) {
      return _EditorSaveStatus(
        icon: Icons.sync,
        label: 'Saving locally...',
        color: Theme.of(context).colorScheme.primary,
      );
    }

    if (_hasUnsavedChanges) {
      return _EditorSaveStatus(
        icon: Icons.edit_outlined,
        label: 'Unsaved changes',
        color: Theme.of(context).colorScheme.primary,
      );
    }

    if (_persistedNote == null) {
      return _EditorSaveStatus(
        icon: Icons.edit_note_outlined,
        label: 'Start typing to create this note',
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );
    }

    return _EditorSaveStatus(
      icon: Icons.check_circle_outline,
      label: 'All changes saved',
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
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
          return line;
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

  void _insertCodeSnippet() {
    _contentFocusNode.requestFocus();
    final text = _contentController.text;
    final selection = _validSelection(text);
    final selectedText = selection.textInside(text);
    final replacement = selectedText.isEmpty
        ? '[code]\n\n[/code]'
        : '[code]\n$selectedText\n[/code]';
    final updatedText =
        selection.textBefore(text) + replacement + selection.textAfter(text);
    final cursorOffset = selectedText.isEmpty
        ? selection.start + 7
        : selection.start + replacement.length;

    _contentController.value = TextEditingValue(
      text: updatedText,
      selection: TextSelection.collapsed(offset: cursorOffset),
    );
  }

  Future<void> _copyCurrentCodeSnippet() async {
    final snippet = _contentController.currentCodeSnippet;
    if (snippet == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Place the cursor inside a code snippet to copy it.'),
        ),
      );
      return;
    }

    await Clipboard.setData(ClipboardData(text: snippet.code));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          snippet.language.isEmpty
              ? 'Code snippet copied'
              : '${snippet.language.toUpperCase()} snippet copied',
        ),
      ),
    );
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
    if (!selection.isValid) {
      return TextSelection.collapsed(offset: text.length);
    }
    return selection;
  }

  String _leadingWhitespace(String text) {
    final match = RegExp(r'^\s*').firstMatch(text);
    return match?.group(0) ?? '';
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
    required this.title,
    required this.derivedTitle,
    required this.manualTitleIsEmpty,
    required this.titleController,
    required this.titleFocusNode,
    required this.contentController,
    required this.contentFocusNode,
    required this.isSaving,
    required this.status,
    required this.canRetrySave,
    required this.embedded,
    required this.onRetrySave,
    required this.onClose,
    required this.applyHeading,
    required this.toggleBulletList,
    required this.toggleQuote,
    required this.insertCodeSnippet,
    required this.copyCurrentCodeSnippet,
    required this.onContentTap,
  });

  final String title;
  final String derivedTitle;
  final bool manualTitleIsEmpty;
  final TextEditingController titleController;
  final FocusNode titleFocusNode;
  final TextEditingController contentController;
  final FocusNode contentFocusNode;
  final bool isSaving;
  final _EditorSaveStatus status;
  final bool canRetrySave;
  final bool embedded;
  final Future<bool> Function() onRetrySave;
  final Future<void> Function()? onClose;
  final void Function(int level) applyHeading;
  final VoidCallback toggleBulletList;
  final VoidCallback toggleQuote;
  final VoidCallback insertCodeSnippet;
  final Future<void> Function() copyCurrentCodeSnippet;
  final VoidCallback onContentTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDesktopEmbedded = embedded;

    return Column(
      children: [
        if (onClose != null) ...[
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              onPressed: onClose,
              tooltip: 'Close editor',
              icon: const Icon(Icons.close),
            ),
          ),
          const SizedBox(height: 2),
        ],
        TextField(
          controller: titleController,
          focusNode: titleFocusNode,
          decoration: isDesktopEmbedded
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
        const SizedBox(height: 16),
        if (isDesktopEmbedded)
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _EditorCommandButton(
                  label: 'Code',
                  onPressed: insertCodeSnippet,
                ),
                _EditorCommandButton(
                  label: 'Copy code',
                  onPressed: () {
                    unawaited(copyCurrentCodeSnippet());
                  },
                ),
              ],
            ),
          ),
        if (isDesktopEmbedded) const SizedBox(height: 12),
        if (!isDesktopEmbedded)
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
                  label: 'List',
                  onPressed: toggleBulletList,
                ),
                _EditorCommandButton(
                  label: 'Quote',
                  onPressed: toggleQuote,
                ),
                _EditorCommandButton(
                  label: 'Code',
                  onPressed: insertCodeSnippet,
                ),
              ],
            ),
          ),
        SizedBox(height: isDesktopEmbedded ? 8 : 16),
        Expanded(
          child: _MarkdownEditorPane(
            controller: contentController,
            focusNode: contentFocusNode,
            embedded: embedded,
            onTap: onContentTap,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Icon(
                    status.icon,
                    size: 18,
                    color: status.color,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      status.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: status.color,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            if (canRetrySave)
              TextButton(
                onPressed: isSaving ? null : onRetrySave,
                child: const Text('Retry'),
              ),
          ],
        ),
      ],
    );
  }
}

class _EditorSaveStatus {
  const _EditorSaveStatus({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
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

class _MarkdownEditingController extends TextEditingController {
  _MarkdownEditingController({super.text});

  _CodeSnippetSelection? get currentCodeSnippet {
    final lines = text.split('\n');
    if (lines.isEmpty) {
      return null;
    }

    final currentLineIndex = _activeLineIndex.clamp(0, lines.length - 1);
    var start = -1;
    for (var index = currentLineIndex; index >= 0; index--) {
      final trimmed = lines[index].trim();
      if (_isCodeSnippetClosingTag(trimmed)) {
        return null;
      }
      final language = _codeSnippetLanguage(trimmed);
      if (language != null) {
        start = index;
        break;
      }
    }

    if (start == -1) {
      return null;
    }

    final language = _codeSnippetLanguage(lines[start].trim()) ?? '';
    for (var index = start + 1; index < lines.length; index++) {
      final trimmed = lines[index].trim();
      if (_codeSnippetLanguage(trimmed) != null) {
        return null;
      }
      if (_isCodeSnippetClosingTag(trimmed)) {
        final code = lines.sublist(start + 1, index).join('\n');
        return _CodeSnippetSelection(language: language, code: code);
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
    final activeLineIndex = _activeLineIndex;
    var isInsideCodeSnippet = false;

    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final trimmed = line.trim();
      final codeSnippetLanguage = _codeSnippetLanguage(trimmed);
      final isCodeSnippetOpeningTag = codeSnippetLanguage != null;
      final isCodeSnippetClosingTag = _isCodeSnippetClosingTag(trimmed);
      spans.add(
        _buildLineSpan(
          line,
          baseStyle,
          context,
          isActiveLine: index == activeLineIndex,
          isInsideCodeSnippet: isInsideCodeSnippet,
          isCodeSnippetOpeningTag: isCodeSnippetOpeningTag,
          isCodeSnippetClosingTag: isCodeSnippetClosingTag,
          codeSnippetLanguage: codeSnippetLanguage ?? '',
        ),
      );
      if (isCodeSnippetOpeningTag) {
        isInsideCodeSnippet = true;
      } else if (isCodeSnippetClosingTag) {
        isInsideCodeSnippet = false;
      }
      if (index < lines.length - 1) {
        spans.add(TextSpan(text: '\n', style: baseStyle));
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
  }) {
    if (isActiveLine) {
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
      ),
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

@visibleForTesting
List<InlineSpan> buildInactiveMarkdownLineSpans(
  String line, {
  required TextStyle baseStyle,
  required ColorScheme colorScheme,
  bool isInsideCodeSnippet = false,
  bool isCodeSnippetOpeningTag = false,
  bool isCodeSnippetClosingTag = false,
  String codeSnippetLanguage = '',
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

  final headingMatch = RegExp(r'^(#{1,3})(\s+)(.*)$').firstMatch(trimmedLeft);
  if (headingMatch != null) {
    final hashes = headingMatch.group(1)!;
    final spacing = headingMatch.group(2)!;
    final content = headingMatch.group(3)!;
    final level = hashes.length;
    final headingStyle = switch (level) {
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

    return [
      if (indent.isNotEmpty) TextSpan(text: indent, style: baseStyle),
      TextSpan(
        text: hashes,
        style: headingStyle.copyWith(
          color: Colors.transparent,
          fontSize: 0.1,
          height: 1,
        ),
      ),
      TextSpan(
        text: spacing,
        style: headingStyle.copyWith(
          color: Colors.transparent,
          fontSize: 0.1,
          height: 1,
        ),
      ),
      TextSpan(
        text: content,
        style: headingStyle.copyWith(color: colorScheme.onSurface),
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
      TextSpan(
        text: content,
        style: baseStyle.copyWith(color: colorScheme.onSurface),
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
      TextSpan(
        text: content,
        style: baseStyle.copyWith(
          color: colorScheme.onSurface,
          fontStyle: FontStyle.italic,
        ),
      ),
    ];
  }

  return [
    TextSpan(
      text: line,
      style: baseStyle.copyWith(color: colorScheme.onSurface),
    ),
  ];
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
  final codeStyle = baseStyle.copyWith(
    color: colorScheme.onSurface,
    fontFamily: 'monospace',
    backgroundColor: colorScheme.surfaceContainerHigh,
  );

  if (isCodeSnippetOpeningTag) {
    return [
      if (indent.isNotEmpty) TextSpan(text: indent, style: baseStyle),
      TextSpan(
        text: codeSnippetLanguage.isEmpty
            ? '[CODE]'
            : '[${codeSnippetLanguage.toUpperCase()}]',
        style: chipStyle,
      ),
    ];
  }

  if (isCodeSnippetClosingTag) {
    return [
      if (indent.isNotEmpty) TextSpan(text: indent, style: baseStyle),
      TextSpan(text: '[/CODE]', style: chipStyle),
    ];
  }

  return [
    if (indent.isNotEmpty) TextSpan(text: indent, style: baseStyle),
    TextSpan(text: trimmedLeft, style: codeStyle),
  ];
}

class _CodeSnippetSelection {
  const _CodeSnippetSelection({
    required this.language,
    required this.code,
  });

  final String language;
  final String code;
}

bool _isCodeSnippetClosingTag(String line) {
  return line == '[/code]';
}

String? _codeSnippetLanguage(String line) {
  final match = RegExp(r'^\[code(?::([^\]\s]+))?\]$').firstMatch(line);
  return match?.group(1)?.trim() ?? (match != null ? '' : null);
}

class _MarkdownEditorPane extends StatelessWidget {
  const _MarkdownEditorPane({
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
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color:
            embedded ? Colors.transparent : colorScheme.surfaceContainerLowest,
        borderRadius: embedded ? BorderRadius.zero : BorderRadius.circular(16),
        border: embedded ? null : Border.all(color: colorScheme.outlineVariant),
      ),
      child: _DocumentBlocksEditor(
        controller: controller,
        focusNode: focusNode,
        embedded: embedded,
        onTap: onTap,
      ),
    );
  }
}

class _DocumentBlocksEditor extends StatefulWidget {
  const _DocumentBlocksEditor({
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

  @override
  void initState() {
    super.initState();
    _rebuildBlocksFromMasterText();
    widget.controller.addListener(_handleMasterChanged);
    widget.focusNode.addListener(_syncMasterFromBlocks);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleMasterChanged);
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
        block.controller.addListener(_syncMasterFromBlocks);
        block.focusNode.addListener(_syncMasterFromBlocks);
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
    return !listEquals(currentStructure, nextStructure);
  }

  void _syncBlockTextsFromMaster(List<NoteBlock> parsedBlocks) {
    _syncingFromMaster = true;
    try {
      for (var index = 0; index < _blocks.length && index < parsedBlocks.length; index++) {
        _blocks[index].syncFromNoteBlock(parsedBlocks[index]);
      }
    } finally {
      _syncingFromMaster = false;
    }
  }

  void _syncSelectionsFromMaster() {
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
        final localOffset =
            block.localSelectionOffset((targetOffset - consumed).clamp(0, length));
        if (block.controller.selection.baseOffset != localOffset ||
            block.controller.selection.extentOffset != localOffset) {
          block.controller.selection =
              TextSelection.collapsed(offset: localOffset);
        }
        return;
      }

      consumed = rangeEnd;
    }
  }

  void _syncMasterFromBlocks() {
    if (_syncingFromMaster) {
      return;
    }

    final text = _blocks.map((block) => block.rawText).join('\n\n');
    final focusedIndex =
        _blocks.indexWhere((block) => block.focusNode.hasFocus);
    final effectiveFocusedIndex = widget.focusNode.hasFocus ? 0 : focusedIndex;
    var selectionOffset = text.length;

    if (effectiveFocusedIndex != -1) {
      var consumed = 0;
      for (var index = 0; index < effectiveFocusedIndex; index++) {
        consumed += _blocks[index].rawText.length + 2;
      }
      final activeSelection =
          _blocks[effectiveFocusedIndex].controller.selection;
      final localOffset = activeSelection.isValid
          ? activeSelection.extentOffset.clamp(
              0,
              _blocks[effectiveFocusedIndex].controller.text.length,
            )
          : _blocks[effectiveFocusedIndex].controller.text.length;
      selectionOffset =
          consumed + _blocks[effectiveFocusedIndex].rawSelectionOffset(localOffset);
    }

    _syncingToMaster = true;
    try {
      widget.controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: selectionOffset),
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

  bool _matchesMasterStructure(String text) {
    final parsedSignatures = blocksFromEditableText(text)
        .map(_DocumentEditorBlock.structureSignatureForNoteBlock)
        .toList(growable: false);
    final currentSignatures =
        _blocks.map((block) => block.structureSignature).toList(growable: false);
    return listEquals(currentSignatures, parsedSignatures);
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6);
    final padding = widget.embedded
        ? const EdgeInsets.only(top: 8, right: 4, bottom: 8)
        : const EdgeInsets.all(18);

    return ListView.separated(
      key: const ValueKey('document-block-editor'),
      padding: padding,
      itemCount: _blocks.length,
      separatorBuilder: (context, _) => const SizedBox(height: 18),
      itemBuilder: (context, index) {
        final block = _blocks[index];
        final focusNode = index == 0 ? widget.focusNode : block.focusNode;
        if (block.isCode) {
          return _CodeEditorBlockCard(
            block: block,
            focusNode: focusNode,
            onTap: widget.onTap,
          );
        }

        return TextField(
          controller: block.controller,
          focusNode: focusNode,
          onTap: widget.onTap,
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
        );
      },
    );
  }
}

class _DocumentEditorBlock {
  const _DocumentEditorBlock({
    required this.controller,
    required this.focusNode,
    required this.isCode,
    required this.language,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isCode;
  final String language;

  factory _DocumentEditorBlock.fromNoteBlock(
    NoteBlock block, {
    required FocusNode focusNode,
  }) {
    return switch (block) {
      ParagraphBlock(:final text) => _DocumentEditorBlock(
          controller: _MarkdownEditingController(text: text),
          focusNode: focusNode,
          isCode: false,
          language: '',
        ),
      CodeBlock(:final language, :final code) => _DocumentEditorBlock(
          controller: TextEditingController(text: code),
          focusNode: focusNode,
          isCode: true,
          language: language,
        ),
      _ => _DocumentEditorBlock(
          controller: _MarkdownEditingController(text: ''),
          focusNode: focusNode,
          isCode: false,
          language: '',
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
      ? 'code|$language|${controller.text}'
      : 'paragraph|${controller.text}';

  String get structureSignature => isCode ? 'code|$language' : 'paragraph';

  String get openingTag =>
      language.isEmpty ? '[code]' : '[code:$language]';

  String get rawText => isCode
      ? '$openingTag\n${controller.text}\n[/code]'
      : controller.text;

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
      CodeBlock(:final code, :final language) when isCode && language == this.language => code,
      _ => controller.text,
    };

    if (controller.text == nextText) {
      return;
    }

    final safeOffset =
        controller.selection.extentOffset.clamp(0, nextText.length);
    controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: safeOffset),
    );
  }

  void dispose() {
    controller.dispose();
    focusNode.dispose();
  }
}

class _CodeEditorBlockCard extends StatelessWidget {
  const _CodeEditorBlockCard({
    required this.block,
    required this.focusNode,
    required this.onTap,
  });

  final _DocumentEditorBlock block;
  final FocusNode focusNode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      key: ValueKey('code-block-editor-${block.language}-${block.controller.text.length}'),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                block.language.isEmpty ? 'CODE' : block.language.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              TextButton.icon(
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
                        block.language.isEmpty
                            ? 'Code snippet copied'
                            : '${block.language.toUpperCase()} snippet copied',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.content_copy_outlined, size: 16),
                label: const Text('Copy'),
              ),
            ],
          ),
          TextField(
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
              color: colorScheme.onSurface,
              height: 1.5,
            ),
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            textAlignVertical: TextAlignVertical.top,
            minLines: 1,
            maxLines: null,
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
