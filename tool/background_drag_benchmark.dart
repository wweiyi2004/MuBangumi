// Run with: flutter run -d windows --profile -t tool/background_drag_benchmark.dart
// Defaults to generated imagery and in-memory preferences. REAL_APP restores
// the normal session; background edits still use an isolated test controller.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mubangumi/app.dart';
import 'package:mubangumi/core/theme/app_theme.dart';
import 'package:mubangumi/screens/background_settings_sheet.dart';
import 'package:mubangumi/state/background_controller.dart';
import 'package:mubangumi/state/system_appearance_controller.dart';
import 'package:mubangumi/state/session_controller.dart';
import 'package:mubangumi/widgets/app_background.dart';

import '../test/support/background_fixtures.dart';

final _frames = <String, List<ui.FrameTiming>>{};
String _phase = 'startup';
final _root = GlobalKey();
WidgetRef? _appRef;
final _storage = const bool.fromEnvironment('NATIVE_BACKGROUND_STORAGE')
    ? _NativeProbeStorage()
    : BackgroundTestStorage();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final directory = await Directory(
    '.dart_tool/background-benchmark',
  ).create(recursive: true);
  final image = await backgroundTestImage(
    directory,
    width: 2560,
    height: 1440,
    patterned: true,
  );
  var settings = AppBackgroundSettings(
    enabled: true,
    imagePath: image.absolute.path,
  );
  final imageInfo = <String, Object?>{};
  if (const bool.fromEnvironment('REAL_BACKGROUND_IMAGE')) {
    final raw = await const FlutterSecureStorage().read(
      key: BackgroundController.storageKey,
    );
    if (raw != null) {
      settings = AppBackgroundSettings.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    }
    imageInfo['savedBackgroundActive'] = settings.isActive;
    if (settings.hasImage) {
      final file = File(settings.imagePath!);
      imageInfo['bytes'] = await file.length();
      final buffer = await ui.ImmutableBuffer.fromUint8List(
        await file.readAsBytes(),
      );
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      imageInfo['width'] = descriptor.width;
      imageInfo['height'] = descriptor.height;
      descriptor.dispose();
      buffer.dispose();
    }
  }
  final controller = BackgroundTestController(settings, storage: _storage);
  await controller.ready;
  SchedulerBinding.instance.addTimingsCallback(
    (frames) => _frames.putIfAbsent(_phase, () => []).addAll(frames),
  );
  runApp(
    ProviderScope(
      overrides: [
        backgroundSettingsProvider.overrideWith((ref) => controller),
        if (!const bool.fromEnvironment('NATIVE_SYSTEM_APPEARANCE'))
          systemAppearanceProvider.overrideWith(
            (ref) => AppearanceTestController(),
          ),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          _appRef = ref;
          if (const bool.fromEnvironment('REAL_APP')) {
            return const MuBangumiApp();
          }
          final settings = ref.watch(backgroundThemeSettingsProvider);
          return MaterialApp(
            theme: applyBackgroundTheme(AppTheme.light, settings),
            builder: (_, child) => AppBackgroundHost(child: child!),
            home: Scaffold(
              key: _root,
              appBar: AppBar(title: const Text('毛玻璃拖动性能检查（测试图片）')),
              body: Builder(
                builder: (context) {
                  return Center(
                    child: FilledButton(
                      onPressed: () =>
                          showBackgroundSettingsSheet(context, ref),
                      child: const Text('打开设置'),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    ),
  );
  await Future<void>.delayed(const Duration(seconds: 2));
  final result = <String, Object?>{'imageInfo': imageInfo};
  try {
    if (const bool.fromEnvironment('REAL_APP')) {
      result['sessionPhase'] = _appRef!.read(sessionProvider).phase.name;
      unawaited(
        showBackgroundSettingsSheet(_find<Navigator>().first, _appRef!),
      );
    } else {
      (_find<FilledButton>().single.widget as FilledButton).onPressed!();
    }
    await Future<void>.delayed(const Duration(seconds: 1));
    // Use the actual expansion tile and pointer dispatch, not slider callbacks.
    final tile = _find<ExpansionTile>().single;
    await Scrollable.ensureVisible(
      tile,
      duration: const Duration(milliseconds: 150),
    );
    await _tap(
      (tile.renderObject as RenderBox).localToGlobal(const Offset(80, 24)),
    );
    await Future<void>.delayed(const Duration(milliseconds: 500));
    for (var sliderIndex = 0; sliderIndex < 3; sliderIndex++) {
      final slider = _find<Slider>()[sliderIndex];
      await Scrollable.ensureVisible(
        slider,
        alignment: .5,
        duration: const Duration(milliseconds: 150),
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final box = slider.renderObject as RenderBox;
      await _snapshotSemantics('before-$sliderIndex');
      final start = box.localToGlobal(Offset(30, box.size.height / 2));
      final width = box.size.width - 60;
      _phase = 'slider-$sliderIndex-drag';
      final frameGaps = <double>[];
      final clock = Stopwatch()..start();
      var previous = clock.elapsedMicroseconds;
      GestureBinding.instance.handlePointerEvent(
        PointerDownEvent(pointer: 1, position: start),
      );
      var position = start;
      for (var i = 1; i <= 180; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 16));
        final now = clock.elapsedMicroseconds;
        frameGaps.add((now - previous) / 1000);
        previous = now;
        final next =
            start +
            Offset(width * (1 - math.cos(i / 180 * math.pi * 3)) / 2, 0);
        GestureBinding.instance.handlePointerEvent(
          PointerMoveEvent(pointer: 1, position: next, delta: next - position),
        );
        position = next;
        if (i == 2 || i == 90) await _snapshotSemantics('drag-$sliderIndex-$i');
      }
      result['slider-$sliderIndex-heartbeat'] = _stats(frameGaps);
      result['slider-$sliderIndex-value'] =
          (_find<Slider>()[sliderIndex].widget as Slider).value;
      _phase = 'slider-$sliderIndex-release';
      GestureBinding.instance.handlePointerEvent(
        PointerUpEvent(pointer: 1, position: position),
      );
      await Future<void>.delayed(const Duration(seconds: 2));
      await _snapshotSemantics('after-$sliderIndex');
      // Match the reported trigger: interact with another control after release.
      // Collapsing also removes the sliders and their portals from the tree.
      await _toggleAdvanced();
      await _toggleAdvanced();
      result['slider-$sliderIndex-followupClick'] = 'completed';
    }
    Navigator.of(_find<Slider>().first).pop();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (const bool.fromEnvironment('REAL_APP')) {
      unawaited(
        showBackgroundSettingsSheet(_find<Navigator>().first, _appRef!),
      );
    } else {
      (_find<FilledButton>().single.widget as FilledButton).onPressed!();
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await _toggleAdvanced();
    result['reopenedSliderCount'] = _find<Slider>().length;
    await Future<void>.delayed(const Duration(seconds: 2));
    result['writes'] = _storage.writes.length;
    if (_storage case final _NativeProbeStorage native) {
      result['nativeWriteMs'] = native.durations;
      await native.cleanUp();
    }
    result['frames'] = {
      for (final entry in _frames.entries)
        entry.key: {
          'buildMs': _stats(
            entry.value
                .map((frame) => frame.buildDuration.inMicroseconds / 1000)
                .toList(),
          ),
          'rasterMs': _stats(
            entry.value
                .map((frame) => frame.rasterDuration.inMicroseconds / 1000)
                .toList(),
          ),
        },
    };
    result['devicePixelRatio'] =
        ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
    final size = ui.PlatformDispatcher.instance.views.first.physicalSize;
    result['physicalSize'] = [size.width, size.height];
  } catch (error, stack) {
    result['error'] = '$error';
    result['stack'] = '$stack';
  }
  final path = const String.fromEnvironment(
    'BENCHMARK_RESULT',
    defaultValue: '.dart_tool/background-benchmark/result.json',
  );
  await File(
    path,
  ).writeAsString(const JsonEncoder.withIndent('  ').convert(result));
  exit(result.containsKey('error') ? 1 : 0);
}

class _NativeProbeStorage extends BackgroundTestStorage {
  final key = 'qa_background_probe_${DateTime.now().microsecondsSinceEpoch}';
  final durations = <double>[];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    final watch = Stopwatch()..start();
    await const FlutterSecureStorage().write(key: this.key, value: value);
    durations.add(watch.elapsedMicroseconds / 1000);
    writes.add(value);
    this.value = value;
  }

  Future<void> cleanUp() => const FlutterSecureStorage().delete(key: key);
}

Future<void> _snapshotSemantics(String phase) async {
  if (!const bool.fromEnvironment('SEMANTICS_SNAPSHOTS')) return;
  final rows = <Map<String, Object?>>[];
  const allowed = {
    '背景模糊',
    '背景柔化',
    '导航不透明度',
    '高级调整',
    '恢复推荐参数',
    '减少透明效果',
    '轻度毛玻璃',
    '柔和背景',
    '默认纯色',
  };
  void visit(SemanticsNode node) {
    final data = node.getSemanticsData();
    final children = <int>[];
    node.visitChildren((child) {
      children.add(child.id);
      visit(child);
      return true;
    });
    rows.add({
      'id': node.id,
      'parent': node.parent?.id,
      'label': allowed.contains(data.label) ? data.label : '',
      'slider': data.flagsCollection.isSlider,
      'children': children,
      'rect': [
        node.rect.left,
        node.rect.top,
        node.rect.width,
        node.rect.height,
      ],
    });
  }

  for (final view in RendererBinding.instance.renderViews) {
    final root = view.owner?.semanticsOwner?.rootSemanticsNode;
    if (root != null) visit(root);
  }
  await File(
    '.dart_tool/background-benchmark/semantics-$phase.json',
  ).writeAsString(jsonEncode(rows));
}

List<Element> _find<T extends Widget>() {
  final found = <Element>[];
  void visit(Element element) {
    if (element.widget is T) found.add(element);
    element.visitChildren(visit);
  }

  visit(WidgetsBinding.instance.rootElement!);
  return found;
}

Future<void> _toggleAdvanced() async {
  final tile = _find<ExpansionTile>().single;
  await Scrollable.ensureVisible(
    tile,
    alignment: 0,
    duration: const Duration(milliseconds: 150),
  );
  await _tap(
    (tile.renderObject as RenderBox).localToGlobal(const Offset(80, 24)),
  );
  await Future<void>.delayed(const Duration(milliseconds: 400));
}

Future<void> _tap(Offset position) async {
  GestureBinding.instance.handlePointerEvent(
    PointerDownEvent(pointer: 2, position: position),
  );
  await Future<void>.delayed(const Duration(milliseconds: 30));
  GestureBinding.instance.handlePointerEvent(
    PointerUpEvent(pointer: 2, position: position),
  );
}

Map<String, Object> _stats(List<double> values) {
  values.sort();
  return {
    'count': values.length,
    if (values.isNotEmpty) ...{
      'p50': values[(values.length * .5).floor()],
      'p95': values[(values.length * .95).floor()],
      'max': values.last,
      'over16ms': values.where((value) => value > 16.67).length,
    },
  };
}
