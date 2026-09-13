import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/diagnostics/background_diagnostics.dart';

class SystemAppearance {
  const SystemAppearance({
    this.highContrast = false,
    this.transparency = true,
    this.batterySaver = false,
    this.background,
    this.foreground,
    this.highlight,
    this.onHighlight,
  });
  final bool highContrast, transparency, batterySaver;
  final int? background, foreground, highlight, onHighlight;
  bool get reduceEffects => highContrast || !transparency || batterySaver;

  factory SystemAppearance.fromMap(Map<Object?, Object?> map) =>
      SystemAppearance(
        highContrast: map['highContrast'] == true,
        transparency: map['transparency'] != false,
        batterySaver: map['batterySaver'] == true,
        background: map['background'] as int?,
        foreground: map['foreground'] as int?,
        highlight: map['highlight'] as int?,
        onHighlight: map['onHighlight'] as int?,
      );
}

class SystemAppearanceController extends StateNotifier<SystemAppearance> {
  SystemAppearanceController({bool? supported})
    : super(const SystemAppearance()) {
    if (!(supported ?? Platform.isWindows)) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') await reload();
    });
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(reload()));
    unawaited(reload());
  }

  static const _channel = MethodChannel('mubangumi/system_appearance');
  AppLifecycleListener? _lifecycle;
  bool _listening = false;
  int _generation = 0;

  Future<void> reload() async {
    BackgroundDiagnostics.record('appearance_read_start');
    final generation = ++_generation;
    try {
      final data = await _channel.invokeMapMethod<Object?, Object?>('read');
      if (mounted && generation == _generation && data != null) {
        state = SystemAppearance.fromMap(data);
      }
    } on MissingPluginException {
      // Other platforms use MediaQuery high contrast and the in-app setting.
    } on PlatformException {
      // Retain the last known system preference if a native read fails.
    } finally {
      BackgroundDiagnostics.record('appearance_read_end');
    }
  }

  @override
  void dispose() {
    _generation++;
    if (_listening) _channel.setMethodCallHandler(null);
    _lifecycle?.dispose();
    super.dispose();
  }
}

final systemAppearanceProvider =
    StateNotifierProvider<SystemAppearanceController, SystemAppearance>(
      (ref) => SystemAppearanceController(),
    );
