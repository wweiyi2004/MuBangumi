import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/shortcuts/app_shortcut.dart';
import 'package:mubangumi/state/app_shortcut_controller.dart';

void main() {
  test('parses the three home-screen shortcut types', () {
    expect(AppShortcut.tryParse('scan'), AppShortcut.scan);
    expect(AppShortcut.tryParse('my_qr'), AppShortcut.myQr);
    expect(AppShortcut.tryParse('schedule'), AppShortcut.schedule);
    expect(AppShortcut.tryParse('  scan  '), AppShortcut.scan);
    expect(AppShortcut.tryParse('unknown'), isNull);
    expect(AppShortcut.tryParse(''), isNull);
    expect(AppShortcut.tryParse(null), isNull);
  });

  test('holds a shortcut until HomeShell takes it after sign-in', () {
    final pending = PendingAppShortcut();
    pending.offer(AppShortcut.scan);
    expect(pending.state, AppShortcut.scan);
    expect(pending.take(), AppShortcut.scan);
    expect(pending.state, isNull);
    expect(pending.take(), isNull);
  });

  test('defines scan, my QR and schedule shortcut types', () {
    expect(AppShortcut.values.map((item) => item.type), [
      'scan',
      'my_qr',
      'schedule',
    ]);
  });
}
