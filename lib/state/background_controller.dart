import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'system_appearance_controller.dart';
import '../core/diagnostics/background_diagnostics.dart';

enum BackgroundPreset { plain, soft, frosted }

@immutable
class AppBackgroundSettings {
  const AppBackgroundSettings({
    this.enabled = false,
    this.imagePath,
    this.blur = 22,
    this.dim = 0.32,
    this.glass = 0.42,
    this.reduceTransparency = false,
    this.ready = true,
    this.busy = false,
    this.saveError,
    this.appliedSettings,
  });
  final bool enabled;
  final String? imagePath;

  /// Background blur control, mapped linearly to sigma 0–18.
  final double blur;

  /// Wallpaper softening; light themes brighten and dark themes darken it.
  final double dim;

  /// Legacy 0.15–0.8 preference, mapped to safe navigation opacity 0.82–0.96.
  final double glass;
  final bool reduceTransparency, ready, busy;
  final String? saveError;

  /// During a slider gesture only the small preview uses the draft values.
  /// The app keeps this snapshot until release, dismissal or deactivation.
  final AppBackgroundSettings? appliedSettings;

  // Import and restore validate the path asynchronously, never during build.
  bool get hasImage => imagePath?.trim().isNotEmpty == true;
  bool get isActive => enabled && hasImage && !reduceTransparency;
  double get blurSigma => blur.clamp(0, 40) * .45;
  double get panelOpacity => .82 + ((glass - .15) / .65).clamp(0, 1) * .14;

  AppBackgroundSettings copyWith({
    bool? enabled,
    String? imagePath,
    bool clearImage = false,
    double? blur,
    double? dim,
    double? glass,
    bool? reduceTransparency,
    bool? ready,
    bool? busy,
    String? saveError,
    bool clearError = false,
    AppBackgroundSettings? appliedSettings,
    bool clearApplied = false,
  }) => AppBackgroundSettings(
    enabled: enabled ?? this.enabled,
    imagePath: clearImage ? null : imagePath ?? this.imagePath,
    blur: blur ?? this.blur,
    dim: dim ?? this.dim,
    glass: glass ?? this.glass,
    reduceTransparency: reduceTransparency ?? this.reduceTransparency,
    ready: ready ?? this.ready,
    busy: busy ?? this.busy,
    saveError: clearError ? null : saveError ?? this.saveError,
    appliedSettings: clearApplied
        ? null
        : appliedSettings ?? this.appliedSettings,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'imagePath': imagePath,
    'blur': blur,
    'dim': dim,
    'glass': glass,
    'reduceTransparency': reduceTransparency,
  };
  factory AppBackgroundSettings.fromJson(Map<String, dynamic> json) =>
      AppBackgroundSettings(
        enabled: json['enabled'] == true,
        imagePath: json['imagePath']?.toString(),
        blur: _number(json['blur'], 22, 0, 40),
        dim: _number(json['dim'], .32, 0, .75),
        glass: _number(json['glass'], .42, .15, .8),
        reduceTransparency: json['reduceTransparency'] == true,
      );
  static double _number(
    Object? value,
    double fallback,
    double min,
    double max,
  ) {
    final n = value is num ? value.toDouble() : double.tryParse('$value');
    return n == null || !n.isFinite ? fallback : n.clamp(min, max);
  }
}

class BackgroundController extends StateNotifier<AppBackgroundSettings> {
  BackgroundController(this._storage, {Future<Directory> Function()? directory})
    : _directory =
          directory ??
          (() async => Directory(
            p.join(
              (await getApplicationSupportDirectory()).path,
              'backgrounds',
            ),
          )),
      super(const AppBackgroundSettings(ready: false)) {
    ready = _restore();
    _lifecycle = AppLifecycleListener(onInactive: () => unawaited(flush()));
  }
  static const storageKey = 'app_background_settings_v1';
  final FlutterSecureStorage _storage;
  final Future<Directory> Function() _directory;
  late final Future<void> ready;
  late final AppLifecycleListener _lifecycle;
  Future<void> _writes = Future.value();
  Timer? _debounce;
  int _revision = 0, _imageGeneration = 0;

  Future<void> _restore() async {
    BackgroundDiagnostics.record('background_restore_start');
    final revision = _revision;
    try {
      final raw = await _storage.read(key: storageKey);
      if (raw == null || raw.isEmpty) return;
      var restored = AppBackgroundSettings.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
      if (restored.hasImage) {
        try {
          await _validateImage(restored.imagePath!, decodeOnly: true);
        } catch (_) {
          restored = restored.copyWith(
            clearImage: true,
            enabled: false,
            saveError: '原背景图片已失效，请重新选择图片',
          );
        }
      }
      if (mounted && revision == _revision) state = restored;
    } catch (_) {
      if (mounted && revision == _revision) {
        state = state.copyWith(saveError: '背景设置读取失败，请重新设置');
      }
    } finally {
      BackgroundDiagnostics.record('background_restore_end');
      if (mounted) state = state.copyWith(ready: true);
    }
  }

  void _change(AppBackgroundSettings next, {bool debounce = false}) {
    BackgroundDiagnostics.adjustment();
    _revision++;
    state = next.copyWith(clearError: true, clearApplied: !debounce);
    _debounce?.cancel();
    if (debounce && state.appliedSettings == null) {
      _debounce = Timer(
        const Duration(milliseconds: 250),
        () => unawaited(flush()),
      );
    }
  }

  void beginAdjustments() {
    BackgroundDiagnostics.record('drag_start');
    if (!state.ready || state.appliedSettings != null) return;
    _debounce?.cancel();
    state = state.copyWith(appliedSettings: state);
  }

  Future<bool> flush() {
    BackgroundDiagnostics.record('apply_start', {'revision': _revision});
    _debounce?.cancel();
    if (state.appliedSettings != null) {
      state = state.copyWith(clearApplied: true);
    }
    // Do not overwrite persisted preferences while the initial read is pending.
    if (!state.ready && _revision == 0) return Future.value(true);
    final revision = _revision;
    final encoded = jsonEncode(state.toJson());
    final result = Completer<bool>();
    _writes = _writes.then((_) async {
      final watch = BackgroundDiagnostics.enabled
          ? (Stopwatch()..start())
          : null;
      try {
        BackgroundDiagnostics.record('storage_write_start', {
          'revision': revision,
        });
        await _storage.write(key: storageKey, value: encoded);
        BackgroundDiagnostics.record('storage_write_end', {
          'revision': revision,
          'elapsedMs': watch?.elapsedMilliseconds,
        });
        if (mounted && revision == _revision) {
          state = state.copyWith(clearError: true);
        }
        result.complete(true);
      } catch (_) {
        BackgroundDiagnostics.record('storage_write_failed', {
          'revision': revision,
          'elapsedMs': watch?.elapsedMilliseconds,
        });
        if (mounted && revision == _revision) {
          state = state.copyWith(saveError: '设置已应用，但未能保存。请重试保存。');
        }
        result.complete(false);
      }
    });
    return result.future;
  }

  Future<void> setEnabled(bool enabled) async {
    if (enabled && !state.hasImage) return;
    _change(state.copyWith(enabled: enabled));
    await flush();
  }

  Future<void> setBlur(double value) async =>
      _change(state.copyWith(blur: value.clamp(0, 40)), debounce: true);
  Future<void> setDim(double value) async =>
      _change(state.copyWith(dim: value.clamp(0, .75)), debounce: true);
  Future<void> setGlass(double value) async =>
      _change(state.copyWith(glass: value.clamp(.15, .8)), debounce: true);
  Future<void> setReduceTransparency(bool value) async {
    _change(state.copyWith(reduceTransparency: value));
    await flush();
  }

  Future<void> applyPreset(BackgroundPreset preset) async {
    if (preset != BackgroundPreset.plain && !state.hasImage) return;
    _change(switch (preset) {
      BackgroundPreset.plain => state.copyWith(enabled: false),
      BackgroundPreset.soft => state.copyWith(
        enabled: true,
        blur: 10,
        dim: .5,
        glass: .7,
        reduceTransparency: false,
      ),
      BackgroundPreset.frosted => state.copyWith(
        enabled: true,
        blur: 22,
        dim: .32,
        glass: .42,
        reduceTransparency: false,
      ),
    });
    await flush();
  }

  Future<void> resetAdjustments() async {
    _change(state.copyWith(blur: 22, dim: .32, glass: .42));
    await flush();
  }

  Future<String?> pickAndSetImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: false,
    );
    final path = result?.files.single.path;
    return path == null || path.isEmpty ? null : setImageFromPath(path);
  }

  /// Decode before replacing the current wallpaper; store a bounded static PNG.
  Future<Uint8List?> _validateImage(
    String path, {
    bool decodeOnly = false,
  }) async {
    final source = File(path);
    if (!await source.exists()) throw StateError('找不到所选图片');
    if (await source.length() > 32 * 1024 * 1024) {
      throw StateError('请选择小于 32 MB 的图片');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(
      await source.readAsBytes(),
    );
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final limit = decodeOnly ? 64 : 2560;
      final scale = math.min(
        1.0,
        limit / math.max(descriptor.width, descriptor.height),
      );
      codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (descriptor.width * scale).round()),
        targetHeight: math.max(1, (descriptor.height * scale).round()),
      );
      image = (await codec.getNextFrame()).image;
      if (decodeOnly) return null;
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('无法读取所选图片');
      return bytes.buffer.asUint8List();
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }

  Future<String?> setImageFromPath(String sourcePath) async {
    final generation = ++_imageGeneration;
    _revision++;
    state = state.copyWith(busy: true, clearError: true);
    File? target;
    try {
      final bytes = await _validateImage(sourcePath);
      if (!mounted || generation != _imageGeneration) return null;
      final dir = await _directory();
      await dir.create(recursive: true);
      target = File(
        p.join(
          dir.path,
          'wallpaper_${DateTime.now().microsecondsSinceEpoch}.png',
        ),
      );
      await target.writeAsBytes(bytes!, flush: true);
      if (!mounted || generation != _imageGeneration) {
        await target.delete();
        return null;
      }
      final previous = state.imagePath;
      _change(
        state.copyWith(imagePath: target.path, enabled: true, busy: false),
      );
      if (await flush()) await _removeManaged(previous);
      return target.path;
    } finally {
      if (mounted && generation == _imageGeneration) {
        state = state.copyWith(busy: false);
      }
    }
  }

  Future<void> clearImage() async {
    _imageGeneration++;
    final previous = state.imagePath;
    _change(state.copyWith(clearImage: true, enabled: false, busy: false));
    if (await flush()) await _removeManaged(previous);
  }

  Future<void> _removeManaged(String? path) async {
    if (path == null) return;
    try {
      final dir = p.normalize(p.absolute((await _directory()).path));
      final full = p.normalize(p.absolute(path));
      if (!p.equals(p.dirname(full), dir) ||
          !RegExp(r'^wallpaper_\d+\.png$').hasMatch(p.basename(full))) {
        return;
      }
      final file = File(full);
      if (await file.exists()) await file.delete();
    } catch (_) {
      /* A leftover managed image does not prevent using the app. */
    }
  }

  @override
  void dispose() {
    if (_debounce?.isActive == true || state.appliedSettings != null) {
      unawaited(flush());
    }
    _debounce?.cancel();
    _imageGeneration++;
    _lifecycle.dispose();
    super.dispose();
  }
}

final backgroundSettingsProvider =
    StateNotifierProvider<BackgroundController, AppBackgroundSettings>(
      (ref) => BackgroundController(const FlutterSecureStorage()),
    );

final effectiveBackgroundProvider = Provider<AppBackgroundSettings>((ref) {
  final visual = ref.watch(
    backgroundSettingsProvider.select((draft) {
      final applied = draft.appliedSettings ?? draft;
      return (
        enabled: applied.enabled,
        imagePath: applied.imagePath,
        blur: applied.blur,
        dim: applied.dim,
        glass: applied.glass,
        reduceTransparency: applied.reduceTransparency,
      );
    }),
  );
  final reduceEffects = ref.watch(
    systemAppearanceProvider.select((system) => system.reduceEffects),
  );
  return AppBackgroundSettings(
    enabled: visual.enabled && !reduceEffects,
    imagePath: visual.imagePath,
    blur: visual.blur,
    dim: visual.dim,
    glass: visual.glass,
    reduceTransparency: visual.reduceTransparency,
  );
});

/// Wallpaper blur, veil and file changes must not rebuild MaterialApp themes.
final backgroundThemeSettingsProvider = Provider<AppBackgroundSettings>((ref) {
  final visual = ref.watch(
    effectiveBackgroundProvider.select(
      (settings) => (
        active: settings.isActive,
        glass: settings.isActive ? settings.glass : .42,
      ),
    ),
  );
  return AppBackgroundSettings(
    enabled: visual.active,
    // Theme material needs an active flag, never the actual wallpaper path.
    imagePath: visual.active ? 'theme-material' : null,
    glass: visual.glass,
  );
});
