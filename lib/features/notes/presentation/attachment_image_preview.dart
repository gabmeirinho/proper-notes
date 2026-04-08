import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/utils/attachments.dart';

class AttachmentImagePreview extends StatefulWidget {
  const AttachmentImagePreview({
    required this.attachmentUri,
    this.altText = '',
    this.maxWidth = 420,
    this.maxHeight = 260,
    this.compact = false,
    this.ignorePointer = false,
    this.selected = false,
    super.key,
  });

  final String attachmentUri;
  final String altText;
  final double maxWidth;
  final double maxHeight;
  final bool compact;
  final bool ignorePointer;
  final bool selected;

  @override
  State<AttachmentImagePreview> createState() => _AttachmentImagePreviewState();
}

class _AttachmentImagePreviewState extends State<AttachmentImagePreview> {
  File? _resolvedFile;

  @override
  void initState() {
    super.initState();
    _resolveAttachment();
  }

  @override
  void didUpdateWidget(covariant AttachmentImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachmentUri != widget.attachmentUri) {
      _resolveAttachment();
    }
  }

  Future<void> _resolveAttachment() async {
    final file = await resolveAttachmentFile(widget.attachmentUri);
    if (!mounted) {
      return;
    }

    setState(() {
      _resolvedFile = file;
    });
  }

  @override
  Widget build(BuildContext context) {
    final child = _resolvedFile == null
        ? _buildMissingAttachment(context)
        : FutureBuilder<bool>(
            future: _resolvedFile!.exists(),
            builder: (context, snapshot) {
              if (snapshot.data != true) {
                return _buildMissingAttachment(context);
              }
              return _buildImage(context, _resolvedFile!);
            },
          );

    return IgnorePointer(
      ignoring: widget.ignorePointer,
      child: child,
    );
  }

  Widget _buildImage(BuildContext context, File file) {
    final borderRadius = BorderRadius.circular(widget.compact ? 10 : 14);
    final child = ClipRRect(
      borderRadius: borderRadius,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: widget.maxWidth,
          maxHeight: widget.maxHeight,
        ),
        child: Image.file(
          file,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _buildMissingAttachment(context),
        ),
      ),
    );

    if (!widget.selected) {
      return child;
    }

    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        border: Border.all(color: colorScheme.primary, width: 3),
      ),
      child: child,
    );
  }

  Widget _buildMissingAttachment(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final label =
        widget.altText.trim().isEmpty ? 'Missing image' : widget.altText.trim();

    return Container(
      constraints: BoxConstraints(
        maxWidth: widget.maxWidth,
        minHeight: widget.compact ? 72 : 96,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: widget.compact ? 10 : 14,
        vertical: widget.compact ? 10 : 14,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(widget.compact ? 10 : 14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_not_supported_outlined, color: colorScheme.outline),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
