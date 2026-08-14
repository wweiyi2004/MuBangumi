import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// User wallpaper + layered frosted-glass presentation settings.
@immutable
class AppBackgroundSettings {
  const AppBackgroundSettings({
    this.enabled = false,
    this.imagePath,
    this.blur = 22,
    this.dim = 0.32,
    this.glass = 0.42,
  });

  final bool enabled;
  final String? imagePath;

  /// Backdrop blur strength for the frosted veil (0–40).
  final double blur;

  /// Darkening over the photo (0–0.75).
  final double dim;

  /// Opacity of glass panels / translucent surfaces (0.15–0.8).
  final double glass;

  bool get hasImage =>
      imagePath != null &&
      imagePath!.trim().isNotEmpty &&
      File(imagePath!).existsSync();

  bool get isActive => enabled && hasImage;

  AppBackgroundSettings copyWith({
    bool? enabled,
    String? imagePath,
    bool clearImage = false,
    double? blur,
    double? dim,
    double? glass,
  }) => AppBackgroundSettings(
    enabled: enabled ?? this.enabled,
    imagePath: clearImage ? null : imagePath ?? this.imagePath,
    blur: blur ?? this.blur,
    dim: dim ?? this.dim,
    glass: glass ?? this.glass,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'imagePath': imagePath,
    'blur': blur,
    'dim': dim,
    'glass': glass,
  };

  factory AppBackgroundSettings.fromJson(Map<String, dynamic> json) {
    return AppBackgroundSettings(
      enabled: json['enabled'] == true,
      imagePath: json['imagePath']?.toString(),
      blur: _clampDouble(json['blur'], 22, 0, 40),
      dim: _clampDouble(json['dim'], 0.32, 0, 0.75),
      glass: _clampDouble(json['glass'], 0.42, 0.15, 0.8),
    );
  }

  static double _clampDouble(
    Object? value,
    double fallback,
    double min,
    double max,
  ) {
    final n = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? fallback;
    return n.clamp(min, max);
  }
}

class BackgroundController extends StateNotifier<AppBackgroundSettings> {
  BackgroundController(this._storage) : super(const AppBackgroundSettings()) {
    _restore();
  }

  static const _key = 'app_background_settings_v1';
  final FlutterSecureStorage _storage;

  Future<void> _restore() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final next = AppBackgroundSettings.fromJson(
          Map<String, dynamic>.from(decoded),
        );
        // Drop stale path if file vanished.
        state = next.hasImage || next.imagePath == null
            ? next
            : next.copyWith(clearImage: true, enabled: false);
      }
    } catch (error) {
      debugPrint('BackgroundController restore failed: $error');
    }
  }

  Future<void> _persist() async {
    try {
      await _storage.write(key: _key, value: jsonEncode(state.toJson()));
    } catch (error) {
      debugPrint('BackgroundController persist failed: $error');
    }
  }

  Future<void> setEnabled(bool enabled) async {
    if (enabled && !state.hasImage) return;
    state = state.copyWith(enabled: enabled);
    await _persist();
  }

  Future<void> setBlur(double blur) async {
    state = state.copyWith(blur: blur.clamp(0, 40));
    await _persist();
  }

  Future<void> setDim(double dim) async {
    state = state.copyWith(dim: dim.clamp(0, 0.75));
    await _persist();
  }

  Future<void> setGlass(double glass) async {
    state = state.copyWith(glass: glass.clamp(0.15, 0.8));
    await _persist();
  }

  /// Opens system file picker and installs the image as wallpaper.
  Future<String?> pickAndSetImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: false,
    );
    final path = result?.files.single.path;
    if (path == null || path.isEmpty) return null;
    return setImageFromPath(path);
  }

  Future<String?> setImageFromPath(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw StateError('找不到所选图片');
    }
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'backgrounds'));
    await dir.create(recursive: true);
    final ext = p.extension(sourcePath).toLowerCase();
    final safeExt = switch (ext) {
      '.png' || '.jpg' || '.jpeg' || '.webp' || '.gif' || '.bmp' => ext,
      _ => '.jpg',
    };
    final target = File(
      p.join(
        dir.path,
        'wallpaper_${DateTime.now().millisecondsSinceEpoch}$safeExt',
      ),
    );
    await source.copy(target.path);

    // Remove previous managed wallpaper copies (keep only newest).
    final previous = state.imagePath;
    state = state.copyWith(imagePath: target.path, enabled: true);
    await _persist();
    if (previous != null &&
        previous != target.path &&
        previous.contains('${p.separator}backgrounds${p.separator}')) {
      try {
        final old = File(previous);
        if (await old.exists()) await old.delete();
      } catch (_) {}
    }
    return target.path;
  }

  Future<void> clearImage() async {
    final previous = state.imagePath;
    state = state.copyWith(clearImage: true, enabled: false);
    await _persist();
    if (previous != null &&
        previous.contains('${p.separator}backgrounds${p.separator}')) {
      try {
        final file = File(previous);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }
}

final backgroundSettingsProvider =
    StateNotifierProvider<BackgroundController, AppBackgroundSettings>((ref) {
      return BackgroundController(const FlutterSecureStorage());
    });
