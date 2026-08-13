import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/auth/website_cookie_bridge.dart';

void main() {
  test('Windows cookie-cleanup failure logs a distinctive diagnostic prefix',
      () async {
    // WebView2 cleanup only exists on Windows; on other hosts the branch is
    // never taken and there is nothing to assert.
    if (!Platform.isWindows) return;

    final lines = <String>[];
    final previous = debugPrint;
    debugPrint = (message, {wrapWidth}) => lines.add(message ?? '');
    addTearDown(() => debugPrint = previous);

    await WebsiteCookieBridge.clearBgmCookies();
    await pumpEventQueue();

    expect(lines, anyElement(contains('[BGM-COOKIE-CLEANUP]')));
  });

  test('detached best-effort cleanup does not wait for the task', () async {
    final gate = Completer<void>();
    var finished = false;

    WebsiteCookieBridge.runDetachedBestEffort(() async {
      await gate.future;
      finished = true;
    });

    // The caller has returned while the slow cleanup is still pending.
    expect(finished, isFalse);

    gate.complete();
    await pumpEventQueue();
    expect(finished, isTrue);
  });

  test('detached best-effort cleanup reports failures through the handler',
      () async {
    final failures = <Object>[];

    WebsiteCookieBridge.runDetachedBestEffort(
      () async => throw StateError('boom'),
      onFailure: (error, stack) => failures.add(error),
    );
    await pumpEventQueue();

    expect(failures, hasLength(1));
    expect(failures.single, isA<StateError>());
  });
}
