import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/shortcuts/shared_link_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final pending = <String>[];
  Completer<String?>? gate;
  late SharedLinkBridge bridge;
  final received = <String>[];
  setUp(() {
    pending.clear();
    received.clear();
    gate = null;
    bridge = SharedLinkBridge(enabled: true);
    messenger.setMockMethodCallHandler(SharedLinkBridge.channel, (call) async {
      expect(call.method, 'takePendingText');
      final waiting = gate;
      if (waiting != null) {
        gate = null;
        return waiting.future;
      }
      return pending.isEmpty ? null : pending.removeAt(0);
    });
  });
  tearDown(() {
    bridge.dispose();
    messenger.setMockMethodCallHandler(SharedLinkBridge.channel, null);
  });
  test(
    'cold start drains all shared text once and a resumed app receives new shares',
    () async {
      pending.addAll(['first', 'second']);
      await bridge.bind(received.add);
      expect(received, ['first', 'second']);
      await bridge.resume();
      expect(received, hasLength(2));
      pending.add('third');
      await bridge.resume();
      expect(received, ['first', 'second', 'third']);
    },
  );
  test('new share during the last pending read cannot be lost', () async {
    final waiting = Completer<String?>();
    gate = waiting;
    final binding = bridge.bind(received.add);
    await Future<void>.delayed(Duration.zero);
    pending.add('late');
    await bridge.resume();
    waiting.complete(null);
    await binding;
    expect(received, ['late']);
  });
  test('disposing during native read prevents a late callback', () async {
    final waiting = Completer<String?>();
    gate = waiting;
    final binding = bridge.bind(received.add);
    await Future<void>.delayed(Duration.zero);
    bridge.dispose();
    waiting.complete('late');
    await binding;
    expect(received, isEmpty);
  });
}
