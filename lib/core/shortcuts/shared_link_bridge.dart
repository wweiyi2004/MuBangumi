import 'dart:io';
import 'package:flutter/services.dart';

class SharedLinkBridge {
  SharedLinkBridge({bool? enabled}) : _enabled = enabled ?? Platform.isAndroid;
  static const channel = MethodChannel('mubangumi/shared_links');
  final bool _enabled;
  bool _disposed = false;
  bool _draining = false;
  bool _drainRequested = false;
  void Function(String)? _onText;
  Future<void> bind(void Function(String) onText) async {
    _onText = onText;
    if (!_enabled) return;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'available') await _drain(onText);
    });
    await _drain(onText);
  }

  Future<void> resume() async {
    final onText = _onText;
    if (_enabled && onText != null) await _drain(onText);
  }

  Future<void> _drain(void Function(String) onText) async {
    if (_disposed) return;
    if (_draining) {
      _drainRequested = true;
      return;
    }
    _draining = true;
    try {
      while (!_disposed) {
        final text = await channel.invokeMethod<String>('takePendingText');
        if (_disposed || text == null) break;
        onText(text);
      }
    } on MissingPluginException {
      // Not available in desktop or test runners.
    } on PlatformException {
      // Leave the native queue available for the next resume.
    } finally {
      _draining = false;
      if (_drainRequested && !_disposed) {
        _drainRequested = false;
        await _drain(onText);
      }
    }
  }

  void dispose() {
    _disposed = true;
    if (_enabled) channel.setMethodCallHandler(null);
  }
}
