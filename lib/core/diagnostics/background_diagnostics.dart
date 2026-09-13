import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/scheduler.dart';

/// Opt-in local hang diagnostics. Never records accounts, paths or images.
/// Normal builds compile out all calls through the constant enabled flag.
class BackgroundDiagnostics {
  static const enabled = bool.fromEnvironment('BACKGROUND_DIAGNOSTICS');
  static const buildLabel = String.fromEnvironment(
    'BACKGROUND_DIAGNOSTIC_BUILD',
  );
  static File? _file;
  static Future<void> _writes = Future.value();
  static Timer? _heartbeat;
  static int _frames = 0, _adjustments = 0;
  static int _buildMicros = 0, _rasterMicros = 0;
  static DateTime? _lastBeat;

  static void start() {
    if (!enabled || _heartbeat != null) return;
    _file = File(
      '${File(Platform.resolvedExecutable).parent.path}/background-diagnostic.jsonl',
    );
    _lastBeat = DateTime.now();
    SchedulerBinding.instance.addTimingsCallback(_timings);
    record('start', {'build': buildLabel});
    _heartbeat = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      record('heartbeat', {
        'gapMs': now.difference(_lastBeat!).inMilliseconds,
        'frames': _frames,
        'maxBuildUs': _buildMicros,
        'maxRasterUs': _rasterMicros,
        'adjustments': _adjustments,
      });
      _lastBeat = now;
      _frames = _adjustments = _buildMicros = _rasterMicros = 0;
    });
  }

  static void adjustment() {
    if (enabled) _adjustments++;
  }

  static void _timings(List<FrameTiming> timings) {
    for (final frame in timings) {
      _frames++;
      final build = frame.buildDuration.inMicroseconds;
      final raster = frame.rasterDuration.inMicroseconds;
      if (build > _buildMicros) _buildMicros = build;
      if (raster > _rasterMicros) _rasterMicros = raster;
    }
  }

  static void record(String event, [Map<String, Object?> fields = const {}]) {
    if (!enabled || _file == null) return;
    final line = jsonEncode({
      'time': DateTime.now().toIso8601String(),
      'event': event,
      ...fields,
    });
    _writes = _writes.then((_) async {
      try {
        await _file!.writeAsString('$line\n', mode: FileMode.append);
      } catch (_) {
        // A diagnostic write must never break application behavior.
      }
    });
  }
}
