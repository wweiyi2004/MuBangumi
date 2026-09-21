import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/auth/website_identity.dart';
import 'package:mubangumi/core/auth/website_session.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/state/website_session_controller.dart';

const user = BangumiUser(
  id: 1,
  username: 'alice',
  nickname: 'Alice',
  avatarUrl: '',
);

class Store extends WebsiteSessionStore {
  WebsiteSessionSnapshot? value = WebsiteSessionSnapshot(
    cookies: const [WebsiteCookie(name: 'chii_auth', value: 'fixture')],
    syncedAt: DateTime(2026),
  ).withVerifiedUser(1, at: DateTime(2026));
  Completer<void>? reading;
  bool failWrites = false;
  @override
  Future<WebsiteSessionSnapshot?> read() async {
    await reading?.future;
    return value;
  }

  @override
  Future<void> write(WebsiteSessionSnapshot snapshot) async {
    if (failWrites) throw StateError('secure storage write failed');
    value = snapshot;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

class Probe extends WebsiteIdentityProbe {
  Probe(this.run);
  final Future<int> Function() run;
  @override
  Future<int> verify(WebsiteSessionSnapshot snapshot, BangumiUser expected) =>
      run();
  @override
  Future<int> verifyIdentifier(String identifier, BangumiUser expected) =>
      run();
}

void main() {
  test(
    'a failed revocation write still cannot restore old credentials on reload',
    () async {
      final store = Store();
      final controller = WebsiteSessionController(store);
      addTearDown(controller.dispose);
      await controller.attachAccount(user);
      store.failWrites = true;
      controller.reportFailure(
        WebsiteAccessStatus.expired,
        controller.state.snapshot!.requestKey,
      );
      await controller.reload();
      expect(controller.state.isSynced, false);
      expect(controller.state.snapshot!.verifiedUserId, isNull);
      expect(
        store.value!.verifiedUserId,
        1,
        reason: 'the store intentionally retained the stale binding',
      );
    },
  );
  test(
    'a synchronous checking listener also joins forced verification',
    () async {
      final gate = Completer<int>();
      final controller = WebsiteSessionController(
        Store(),
        probe: Probe(() => gate.future),
      );
      addTearDown(controller.dispose);
      await controller.attachAccount(user);
      Future<bool>? observed;
      final stop = controller.addListener((state) {
        if (state.status == WebsiteAccessStatus.checking) {
          observed = controller.ensureVerified();
        }
      }, fireImmediately: false);
      addTearDown(stop);
      final checking = controller.ensureVerified(force: true);
      expect(controller.state.status, WebsiteAccessStatus.checking);
      gate.complete(1);
      expect(await checking, true);
      expect(await observed, true);
    },
  );

  test(
    'captured browser verification is shared and a failed capture has no cached binding',
    () async {
      final store = Store();
      final gate = Completer<int>();
      final controller = WebsiteSessionController(
        store,
        probe: Probe(() => gate.future),
      );
      addTearDown(controller.dispose);
      await controller.attachAccount(user);
      final old = controller.state.snapshot!;
      final capture = controller.saveCookies(
        old.cookies,
        browserIdentity: WebsiteBrowserIdentity(
          url: 'https://bgm.tv/',
          html:
              '<div id="badgeUserPanel"><a class="avatar" href="/user/alice">Alice</a></div>',
          authenticationKey: old.authenticationKey,
          userAgent: 'Browser/new',
        ),
      );
      var finished = false;
      final guard = controller.ensureVerified().then((value) {
        finished = true;
        return value;
      });
      await Future<void>.delayed(Duration.zero);
      expect(finished, false);
      gate.completeError(
        const WebsiteAccessException(
          WebsiteAccessStatus.unavailable,
          'temporary failure',
        ),
      );
      expect(await capture, false);
      expect(await guard, false);
      expect(controller.state.snapshot!.verifiedUserId, isNull);
      expect(store.value!.verifiedUserId, isNull);
    },
  );

  test(
    'a fresh verification queued after rejection wins on disk and in memory',
    () async {
      final store = Store();
      final controller = WebsiteSessionController(
        store,
        probe: Probe(() async => 1),
      );
      addTearDown(controller.dispose);
      await controller.attachAccount(user);
      controller.reportFailure(
        WebsiteAccessStatus.expired,
        controller.state.snapshot!.requestKey,
      );
      expect(
        await controller.saveCookies(const [
          WebsiteCookie(name: 'chii_auth', value: 'new'),
        ]),
        true,
      );
      await controller.reload();
      expect(controller.state.isSynced, true);
      expect(store.value!.authenticationKey, 'chii_auth=new');
    },
  );

  test(
    'reloading a rejection does not make the old draft proof valid again',
    () async {
      final controller = WebsiteSessionController(Store());
      addTearDown(controller.dispose);
      await controller.attachAccount(user);
      final old = controller.state.snapshot!;
      controller.reportFailure(WebsiteAccessStatus.expired, old.requestKey);
      await controller.reload();
      expect(
        await controller.bindVerifiedUser(
          authenticationKey: old.authenticationKey,
          requestKey: old.requestKey,
          userId: 1,
        ),
        false,
      );
      expect(controller.state.snapshot!.verifiedUserId, isNull);
    },
  );

  test(
    'an already verified same-account renewal keeps draft ownership without rebinding',
    () async {
      final controller = WebsiteSessionController(Store());
      addTearDown(controller.dispose);
      await controller.attachAccount(user);
      final old = controller.state.snapshot!;
      await controller.saveCookies([
        ...old.cookies,
        const WebsiteCookie(name: 'cf_clearance', value: 'new'),
      ]);
      final renewed = controller.state.snapshot!;
      expect(renewed.requestKey, isNot(old.requestKey));
      expect(
        await controller.bindVerifiedUser(
          authenticationKey: old.authenticationKey,
          requestKey: old.requestKey,
          userId: 1,
        ),
        true,
      );
      expect(controller.state.snapshot!.requestKey, renewed.requestKey);
    },
  );
  for (final status in [
    WebsiteAccessStatus.expired,
    WebsiteAccessStatus.challenge,
  ]) {
    test(
      'immediate reload cannot undo an accepted $status rejection',
      () async {
        final store = Store();
        final controller = WebsiteSessionController(store);
        addTearDown(controller.dispose);
        await controller.attachAccount(user);
        expect(
          controller.reportFailure(
            status,
            controller.state.snapshot!.requestKey,
          ),
          true,
        );
        await controller.reload();
        expect(controller.state.isSynced, false);
        expect(store.value!.verifiedUserId, isNull);
      },
    );
  }

  test(
    'a rejection listener can reload without reading an old verified disk snapshot',
    () async {
      final store = Store();
      final controller = WebsiteSessionController(store);
      addTearDown(controller.dispose);
      await controller.attachAccount(user);
      Future<void>? reloading;
      final stop = controller.addListener((state) {
        if (state.status == WebsiteAccessStatus.expired) {
          reloading = controller.reload();
        }
      }, fireImmediately: false);
      addTearDown(stop);
      controller.reportFailure(
        WebsiteAccessStatus.expired,
        controller.state.snapshot!.requestKey,
      );
      await reloading;
      expect(controller.state.isSynced, false);
      expect(store.value!.verifiedUserId, isNull);
    },
  );

  test(
    'parallel cold-start guards wait for the same account attachment',
    () async {
      final store = Store()..reading = Completer<void>();
      final controller = WebsiteSessionController(store);
      addTearDown(controller.dispose);
      final results = <Object>[];
      Future<void> guard() async {
        try {
          results.add(await controller.requireVerifiedSession(user));
        } catch (error) {
          results.add(error);
        }
      }

      final first = guard(), second = guard();
      await Future<void>.delayed(Duration.zero);
      expect(results, isEmpty);
      store.reading!.complete();
      await Future.wait([first, second]);
      expect(results, everyElement(isA<WebsiteSessionSnapshot>()));
    },
  );

  test(
    'normal guards join an in-progress forced verification instead of publishing available',
    () async {
      final gate = Completer<int>();
      final controller = WebsiteSessionController(
        Store(),
        probe: Probe(() => gate.future),
      );
      addTearDown(controller.dispose);
      await controller.attachAccount(user);
      final forced = controller.ensureVerified(force: true);
      var finished = false;
      final normal = controller.ensureVerified().then((value) {
        finished = true;
        return value;
      });
      await Future<void>.delayed(Duration.zero);
      expect(finished, false);
      expect(controller.state.status, WebsiteAccessStatus.checking);
      gate.completeError(
        const WebsiteAccessException(WebsiteAccessStatus.expired, 'expired'),
      );
      expect(await forced, false);
      expect(await normal, false);
    },
  );

  test(
    'a stale draft identity cannot rebind cookies after rejection',
    () async {
      final controller = WebsiteSessionController(Store());
      addTearDown(controller.dispose);
      await controller.attachAccount(user);
      final prior = controller.state.snapshot!;
      controller.reportFailure(WebsiteAccessStatus.expired, prior.requestKey);
      expect(
        await controller.bindVerifiedUser(
          authenticationKey: prior.authenticationKey,
          requestKey: prior.requestKey,
          userId: 1,
        ),
        false,
      );
      expect(controller.state.isSynced, false);
    },
  );

  test(
    'binding cannot replace the account owner even with the same cookie',
    () async {
      final controller = WebsiteSessionController(Store());
      addTearDown(controller.dispose);
      await controller.attachAccount(user);
      expect(
        await controller.bindVerifiedUser(
          authenticationKey: controller.state.snapshot!.authenticationKey,
          requestKey: controller.state.snapshot!.requestKey,
          userId: 2,
        ),
        false,
      );
      expect(controller.state.snapshot!.verifiedUserId, 1);
    },
  );
}
