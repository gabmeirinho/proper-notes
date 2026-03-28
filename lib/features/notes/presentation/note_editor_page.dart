import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/create_note.dart';
import '../application/update_note.dart';
import '../domain/note.dart';

class NoteEditorPage extends StatefulWidget {
  const NoteEditorPage({
    required this.createNote,
    required this.updateNote,
    this.note,
    super.key,
  });

  final CreateNote createNote;
  final UpdateNote updateNote;
  final Note? note;

  bool get isEditing => note != null;

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  late final FocusNode _contentFocusNode;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note?.title ?? '');
    _contentController = TextEditingController(text: widget.note?.content ?? '');
    _contentFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _contentFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isEditing ? 'Edit Note' : 'New Note';

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyS, control: true):
            _SaveNoteIntent(),
        SingleActivator(LogicalKeyboardKey.keyS, meta: true): _SaveNoteIntent(),
        SingleActivator(LogicalKeyboardKey.escape): _CloseEditorIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _SaveNoteIntent: CallbackAction<_SaveNoteIntent>(
            onInvoke: (_) => _isSaving ? null : _save(),
          ),
          _CloseEditorIntent: CallbackAction<_CloseEditorIntent>(
            onInvoke: (_) {
              Navigator.of(context).maybePop();
              return null;
            },
          ),
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(title),
            actions: [
              TextButton.icon(
                onPressed: _isSaving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save'),
              ),
            ],
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Markdown note. Shortcuts: Ctrl/Cmd+S to save, Esc to close',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => _contentFocusNode.requestFocus(),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: TextField(
                      controller: _contentController,
                      focusNode: _contentFocusNode,
                      decoration: const InputDecoration(
                        labelText: 'Markdown',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                      expands: true,
                      maxLines: null,
                      minLines: null,
                      textAlignVertical: TextAlignVertical.top,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isSaving ? null : _save,
                      child: Text(_isSaving ? 'Saving...' : 'Save'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
    });

    try {
      final title = _titleController.text.trim();
      final content = _contentController.text;

      if (widget.note == null) {
        await widget.createNote(
          title: title,
          content: content,
        );
      } else {
        await widget.updateNote(
          original: widget.note!,
          title: title,
          content: content,
        );
      }

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop();
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }
}

class _SaveNoteIntent extends Intent {
  const _SaveNoteIntent();
}

class _CloseEditorIntent extends Intent {
  const _CloseEditorIntent();
}
