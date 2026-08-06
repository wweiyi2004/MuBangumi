import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ThemeController extends StateNotifier<ThemeMode> {
  ThemeController(this._storage) : super(ThemeMode.system) {
    _restore();
  }

  static const _key = 'app_theme_mode';
  final FlutterSecureStorage _storage;

  Future<void> _restore() async {
    try {
      final raw = await _storage.read(key: _key);
      state = switch (raw) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    } catch (_) {}
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    try {
      await _storage.write(key: _key, value: value);
    } catch (_) {}
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeController, ThemeMode>((ref) {
      return ThemeController(const FlutterSecureStorage());
    });
