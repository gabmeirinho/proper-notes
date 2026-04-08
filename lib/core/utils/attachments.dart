import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

const String kAttachmentUriScheme = 'attachment';

@visibleForTesting
Directory? debugAttachmentDirectoryOverride;

class AttachmentImageMarkdown {
  const AttachmentImageMarkdown({
    required this.altText,
    required this.attachmentUri,
    required this.rawText,
  });

  final String altText;
  final String attachmentUri;
  final String rawText;
}

class SavedAttachmentImage {
  const SavedAttachmentImage({
    required this.fileName,
    required this.attachmentUri,
    required this.file,
  });

  final String fileName;
  final String attachmentUri;
  final File file;
}

class DeleteAttachmentFileResult {
  const DeleteAttachmentFileResult({
    required this.fileName,
    required this.existed,
    required this.movedToTrash,
  });

  final String fileName;
  final bool existed;
  final bool movedToTrash;
}

AttachmentImageMarkdown? parseAttachmentImageMarkdownLine(String line) {
  final match =
      RegExp(r'^\s*!\[(.*?)\]\((attachment://[^)\s]+)\)\s*$').firstMatch(line);
  if (match == null) {
    return null;
  }

  return AttachmentImageMarkdown(
    altText: match.group(1) ?? '',
    attachmentUri: match.group(2)!,
    rawText: line,
  );
}

Future<Directory> getAttachmentsDirectory() async {
  final override = debugAttachmentDirectoryOverride;
  if (override != null) {
    await override.create(recursive: true);
    return override;
  }

  final supportDirectory = await getApplicationSupportDirectory();
  final directory = Directory(p.join(supportDirectory.path, 'attachments'));
  await directory.create(recursive: true);
  return directory;
}

Future<File?> resolveAttachmentFile(String attachmentUri) async {
  final fileName = attachmentFileNameFromUri(attachmentUri);
  if (fileName == null) {
    return null;
  }

  final directory = await getAttachmentsDirectory();
  return File(p.join(directory.path, fileName));
}

Future<Size?> readAttachmentImageSize(String attachmentUri) async {
  final file = await resolveAttachmentFile(attachmentUri);
  if (file == null || !await file.exists()) {
    return null;
  }

  final bytes = await file.readAsBytes();
  return decodeImageSize(bytes);
}

Future<Size?> decodeImageSize(Uint8List bytes) async {
  if (bytes.isEmpty) {
    return null;
  }

  try {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      try {
        return Size(
          frame.image.width.toDouble(),
          frame.image.height.toDouble(),
        );
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  } catch (_) {
    return null;
  }
}

String? attachmentFileNameFromUri(String attachmentUri) {
  final parsed = Uri.tryParse(attachmentUri);
  if (parsed == null || parsed.scheme != kAttachmentUriScheme) {
    return null;
  }

  final host = parsed.host.trim();
  final path = parsed.path.trim();
  final rawName =
      host.isNotEmpty ? host : path.replaceFirst(RegExp(r'^/+'), '');
  if (rawName.isEmpty) {
    return null;
  }

  return p.basename(rawName);
}

String buildAttachmentImageMarkdown(
  String attachmentUri, {
  String altText = '',
}) {
  return '![$altText]($attachmentUri)';
}

int countAttachmentReferencesInText(String text, String attachmentUri) {
  if (text.isEmpty || attachmentUri.isEmpty) {
    return 0;
  }

  return RegExp(RegExp.escape(attachmentUri)).allMatches(text).length;
}

Future<DeleteAttachmentFileResult> deleteAttachmentFile(
  String attachmentUri, {
  bool preferSystemTrash = true,
}) async {
  final fileName = attachmentFileNameFromUri(attachmentUri) ?? attachmentUri;
  final file = await resolveAttachmentFile(attachmentUri);
  if (file == null || !await file.exists()) {
    return DeleteAttachmentFileResult(
      fileName: fileName,
      existed: false,
      movedToTrash: false,
    );
  }

  if (preferSystemTrash &&
      debugAttachmentDirectoryOverride == null &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.linux) {
    try {
      final result = await Process.run('gio', <String>['trash', file.path]);
      if (result.exitCode == 0) {
        return DeleteAttachmentFileResult(
          fileName: fileName,
          existed: true,
          movedToTrash: true,
        );
      }
    } catch (_) {
      // Fall back to direct deletion when the desktop trash command is missing.
    }
  }

  await file.delete();
  return DeleteAttachmentFileResult(
    fileName: fileName,
    existed: true,
    movedToTrash: false,
  );
}

Future<SavedAttachmentImage> saveAttachmentImageBytes(
  Uint8List bytes, {
  required String extension,
}) async {
  final safeExtension = _sanitizeImageExtension(extension);
  final directory = await getAttachmentsDirectory();
  final fileName = '${const Uuid().v4()}.$safeExtension';
  final file = File(p.join(directory.path, fileName));
  await file.writeAsBytes(bytes, flush: true);

  return SavedAttachmentImage(
    fileName: fileName,
    attachmentUri: '$kAttachmentUriScheme://$fileName',
    file: file,
  );
}

String _sanitizeImageExtension(String extension) {
  final normalized = extension.toLowerCase().replaceAll('.', '').trim();
  return switch (normalized) {
    'jpg' || 'jpeg' => 'jpg',
    'png' => 'png',
    'webp' => 'webp',
    'gif' => 'gif',
    _ => 'png',
  };
}
