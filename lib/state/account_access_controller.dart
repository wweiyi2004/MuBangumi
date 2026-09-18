import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/auth/website_session.dart';
import '../core/network/community_service.dart';
import '../core/network/pm_service.dart';
import '../models/bangumi_models.dart';
import 'session_controller.dart';
import 'website_session_controller.dart';

/// One coordination point; the existing API session remains the account owner.
final accountAccessProvider = Provider<AccountAccessController>((ref) {
  final website = ref.read(websiteSessionProvider.notifier);
  final access = AccountAccessController(
    website: website,
    currentUser: () => ref.read(sessionProvider).user,
  );
  ref.listen(
    sessionProvider.select((state) => state.user),
    (_, user) => access.accountChanged(user),
    fireImmediately: true,
  );
  final guard = access.requireWebsiteSession;
  final failure = website.reportFailure;
  PmService.shared.websiteSessionGuard = guard;
  PmService.shared.onWebsiteSessionFailure = failure;
  CommunityService.shared.websiteSessionGuard = guard;
  CommunityService.shared.onWebsiteSessionFailure = failure;
  ref.onDispose(() {
    access.dispose();
    if (identical(PmService.shared.websiteSessionGuard, guard)) {
      PmService.shared.websiteSessionGuard = null;
      PmService.shared.onWebsiteSessionFailure = null;
    }
    if (identical(CommunityService.shared.websiteSessionGuard, guard)) {
      CommunityService.shared.websiteSessionGuard = null;
      CommunityService.shared.onWebsiteSessionFailure = null;
    }
  });
  return access;
});

class AccountAccessController {
  AccountAccessController({required this.website, required this.currentUser});
  final WebsiteSessionController website;
  final BangumiUser? Function() currentUser;
  bool _disposed = false;
  int _revision = 0;
  int? _lastId;
  String? _lastUsername;
  Future<bool>? _login;
  int? _loginRevision;

  int get revision => _revision;
  void accountChanged(BangumiUser? user) {
    if (_lastId == user?.id && _lastUsername == user?.username) return;
    _lastId = user?.id;
    _lastUsername = user?.username;
    final revision = ++_revision;
    scheduleMicrotask(() {
      if (!_disposed && revision == _revision) {
        unawaited(website.attachAccount(user));
      }
    });
  }

  Future<WebsiteSessionSnapshot> requireWebsiteSession() async {
    final revision = _revision;
    final user = currentUser();
    final result = await website.requireVerifiedSession(user);
    if (_disposed || revision != _revision || user?.id != currentUser()?.id) {
      throw const WebsiteAccessException(
        WebsiteAccessStatus.mismatch,
        '账号已变化，请重新操作',
      );
    }
    return result;
  }

  Future<bool> verify({bool force = false}) async {
    final user = currentUser();
    if (user == null || _disposed) return false;
    final revision = _revision;
    await website.attachAccount(user);
    final result = await website.ensureVerified(force: force);
    return !_disposed && revision == _revision && result;
  }

  Future<bool> runLogin(Future<bool> Function() open) {
    if (_login != null && _loginRevision == _revision) return _login!;
    final revision = _revision;
    _loginRevision = revision;
    final future = () async {
      final result = await open();
      return result && !_disposed && revision == _revision && await verify();
    }();
    _login = future;
    return future.whenComplete(() {
      if (identical(_login, future)) _login = null;
    });
  }

  void dispose() {
    _disposed = true;
    _revision++;
  }
}
