import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/auth/website_identity.dart';
import 'package:mubangumi/core/auth/website_session.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/state/account_access_controller.dart';
import 'package:mubangumi/state/website_session_controller.dart';

const user = BangumiUser(
  id: 1,
  username: 'alice',
  nickname: 'Alice',
  avatarUrl: '',
);

class Store extends WebsiteSessionStore {
  WebsiteSessionSnapshot? value = WebsiteSessionSnapshot(
    cookies: const [
      WebsiteCookie(name: 'chii_auth', value: 'test-only-cookie'),
    ],
    syncedAt: DateTime.now(),
  ).withVerifiedUser(1);
  bool failReads = false;
  int reads = 0;
  @override
  Future<WebsiteSessionSnapshot?> read() async {
    reads++;
    if (failReads) throw StateError('temporary secure storage failure');
    return value;
  }

  @override
  Future<void> write(WebsiteSessionSnapshot snapshot) async {
    value = snapshot;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

class RejectingProbe extends WebsiteIdentityProbe {
  RejectingProbe([this.status = WebsiteAccessStatus.expired]);
  final WebsiteAccessStatus status;
  int calls = 0;
  @override
  Future<int> verify(
    WebsiteSessionSnapshot snapshot,
    BangumiUser expected,
  ) async {
    calls++;
    throw WebsiteAccessException(status, 'rejected');
  }
}

class AcceptingProbe extends WebsiteIdentityProbe {
  @override
  Future<int> verify(
    WebsiteSessionSnapshot snapshot,
    BangumiUser expected,
  ) async => expected.id;
}

void main() {
  test('manual rejection must remain revoked after controller restart', () async {
    final store = Store();
    final probe = RejectingProbe();
    final first = WebsiteSessionController(store, probe: probe);
    await first.attachAccount(user);
    expect(await first.ensureVerified(force: true), false);
    expect(first.state.status, WebsiteAccessStatus.expired);
    first.dispose();
    final restarted = WebsiteSessionController(store, probe: probe);
    addTearDown(restarted.dispose);
    await restarted.attachAccount(user);
    expect(
      await restarted.ensureVerified(),
      false,
      reason:
          'an explicitly rejected cookie must not regain available status on restart',
    );
  });

  test(
    'retry verification must recover after a transient storage read failure',
    () async {
      final store = Store()..failReads = true;
      final controller = WebsiteSessionController(
        store,
        probe: AcceptingProbe(),
      );
      addTearDown(controller.dispose);
      final access = AccountAccessController(
        website: controller,
        currentUser: () => user,
      );
      addTearDown(access.dispose);
      expect(await access.verify(), false);
      expect(controller.state.status, WebsiteAccessStatus.unavailable);
      final readsBeforeRetry = store.reads;
      expect(await access.verify(force: true), false);
      expect(controller.state.status, WebsiteAccessStatus.unavailable);
      expect(store.reads, greaterThan(readsBeforeRetry));
      store.failReads = false;
      final result = await access.verify(force: true);
      expect(
        store.reads,
        greaterThan(readsBeforeRetry),
        reason: 'the retry action must retry the failed storage read',
      );
      expect(result, true);
    },
  );

  for (final status in [
    WebsiteAccessStatus.mismatch,
    WebsiteAccessStatus.challenge,
  ]) {
    test(
      '$status revokes the stored binding without deleting cookies',
      () async {
        final store = Store();
        final controller = WebsiteSessionController(
          store,
          probe: RejectingProbe(status),
        );
        addTearDown(controller.dispose);
        await controller.attachAccount(user);
        expect(await controller.ensureVerified(force: true), false);
        expect(store.value!.verifiedUserId, isNull);
        expect(store.value!.hasSessionCookies, true);
        expect(controller.state.status, status);
        expect(
          await controller.saveCookies([
            ...store.value!.cookies,
            const WebsiteCookie(name: 'cf_clearance', value: 'refreshed'),
          ]),
          false,
        );
        expect(controller.state.isSynced, false);
      },
    );
  }
}
