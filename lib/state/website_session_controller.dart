import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/website_cookie_bridge.dart';
import '../core/auth/website_session.dart';
import '../core/auth/website_identity.dart';
import '../models/bangumi_models.dart';
export '../core/auth/website_identity.dart'
    show WebsiteAccessStatus, WebsiteAccessException;

final websiteIdentityProbeProvider = Provider<WebsiteIdentityProbe>(
  (ref) => WebsiteIdentityProbe(),
);

final websiteSessionStoreProvider = Provider<WebsiteSessionStore>((ref) {
  return WebsiteSessionStore();
});

final websiteSessionProvider =
    StateNotifierProvider<WebsiteSessionController, WebsiteSessionState>((ref) {
      return WebsiteSessionController(
        ref.watch(websiteSessionStoreProvider),
        probe: ref.watch(websiteIdentityProbeProvider),
      );
    });

class WebsiteSessionState {
  const WebsiteSessionState({
    this.ready = false,
    this.snapshot,
    this.message,
    this.status = WebsiteAccessStatus.missing,
  });

  final bool ready;
  final WebsiteSessionSnapshot? snapshot;
  final String? message;
  final WebsiteAccessStatus status;

  bool get hasStoredSession => snapshot?.hasSessionCookies == true;
  bool get isSynced =>
      status == WebsiteAccessStatus.available && hasStoredSession;

  bool get requiresLogin => status.requiresLogin;

  String get statusLabel {
    if (!ready) return '检查中…';
    return switch (status) {
      WebsiteAccessStatus.missing => '聊天与小组操作需要补充验证',
      WebsiteAccessStatus.unverified => '网页登录待核验',
      WebsiteAccessStatus.checking => '正在核验账号…',
      WebsiteAccessStatus.available => '聊天与小组操作可用',
      WebsiteAccessStatus.expired => '网页登录已过期',
      WebsiteAccessStatus.mismatch => '网页账号与应用账号不一致',
      WebsiteAccessStatus.challenge => '需要完成网页验证',
      WebsiteAccessStatus.unavailable => '网络暂不可用，已保留登录',
      WebsiteAccessStatus.cleanupRequired => '登录会话清理失败，请重试',
    };
  }

  WebsiteSessionState copyWith({
    bool? ready,
    WebsiteSessionSnapshot? snapshot,
    String? message,
    bool clearSnapshot = false,
    bool clearMessage = false,
    WebsiteAccessStatus? status,
  }) => WebsiteSessionState(
    ready: ready ?? this.ready,
    snapshot: clearSnapshot ? null : snapshot ?? this.snapshot,
    message: clearMessage ? null : message ?? this.message,
    status: status ?? this.status,
  );
}

class WebsiteSessionController extends StateNotifier<WebsiteSessionState> {
  WebsiteSessionController(this._store, {WebsiteIdentityProbe? probe})
    : _probe = probe ?? WebsiteIdentityProbe(),
      super(const WebsiteSessionState()) {
    unawaited(reload());
  }

  final WebsiteSessionStore _store;
  final WebsiteIdentityProbe _probe;
  BangumiUser? _expectedUser;
  Future<bool>? _verification;
  Future<void>? _attachment;
  Future<bool>? _captureVerification;
  int? _captureGeneration;
  String? _verificationKey;
  final _probeRequests = <String, Future<int>>{};
  final _rejectedRequests = <String>{};

  Future<int> _probeOnce(
    WebsiteSessionSnapshot snapshot,
    BangumiUser user,
    int generation,
  ) {
    final key = '$generation:${user.id}:${snapshot.cookieHeader}';
    final active = _probeRequests[key];
    if (active != null) return active;
    final request = _probe.verify(snapshot, user);
    _probeRequests[key] = request;
    return request.whenComplete(() {
      if (identical(_probeRequests[key], request)) _probeRequests.remove(key);
    });
  }

  /// Each operation supersedes earlier reads and saves, including sign-out.
  int _generation = 0;
  Future<void> _writes = Future<void>.value();
  bool _readFailed = false;

  WebsiteSessionState _snapshotState(
    WebsiteSessionSnapshot? snapshot, {
    String? message,
  }) {
    // A failed secure-storage write must not let a reload restore a binding
    // that this running controller has already rejected.
    if (snapshot != null && _rejectedRequests.contains(snapshot.requestKey)) {
      snapshot = snapshot.withoutVerification();
    }
    return WebsiteSessionState(
      ready: true,
      snapshot: snapshot,
      message: message,
      status: snapshot?.hasSessionCookies != true
          ? WebsiteAccessStatus.missing
          : _expectedUser != null &&
                snapshot!.isVerifiedFor(_expectedUser!.id, DateTime.now())
          ? WebsiteAccessStatus.available
          : WebsiteAccessStatus.unverified,
    );
  }

  Future<void> attachAccount(BangumiUser? user) async {
    if (!mounted) return;
    if (_expectedUser?.id == user?.id &&
        _expectedUser?.username == user?.username) {
      await _attachment;
      return;
    }
    final attachment = Completer<void>();
    _attachment = attachment.future;
    _expectedUser = user;
    _generation++;
    _verification = null;
    _verificationKey = null;
    try {
      state = _snapshotState(state.snapshot);
      await reload();
      if (mounted &&
          _expectedUser?.id == user?.id &&
          _expectedUser?.username == user?.username &&
          user != null) {
        await ensureVerified();
      }
    } finally {
      attachment.complete();
      if (identical(_attachment, attachment.future)) _attachment = null;
    }
  }

  Future<bool> ensureVerified({bool force = false}) {
    if (!mounted) return Future.value(false);
    if (force && _readFailed) return _reloadForVerification();
    final user = _expectedUser;
    final snapshot = state.snapshot;
    if (user == null) return Future.value(false);
    if (_captureVerification != null && _captureGeneration == _generation) {
      return _captureVerification!;
    }
    if (state.status == WebsiteAccessStatus.cleanupRequired) {
      return Future.value(false);
    }
    if (snapshot?.hasSessionCookies != true) {
      if (state.status == WebsiteAccessStatus.unavailable) {
        return Future.value(false);
      }
      state = state.copyWith(
        status: snapshot == null
            ? WebsiteAccessStatus.missing
            : WebsiteAccessStatus.expired,
      );
      return Future.value(false);
    }
    if (!force &&
        const {
          WebsiteAccessStatus.expired,
          WebsiteAccessStatus.mismatch,
          WebsiteAccessStatus.challenge,
          WebsiteAccessStatus.cleanupRequired,
        }.contains(state.status)) {
      return Future.value(false);
    }
    final key = '$_generation:${user.id}:${snapshot!.authenticationKey}';
    if (_verification != null && _verificationKey == key) return _verification!;
    if (!force && snapshot.isVerifiedFor(user.id, DateTime.now())) {
      if (state.status != WebsiteAccessStatus.available) {
        state = _snapshotState(snapshot);
      }
      return Future.value(true);
    }
    final generation = _generation;
    _verificationKey = key;
    final result = Completer<bool>();
    final future = result.future;
    _verification = future;
    unawaited(
      _verify(
        snapshot,
        user,
        generation,
      ).then(result.complete, onError: result.completeError),
    );
    return future.whenComplete(() {
      if (identical(_verification, future)) {
        _verification = null;
        _verificationKey = null;
      }
    });
  }

  Future<bool> _reloadForVerification() async {
    final reloading = reload();
    final generation = _generation;
    await reloading;
    if (!mounted || generation != _generation || _readFailed) return false;
    return ensureVerified(force: true);
  }

  Future<bool> _verify(
    WebsiteSessionSnapshot snapshot,
    BangumiUser user,
    int generation,
  ) async {
    state = state.copyWith(
      status: WebsiteAccessStatus.checking,
      clearMessage: true,
    );
    try {
      final id = await _probeOnce(snapshot, user, generation);
      if (!mounted ||
          generation != _generation ||
          _expectedUser?.id != user.id) {
        return false;
      }
      final verified = snapshot.withVerifiedUser(id);
      await _write(() async {
        if (mounted && generation == _generation) await _store.write(verified);
      });
      if (!mounted || generation != _generation) return false;
      state = _snapshotState(verified);
      return true;
    } catch (error) {
      if (mounted && generation == _generation) {
        final rejected =
            error is WebsiteAccessException && error.status.requiresLogin;
        final revoked = rejected ? snapshot.withoutVerification() : null;
        if (rejected) _rejectedRequests.add(snapshot.requestKey);
        // Enqueue accepted revocations before notifying listeners. A listener
        // may reload immediately; reload must wait for this durable state.
        final saving = revoked == null
            ? null
            : _write(() => _store.write(revoked));
        state = state.copyWith(
          snapshot: revoked,
          status: error is WebsiteAccessException
              ? error.status
              : WebsiteAccessStatus.unavailable,
          message: error is WebsiteAccessException
              ? error.message
              : '账号核验暂时失败，请稍后重试',
        );
        if (revoked != null) {
          try {
            await saving;
          } catch (_) {
            if (mounted && generation == _generation) {
              state = state.copyWith(message: '网站核验已失效，但状态保存失败，请重试');
            }
          }
        }
      }
      return false;
    }
  }

  Future<WebsiteSessionSnapshot> requireVerifiedSession(
    BangumiUser? user,
  ) async {
    if (user == null) {
      throw const WebsiteAccessException(
        WebsiteAccessStatus.missing,
        '请先登录 Bangumi 账号',
      );
    }
    await attachAccount(user);
    if (!await ensureVerified() ||
        _expectedUser?.id != user.id ||
        state.snapshot == null) {
      throw WebsiteAccessException(
        state.status,
        state.message ?? state.statusLabel,
      );
    }
    return state.snapshot!;
  }

  bool reportFailure(WebsiteAccessStatus status, String requestKey) {
    if (!mounted || state.snapshot?.requestKey != requestKey) return false;
    _rejectedRequests.add(requestKey);
    ++_generation;
    _verification = null;
    _verificationKey = null;
    final snapshot = state.snapshot!.withoutVerification();
    // Later captures/logout queue after this write. A plain reload must not
    // cancel it and restore the rejected binding from disk.
    final saving = _write(() => _store.write(snapshot));
    state = state.copyWith(
      snapshot: snapshot,
      status: status,
      clearMessage: true,
    );
    unawaited(saving.catchError((Object _) {}));
    return true;
  }

  Future<void> _write(Future<void> Function() action) {
    final future = _writes.then((_) => action());
    _writes = future.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return future;
  }

  Future<void> reload() async {
    final generation = ++_generation;
    try {
      await _writes;
      final snapshot = await _store.read();
      if (!mounted || generation != _generation) return;
      _readFailed = false;
      state = _snapshotState(snapshot);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      _readFailed = true;
      state = state.copyWith(
        ready: true,
        status: WebsiteAccessStatus.unavailable,
        message: '无法读取网站登录，已保留原记录，请重试',
      );
    }
  }

  /// Capture belongs to the session that requested it, even if the native
  /// browser responds after logout. Unchanged cookies need no disk write.
  Future<bool> captureCookies(
    Future<List<WebsiteCookie>> Function() capture, {
    bool automatic = false,
    WebsiteBrowserIdentity? browserIdentity,
  }) async {
    final generation = _generation;
    try {
      final cookies = await capture();
      if (!mounted || generation != _generation) return false;
      final snapshot = WebsiteSessionSnapshot(
        cookies: cookies,
        syncedAt: DateTime.now(),
      );
      if (automatic &&
          !cookies.any(
            (cookie) =>
                cookie.name.toLowerCase().endsWith('_auth') &&
                cookie.value.isNotEmpty &&
                !cookie.isExpired,
          )) {
        return false;
      }
      if (browserIdentity == null &&
          snapshot.hasSessionCookies &&
          snapshot.cookieHeader == state.snapshot?.cookieHeader) {
        return _expectedUser == null
            ? true
            : ensureVerified(
                force: state.status != WebsiteAccessStatus.available,
              );
      }
      return saveCookies(cookies, browserIdentity: browserIdentity);
    } catch (_) {
      if (mounted && generation == _generation && !automatic) {
        state = state.copyWith(message: '无法保存登录，请重试');
      }
      return false;
    }
  }

  Future<bool> saveCookies(
    List<WebsiteCookie> cookies, {
    DateTime? syncedAt,
    WebsiteBrowserIdentity? browserIdentity,
  }) {
    final generation = ++_generation;
    final result = Completer<bool>();
    final future = result.future;
    _captureVerification = future;
    _captureGeneration = generation;
    unawaited(
      _saveCookies(
        cookies,
        generation: generation,
        syncedAt: syncedAt,
        browserIdentity: browserIdentity,
      ).then(result.complete, onError: result.completeError),
    );
    return future.whenComplete(() {
      if (identical(_captureVerification, future)) {
        _captureVerification = null;
        _captureGeneration = null;
      }
    });
  }

  Future<bool> _saveCookies(
    List<WebsiteCookie> cookies, {
    required int generation,
    DateTime? syncedAt,
    WebsiteBrowserIdentity? browserIdentity,
  }) async {
    final cleaned = [
      for (final cookie in cookies)
        if (cookie.name.trim().isNotEmpty && cookie.value.isNotEmpty) cookie,
    ];
    if (cleaned.isEmpty) {
      state = state.copyWith(ready: true, message: '未检测到登录，请登录后再保存');
      return false;
    }
    var snapshot = WebsiteSessionSnapshot(
      cookies: cleaned,
      syncedAt: syncedAt ?? DateTime.now(),
    );
    if (!snapshot.hasSessionCookies) {
      state = state.copyWith(ready: true, message: '未检测到有效登录，请登录后再保存');
      return false;
    }
    final previous = state.snapshot;
    final browserMatches = browserIdentity?.matches(snapshot) == true;
    snapshot = WebsiteSessionSnapshot(
      cookies: snapshot.cookies,
      syncedAt: snapshot.syncedAt,
      userAgent: browserMatches
          ? browserIdentity!.userAgent
          : previous?.authenticationKey == snapshot.authenticationKey
          ? previous?.userAgent
          : null,
    );
    if (previous != null &&
        previous.verifiedUserId != null &&
        previous.isVerifiedFor(previous.verifiedUserId!, DateTime.now()) &&
        previous.authenticationKey == snapshot.authenticationKey) {
      snapshot = snapshot.withVerifiedUser(previous.verifiedUserId!);
      snapshot = WebsiteSessionSnapshot(
        cookies: snapshot.cookies,
        syncedAt: snapshot.syncedAt,
        verifiedUserId: previous.verifiedUserId,
        verifiedAt: previous.verifiedAt,
        verificationVersion: previous.verificationVersion,
        userAgent: snapshot.userAgent,
      );
    }
    final expected = _expectedUser;
    final browserIdentifier = browserIdentity?.identifierFor(snapshot);
    if (expected != null &&
        (browserIdentifier != null ||
            !snapshot.isVerifiedFor(expected.id, DateTime.now()))) {
      state = state.copyWith(
        snapshot: snapshot,
        status: WebsiteAccessStatus.checking,
        clearMessage: true,
      );
      try {
        final id = browserIdentifier != null
            ? await _probe.verifyIdentifier(browserIdentifier, expected)
            : await _probeOnce(snapshot, expected, generation);
        if (!mounted ||
            generation != _generation ||
            _expectedUser?.id != expected.id) {
          return false;
        }
        snapshot = snapshot.withVerifiedUser(id);
      } catch (error) {
        if (mounted && generation == _generation) {
          final unverified = snapshot.withoutVerification();
          // Preserve the captured cookies for recovery, but never keep a
          // verified binding in memory after persisting it as unverified.
          // A different browser account must not replace the saved account.
          final rejectedCurrent =
              error is WebsiteAccessException &&
              error.status.requiresLogin &&
              error.status != WebsiteAccessStatus.mismatch &&
              previous != null &&
              previous.authenticationKey == snapshot.authenticationKey;
          if (rejectedCurrent) _rejectedRequests.add(previous.requestKey);
          if (error is WebsiteAccessException &&
              (error.status == WebsiteAccessStatus.unavailable ||
                  rejectedCurrent)) {
            try {
              await _write(() => _store.write(unverified));
            } catch (_) {
              // The original verification error remains the relevant state.
            }
          }
          if (!mounted || generation != _generation) return false;
          state = state.copyWith(
            snapshot: unverified,
            status: error is WebsiteAccessException
                ? error.status
                : WebsiteAccessStatus.unavailable,
            message: error is WebsiteAccessException
                ? error.message
                : '暂时无法核验登录，请稍后重试',
          );
        }
        return false;
      }
    }
    try {
      await _write(() async {
        if (mounted && generation == _generation) await _store.write(snapshot);
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        state = state.copyWith(
          ready: true,
          status: WebsiteAccessStatus.unavailable,
          message: '保存网站会话失败，请重试',
        );
      }
      return false;
    }
    if (!mounted || generation != _generation) return false;
    _readFailed = false;
    state = _snapshotState(
      snapshot,
      message: expected == null ? '网站会话已保存，等待账号核验' : '账号验证完成',
    );
    return true;
  }

  /// Serialize identity binding with captures and logout; a late probe cannot
  /// attach an identity to a different cookie session or restore a cleared one.
  Future<bool> bindVerifiedUser({
    required String authenticationKey,
    required String requestKey,
    required int userId,
  }) async {
    if (!mounted ||
        userId <= 0 ||
        authenticationKey.isEmpty ||
        state.requiresLogin ||
        state.status == WebsiteAccessStatus.checking ||
        (_expectedUser != null && _expectedUser!.id != userId) ||
        state.snapshot?.authenticationKey != authenticationKey) {
      return false;
    }
    if (state.snapshot!.isVerifiedFor(userId, DateTime.now())) {
      return true;
    }
    if (state.snapshot!.requestKey != requestKey) return false;
    final generation = ++_generation;
    var bound = false;
    try {
      await _write(() async {
        if (!mounted || generation != _generation) return;
        final snapshot = await _store.read();
        if (!mounted ||
            generation != _generation ||
            snapshot?.authenticationKey != authenticationKey ||
            snapshot?.requestKey != requestKey) {
          return;
        }
        final next = snapshot!.withVerifiedUser(userId);
        await _store.write(next);
        if (!mounted || generation != _generation) return;
        state = _snapshotState(next);
        bound = true;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        state = state.copyWith(message: '无法保存已核对的账号，请重试');
      }
    }
    return bound;
  }

  Future<void> clear({String? message}) async {
    final generation = ++_generation;
    _readFailed = false;
    state = WebsiteSessionState(ready: true, message: message ?? '已清除网站登录会话');
    try {
      await _write(_store.clear);
      await WebsiteCookieBridge.clearBgmCookies(strict: true);
    } catch (_) {
      if (mounted && generation == _generation) {
        state = state.copyWith(
          status: WebsiteAccessStatus.cleanupRequired,
          message: '清理网站会话失败，请重试',
        );
      }
    }
  }

  /// Reflect sign-out immediately and clear storage after pending saves.
  Future<void> markCleared({String? message}) {
    _generation++;
    _readFailed = false;
    state = WebsiteSessionState(ready: true, message: message);
    // Complete any in-flight save before clearing it. A newer save then queues
    // after this cleanup, so an old write cannot erase the new website session.
    return _write(_store.clear).catchError((Object _) {});
  }
}
