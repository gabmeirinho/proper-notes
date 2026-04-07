import 'dart:typed_data';

import 'package:flutter/services.dart';

class ClipboardImageData {
  const ClipboardImageData({
    required this.bytes,
    required this.extension,
  });

  final Uint8List bytes;
  final String extension;
}

class ClipboardImageService {
  static const MethodChannel _channel =
      MethodChannel('proper_notes/clipboard_image');

  static Future<ClipboardImageData?> readImage() async {
    try {
      final result =
          await _channel.invokeMapMethod<String, Object?>('getImage');
      if (result == null) {
        return null;
      }

      final bytes = result['bytes'];
      final extension = result['extension'];
      if (bytes is! Uint8List || extension is! String) {
        return null;
      }

      return ClipboardImageData(
        bytes: bytes,
        extension: extension,
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
