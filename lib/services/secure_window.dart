import 'dart:io';
import 'package:flutter/services.dart';

/// Hides the app from the app-switcher preview and blocks screenshots
/// (Android FLAG_SECURE) while private content is on screen.
abstract final class SecureWindow {
  static const _channel = MethodChannel('pdfnova/window');

  static Future<void> set(bool on) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setSecure', {'on': on});
    } catch (_) {
      // Not fatal: the vault still locks; only the preview stays visible.
    }
  }
}
