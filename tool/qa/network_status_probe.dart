// Read-only native plugin check. No app login, cookies, cache, or API requests.
// flutter build windows --debug -t tool/qa/network_status_probe.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:mubangumi/state/network_status_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final result = <String, Object?>{};
  StreamSubscription<NetworkAvailability>? subscription;
  try {
    final monitor = PlatformNetworkMonitor();
    subscription = monitor.changes.listen(
      (status) => result['event'] = status.name,
      onError: (Object error) => result['streamError'] = error.toString(),
    );
    final status = await monitor.check().timeout(const Duration(seconds: 10));
    result['availability'] = status.name;
    await Future<void>.delayed(const Duration(seconds: 2));
  } catch (error) {
    result['error'] = error.toString();
  } finally {
    await subscription?.cancel();
  }
  final output = File(
    const String.fromEnvironment(
      'NETWORK_PROBE_RESULT',
      defaultValue: '.dart_tool/network-status-native.json',
    ),
  );
  await output.parent.create(recursive: true);
  await output.writeAsString(jsonEncode(result));
  exit(
    result.containsKey('error') || result.containsKey('streamError') ? 1 : 0,
  );
}
