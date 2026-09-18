import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/features/sync/application/network_recovery_controller.dart';
import 'package:mubangumi/state/network_status_controller.dart';

void main() {
  test(
    'late connectivity check cannot overwrite a newer disconnect event',
    () async {
      final monitor = _Monitor();
      final status = NetworkStatusController(monitor);
      addTearDown(status.dispose);
      addTearDown(monitor.events.close);
      monitor.events.add(NetworkAvailability.unavailable);
      await Future<void>.delayed(Duration.zero);
      monitor.checks.single.complete(NetworkAvailability.available);
      await Future<void>.delayed(Duration.zero);
      expect(status.state, NetworkAvailability.unavailable);
      final check = status.refresh();
      monitor.checks.last.complete(NetworkAvailability.available);
      await check;
      expect(status.state, NetworkAvailability.available);
    },
  );

  test('monitor errors stay unknown and dispose ignores late checks', () async {
    final monitor = _Monitor();
    final status = NetworkStatusController(monitor);
    addTearDown(monitor.events.close);
    monitor.checks.single.completeError(Exception('unsupported'));
    await Future<void>.delayed(Duration.zero);
    expect(status.state, NetworkAvailability.unknown);
    final check = status.refresh();
    status.dispose();
    monitor.checks.last.complete(NetworkAvailability.available);
    await check;
    expect(monitor.events.hasListener, isFalse);
  });

  testWidgets('a burst of reconnect events triggers one serialized recovery', (
    tester,
  ) async {
    final gate = Completer<void>();
    var calls = 0;
    var active = 0;
    var peak = 0;
    final recovery = NetworkRecoveryController(
      recover: () async {
        calls++;
        active++;
        if (active > peak) peak = active;
        if (calls == 1) await gate.future;
        active--;
      },
    );
    addTearDown(recovery.dispose);
    recovery.setAvailable(true);
    for (var i = 0; i < 5; i++) {
      recovery.request();
    }
    await tester.pump(const Duration(milliseconds: 599));
    expect(calls, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, 1);
    recovery.setAvailable(false);
    recovery.setAvailable(true);
    recovery.request();
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 1);
    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(calls, 2);
    expect(peak, 1);
  });

  testWidgets(
    'disconnect cancels pending recovery; background work waits for resume',
    (tester) async {
      var calls = 0;
      final recovery = NetworkRecoveryController(
        recover: () async {
          calls++;
        },
      );
      addTearDown(recovery.dispose);
      recovery.setAvailable(true);
      recovery.request();
      recovery.setAvailable(false);
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 0);
      recovery.setAvailable(true);
      recovery.setForeground(false);
      recovery.request();
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 0);
      recovery.setForeground(true);
      await tester.pump(const Duration(milliseconds: 600));
      expect(calls, 1);
    },
  );

  testWidgets('failure does not busy-loop and disposal cancels recovery', (
    tester,
  ) async {
    var calls = 0;
    final recovery = NetworkRecoveryController(
      recover: () async {
        calls++;
        throw Exception('no Internet');
      },
    );
    recovery.setAvailable(true);
    recovery.request();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(minutes: 1));
    expect(calls, 1);
    recovery.request();
    recovery.dispose();
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 1);
  });
}

class _Monitor implements NetworkMonitor {
  final events = StreamController<NetworkAvailability>();
  final checks = <Completer<NetworkAvailability>>[];
  @override
  Stream<NetworkAvailability> get changes => events.stream;
  @override
  Future<NetworkAvailability> check() {
    final result = Completer<NetworkAvailability>();
    checks.add(result);
    return result.future;
  }
}
