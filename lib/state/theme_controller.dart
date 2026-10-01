import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ThemeController extends StateNotifier<ThemeMode> {
  ThemeController(this._storage) : super(ThemeMode.system) {
    ready = _restore();
  }

  static const _key = 'app_theme_mode';
  final FlutterSecureStorage _storage;
  late final Future<void> ready;
  int _revision = 0;
  Future<void> _writes = Future.value();

  Future<void> _restore() async {
    final revision = _revision;
    try {
      final raw = await _storage.read(key: _key);
      if (!mounted || revision != _revision) return;
      state = switch (raw) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    } catch (error) {
      debugPrint('ThemeController._restore failed: $error');
    }
  }

  Future<void> setMode(ThemeMode mode, {bool strict = false}) async {
    ++_revision;
    state = mode;
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    try {
      final write = _writes.then(
        (_) => _storage.write(key: _key, value: value),
      );
      _writes = write.then<void>((_) {}, onError: (Object _, StackTrace _) {});
      await write;
    } catch (error) {
      debugPrint('ThemeController.setMode persist failed: $error');
      if (strict) rethrow;
    }
  }
}

final themeModeProvider = StateNotifierProvider<ThemeController, ThemeMode>((
  ref,
) {
  return ThemeController(const FlutterSecureStorage());
});
