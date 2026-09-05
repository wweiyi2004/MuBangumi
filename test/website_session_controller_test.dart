import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/auth/website_session.dart';
import 'package:mubangumi/state/website_session_controller.dart';

void main() {
  test('late website reload cannot restore a cleared session', () async {
    final store = _DelayedReadStore();
    final controller = WebsiteSessionController(store);
    addTearDown(controller.dispose);
    await _waitFor(() => controller.state.ready);
    store.pendingRead = Completer<WebsiteSessionSnapshot?>();
    final reload = controller.reload();
    await Future<void>.delayed(Duration.zero);
    controller.markCleared();
    store.pendingRead!.complete(
      WebsiteSessionSnapshot(
        cookies: const [WebsiteCookie(name: 'chii_auth', value: 'old-account')],
        syncedAt: DateTime.now(),
      ),
    );
    await reload;
    expect(controller.state.snapshot, isNull);
    expect(controller.state.isSynced, isFalse);
  });

  test(
    'website storage read failure finishes loading with a recoverable message',
    () async {
      final controller = WebsiteSessionController(_FailedReadStore());
      addTearDown(controller.dispose);
      await _waitFor(() => controller.state.ready);
      expect(controller.state.isSynced, isFalse);
      expect(controller.state.message, contains('无法读取网站登录'));
    },
  );

  test(
    'expired or unrelated cookies are not saved as a logged-in session',
    () async {
      final store = _InterleavableWebsiteSessionStore();
      final controller = WebsiteSessionController(store);
      addTearDown(controller.dispose);
      await _waitFor(() => controller.state.ready);
      expect(
        await controller.saveCookies([
          WebsiteCookie(
            name: 'chii_auth',
            value: 'expired',
            expiresAt: DateTime.utc(2000),
          ),
          const WebsiteCookie(name: 'cf_clearance', value: 'challenge-cookie'),
        ]),
        isFalse,
      );
      expect(store.pendingWrite, isNull);
      expect(controller.state.isSynced, isFalse);
    },
  );

  test('old save cleanup cannot erase a newer website session', () async {
    final store = _InterleavableWebsiteSessionStore();
    final controller = WebsiteSessionController(store);
    addTearDown(controller.dispose);
    await _waitFor(() => controller.state.ready);
    final oldSave = controller.saveCookies(const [
      WebsiteCookie(name: 'chii_auth', value: 'old'),
    ]);
    await _waitFor(() => store.pendingWrite != null);
    final oldWrite = store.pendingWrite!;
    controller.markCleared();
    final newSave = controller.saveCookies(const [
      WebsiteCookie(name: 'chii_auth', value: 'new'),
    ]);
    oldWrite.complete();
    await _waitFor(() => store.pendingWrite != oldWrite);
    store.pendingWrite!.complete();
    expect(await oldSave, isFalse);
    expect(await newSave, isTrue);
    expect(store.snapshot!.cookies.single.value, 'new');
    expect(controller.state.snapshot!.cookies.single.value, 'new');
  });

  test(
    'saveCookies across a sign-out clear does not restore the old snapshot',
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
    },
  );

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

class _DelayedReadStore extends _InterleavableWebsiteSessionStore {
  Completer<WebsiteSessionSnapshot?>? pendingRead;
  @override
  Future<WebsiteSessionSnapshot?> read() => pendingRead?.future ?? super.read();
}

class _FailedReadStore extends WebsiteSessionStore {
  @override
  Future<WebsiteSessionSnapshot?> read() async =>
      throw StateError('storage unavailable');
}
