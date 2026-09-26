import 'package:mubangumi/core/storage/snapshot_cache.dart';
import 'dart:async';

import 'package:mubangumi/core/auth/bangumi_oauth.dart';
import 'package:mubangumi/core/auth/website_session.dart';
import 'package:mubangumi/core/network/bangumi_api.dart';
import 'package:mubangumi/core/network/bangumi_endpoints.dart';
import 'package:mubangumi/core/storage/token_store.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/state/session_controller.dart';

class PmTestSession extends SessionController {
  PmTestSession() : super(BangumiApi(), BangumiOAuth(), _TokenStore()) {
    switchUser(1);
  }

  void switchUser(int id) => state = SessionState(
    phase: SessionPhase.signedIn,
    user: BangumiUser(
      id: id,
      username: 'user$id',
      nickname: 'User $id',
      avatarUrl: '',
    ),
  );
}

class _TokenStore extends TokenStore {
  @override
  Future<BangumiNetworkRoute> readNetworkRoute() =>
      Completer<BangumiNetworkRoute>().future;
}

class PmTestWebsiteStore extends WebsiteSessionStore {
  String account = 'account-a';
  String challenge = 'challenge';
  int? verifiedUserId = 1;
  @override
  Future<WebsiteSessionSnapshot?> read() async => WebsiteSessionSnapshot(
    cookies: [
      WebsiteCookie(name: 'chii_auth', value: account),
      WebsiteCookie(name: 'cf_clearance', value: challenge),
    ],
    syncedAt: DateTime(2026),
    verifiedUserId: verifiedUserId,
    verifiedAt: verifiedUserId == null ? null : DateTime(2026),
    verificationVersion: verifiedUserId == null ? 0 : 2,
  );
  @override
  Future<void> write(WebsiteSessionSnapshot value) async {
    verifiedUserId = value.verifiedUserId;
  }
}

class PmTestFriendsCache extends SnapshotCache {
  @override
  Future<List<BangumiUser>?> readPmFriends(int userId) async => null;
  @override
  Future<void> writePmFriends(int userId, List<BangumiUser> friends) async {}
}
