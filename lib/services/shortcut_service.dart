import 'dart:io';
import 'package:flutter/services.dart';

class ShortcutService {
  ShortcutService._() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onShortcutLaunched') {
        final toolId = call.arguments as String?;
        if (toolId != null && _onToolLaunched != null) {
          _onToolLaunched!(toolId);
        }
      }
    });
  }

  static final ShortcutService instance = ShortcutService._();
  static const _channel = MethodChannel('pdfnova/widget_shortcut');

  void Function(String toolId)? _onToolLaunched;

  void listenToolLaunch(void Function(String toolId) callback) {
    _onToolLaunched = callback;
  }

  /// Requests Android launcher to pin the App Widget to the Home Screen
  Future<bool> pinShortcut(String toolId, String title) async {
    if (!Platform.isAndroid) return false;
    try {
      final bool? result = await _channel.invokeMethod('pinShortcut', {
        'toolId': toolId,
        'title': title,
      });
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Checks if app was launched directly from a Home Screen Widget shortcut
  Future<String?> getInitialShortcut() async {
    if (!Platform.isAndroid) return null;
    try {
      final String? toolId = await _channel.invokeMethod('getInitialShortcut');
      return toolId;
    } catch (_) {
      return null;
    }
  }
}
