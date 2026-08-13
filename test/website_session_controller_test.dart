import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/auth/website_session.dart';
import 'package:mubangumi/state/website_session_controller.dart';

void main() {
  test('saveCookies across a sign-out clear does not restore the old snapshot',
      () async {
    final store = _InterleavableWebsiteSessionStore();
    final controller = WebsiteSessionController(store);
    addTearDown(controller.dispose);

    await _waitFor(() => controller.state.ready);

    final save = controller.saveCookies(const [
      WebsiteCookie(name: 'chii_sid', value: 'old-account'),
    ]);
    await _waitFor(() => store.pendingWrite != null);

    // Forced sign-out clears the store and marks the in-memory state cleared
    // while the save above is still writing.
    controller.markCleared();
    store.pendingWrite!.complete();
    final saved = await save;

    expect(saved, isFalse);
    expect(store.snapshot, isNull);
    expect(controller.state.snapshot, isNull);
    expect(controller.state.ready, isTrue);
  });

  test('saveCookies persists when no clear races', () async {
    final store = _InterleavableWebsiteSessionStore();
    final controller = WebsiteSessionController(store);
    addTearDown(controller.dispose);

    await _waitFor(() => controller.state.ready);

    final save = controller.saveCookies(const [
      WebsiteCookie(name: 'chii_sid', value: 'fresh-account'),
    ]);
    await _waitFor(() => store.pendingWrite != null);
    store.pendingWrite!.complete();
    final saved = await save;

    expect(saved, isTrue);
    expect(store.snapshot, isNotNull);
    expect(controller.state.snapshot, isNotNull);
    expect(controller.state.isSynced, isTrue);
  });
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Timed out waiting for asynchronous state');
}

class _InterleavableWebsiteSessionStore extends WebsiteSessionStore {
  WebsiteSessionSnapshot? snapshot;
  Completer<void>? pendingWrite;

  @override
  Future<WebsiteSessionSnapshot?> read() async => snapshot;

  @override
  Future<void> write(WebsiteSessionSnapshot snapshot) {
    this.snapshot = snapshot;
    final completer = Completer<void>();
    pendingWrite = completer;
    return completer.future;
  }

  @override
  Future<void> clear() async {
    snapshot = null;
  }
}
