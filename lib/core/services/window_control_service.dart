import 'package:flutter/services.dart';

class WindowControlService {
  const WindowControlService();

  static const MethodChannel _channel =
      MethodChannel('proper_notes/window_control');

  Future<void> hideWindowForExit() async {
    try {
      await _channel.invokeMethod<void>('hideWindowForExit');
    } on MissingPluginException {
      // Non-desktop platforms do not expose this channel.
    }
  }
}
