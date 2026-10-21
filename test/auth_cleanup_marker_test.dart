import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/auth/auth_cleanup_marker.dart';
import 'package:mubangumi/core/auth/website_cookie_bridge.dart';
import 'package:mubangumi/core/auth/website_session.dart';
import 'package:mubangumi/core/storage/token_store.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory directory;
  late File marker;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'mubangumi-auth-cleanup-',
    );
    marker = File(p.join(directory.path, 'cleanup-state.json'));
    AuthCleanupMarker.useFileForTests(marker);
    FlutterSecureStorage.setMockInitialValues({});
  });
  tearDown(() async {
    AuthCleanupMarker.useMemoryForTests();
    if (!p.isWithin(
          Directory.systemTemp.resolveSymbolicLinksSync(),
          directory.resolveSymbolicLinksSync(),
        ) ||
        !p.basename(directory.path).startsWith('mubangumi-auth-cleanup-'))
      throw StateError('Unexpected cleanup test path');
    await directory.delete(recursive: true);
  });

  Future<void> seed() async {
    await TokenStore().write('synthetic-old-token');
    await WebsiteSessionStore().write(
      WebsiteSessionSnapshot(
        cookies: const [
          WebsiteCookie(name: 'chii_auth', value: 'synthetic-old-cookie'),
        ],
        syncedAt: DateTime.now(),
      ),
    );
  }

  test(
    'interrupted logout blocks old token and website snapshot after memory is recreated',
    () async {
      await seed();
      await AuthCleanupMarker.beginLogout();
      AuthCleanupMarker.useFileForTests(marker);
      WebsiteCookieBridge.resetForTests();
      expect(await TokenStore().read(), isNull);
      expect(await WebsiteSessionStore().read(), isNull);
      var cleanups = 0;
      WebsiteCookieBridge.setCleanupForTests(() async {
        cleanups++;
      });
      await WebsiteCookieBridge.waitForPendingCleanup();
      expect(cleanups, 1);
      expect((await AuthCleanupMarker.current()).apiPending, true);
      expect((await AuthCleanupMarker.current()).websitePending, false);
    },
  );
  test(
    'clearing native cookies does not revive a snapshot whose deletion failed',
    () async {
      await seed();
      final nonce = await AuthCleanupMarker.beginLogout();
      await AuthCleanupMarker.completeWebsiteCookies(nonce);
      expect((await AuthCleanupMarker.current()).websiteStorePending, true);
      expect(await WebsiteSessionStore().read(), isNull);
      await WebsiteSessionStore().clear();
      expect((await AuthCleanupMarker.current()).websitePending, false);
    },
  );
  test(
    'old completions cannot unlock a newer logout or a new website cleanup',
    () async {
      await seed();
      final first = await AuthCleanupMarker.beginLogout();
      final website = await AuthCleanupMarker.beginWebsiteCleanup(
        includeStoredSession: true,
      );
      await AuthCleanupMarker.completeApi(first);
      await AuthCleanupMarker.completeWebsiteStore(first);
      await AuthCleanupMarker.completeWebsiteCookies(first);
      var state = await AuthCleanupMarker.current();
      expect(state.apiPending, false);
      expect(state.websiteNonce, website);
      expect(state.websiteStorePending, true);
      expect(state.websiteCookiesPending, true);
      final second = await AuthCleanupMarker.beginLogout();
      expect(second, isNot(first));
      await AuthCleanupMarker.completeApi(first);
      state = await AuthCleanupMarker.current();
      expect(state.apiPending, true);
      expect(await TokenStore().read(), isNull);
    },
  );
  test(
    'a fresh token clears only its API phase and corrupt markers fail closed',
    () async {
      await seed();
      await marker.writeAsString('{');
      expect(await TokenStore().read(), isNull);
      expect(await WebsiteSessionStore().read(), isNull);
      await TokenStore().write('synthetic-new-token');
      expect(await TokenStore().read(), 'synthetic-new-token');
      expect((await AuthCleanupMarker.current()).websitePending, true);
    },
  );
  test('an unreadable marker never falls back to legacy credentials', () async {
    await seed();
    await Directory(marker.path).create();
    await expectLater(TokenStore().read(), throwsStateError);
  });
}
