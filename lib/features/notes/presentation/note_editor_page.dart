import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/markdown_title.dart';
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
    _contentController = _MarkdownEditingController(
      text: widget.note?.content ?? '',
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
          insertCodeBlock: _insertCodeBlock,
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
    return _EditorSnapshot(
      manualTitle: note.title,
      title: note.title,
      content: note.content,
      folderPath: note.folderPath,
    );
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

  void _insertCodeBlock() {
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
    required this.insertCodeBlock,
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
  final VoidCallback insertCodeBlock;
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
                  onPressed: insertCodeBlock,
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
    var isInsideCodeBlock = false;

    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final isCodeFenceLine = _isCodeFenceLine(line);
      spans.add(
        _buildLineSpan(
          line,
          baseStyle,
          context,
          isActiveLine: index == activeLineIndex,
          isInCodeBlock: isInsideCodeBlock || isCodeFenceLine,
          isCodeFenceLine: isCodeFenceLine,
        ),
      );
      if (isCodeFenceLine) {
        isInsideCodeBlock = !isInsideCodeBlock;
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
    required bool isInCodeBlock,
    required bool isCodeFenceLine,
  }) {
    if (isActiveLine) {
      return TextSpan(text: line, style: baseStyle);
    }

    return TextSpan(
      children: buildInactiveMarkdownLineSpans(
        line,
        baseStyle: baseStyle,
        colorScheme: Theme.of(context).colorScheme,
        isInCodeBlock: isInCodeBlock,
        isCodeFenceLine: isCodeFenceLine,
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

bool _isCodeFenceLine(String line) {
  return RegExp(r'^\s*```(?:\S+)?\s*$').hasMatch(line);
}

@visibleForTesting
List<InlineSpan> buildInactiveMarkdownLineSpans(
  String line, {
  required TextStyle baseStyle,
  required ColorScheme colorScheme,
  bool isInCodeBlock = false,
  bool isCodeFenceLine = false,
}) {
  if (isInCodeBlock) {
    return _buildInactiveCodeLineSpans(
      line,
      baseStyle: baseStyle,
      colorScheme: colorScheme,
      isCodeFenceLine: isCodeFenceLine,
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

List<InlineSpan> _buildInactiveCodeLineSpans(
  String line, {
  required TextStyle baseStyle,
  required ColorScheme colorScheme,
  required bool isCodeFenceLine,
}) {
  final trimmedLeft = line.trimLeft();
  final indent = line.substring(0, line.length - trimmedLeft.length);
  final codeStyle = baseStyle.copyWith(
    color: colorScheme.onSurface,
    fontFamily: 'monospace',
    backgroundColor: colorScheme.surfaceContainerHigh,
  );

  if (isCodeFenceLine) {
    final fenceMatch = RegExp(r'^(\s*)```(?:\s*(\S+))?\s*$').firstMatch(line);
    if (fenceMatch != null) {
      final fenceIndent = fenceMatch.group(1)!;
      final language = fenceMatch.group(2)?.trim() ?? '';
      return [
        if (fenceIndent.isNotEmpty)
          TextSpan(text: fenceIndent, style: baseStyle),
        if (language.isNotEmpty)
          TextSpan(
            text: language,
            style: codeStyle.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
      ];
    }
  }

  return [
    if (indent.isNotEmpty) TextSpan(text: indent, style: baseStyle),
    TextSpan(
      text: trimmedLeft,
      style: codeStyle,
    ),
  ];
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
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onTap: onTap,
        inputFormatters: const [
          _MarkdownListEditingFormatter(),
        ],
        decoration: InputDecoration(
          hintText: '# Untitled note\n\nStart writing in Markdown...',
          border: InputBorder.none,
          contentPadding: embedded
              ? const EdgeInsets.only(top: 8, right: 4, bottom: 8)
              : const EdgeInsets.all(18),
        ),
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              height: 1.6,
            ),
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        textAlignVertical: TextAlignVertical.top,
        expands: true,
        minLines: null,
        maxLines: null,
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
