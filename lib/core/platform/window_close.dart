import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../storage/pending_personal_writes.dart';

/// The native close request waits for local durability, never a network POST.
abstract final class WindowCloseCoordinator {
  static const _channel = MethodChannel('mubangumi/window_lifecycle');
  static final _guards = <Future<bool> Function()>{};
  static bool _initialized = false;

  static VoidCallback register(Future<bool> Function() save) {
    _guards.add(save);
    return () => _guards.remove(save);
  }

  static Future<bool> prepareToClose() async {
    try {
      return await (() async {
        final saved = await Future.wait([
          for (final save in _guards.toList()) save(),
        ]);
        if (saved.any((value) => !value)) return false;
        await PendingPersonalWrites.drainAll();
        return true;
      })().timeout(const Duration(seconds: 8));
    } catch (_) {
      return false;
    }
  }

  static Future<void> initialize() async {
    if (!Platform.isWindows || _initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'prepareToClose') return;
      final saved = await prepareToClose();
      await _channel.invokeMethod<void>(saved ? 'closeReady' : 'closeFailed');
    });
    try {
      await _channel.invokeMethod<void>('ready');
    } catch (_) {
      debugPrint('Window close coordination is unavailable in this runner');
    }
  }
}
