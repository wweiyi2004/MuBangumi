import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/website_cookie_bridge.dart';
import '../core/auth/website_session.dart';

final websiteSessionStoreProvider = Provider<WebsiteSessionStore>((ref) {
  return WebsiteSessionStore();
});

final websiteSessionProvider =
    StateNotifierProvider<WebsiteSessionController, WebsiteSessionState>((ref) {
      return WebsiteSessionController(ref.watch(websiteSessionStoreProvider));
    });

class WebsiteSessionState {
  const WebsiteSessionState({this.ready = false, this.snapshot, this.message});

  final bool ready;
  final WebsiteSessionSnapshot? snapshot;
  final String? message;

  bool get isSynced => snapshot?.hasSessionCookies == true;

  String get statusLabel {
    if (!ready) return '检查中…';
    if (!isSynced) return '需要网站登录';
    final time = snapshot!.syncedAt;
    final stamp =
        '${time.month.toString().padLeft(2, '0')}-'
        '${time.day.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
    return '登录已保存 · $stamp';
  }

  WebsiteSessionState copyWith({
    bool? ready,
    WebsiteSessionSnapshot? snapshot,
    String? message,
    bool clearSnapshot = false,
    bool clearMessage = false,
  }) => WebsiteSessionState(
    ready: ready ?? this.ready,
    snapshot: clearSnapshot ? null : snapshot ?? this.snapshot,
    message: clearMessage ? null : message ?? this.message,
  );
}

class WebsiteSessionController extends StateNotifier<WebsiteSessionState> {
  WebsiteSessionController(this._store) : super(const WebsiteSessionState()) {
    unawaited(reload());
  }

  final WebsiteSessionStore _store;

  /// Each operation supersedes earlier reads and saves, including sign-out.
  int _generation = 0;
  Future<void> _writes = Future<void>.value();

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
      state = WebsiteSessionState(ready: true, snapshot: snapshot);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      state = const WebsiteSessionState(
        ready: true,
        message: '无法读取网站登录，请重新登录网站',
      );
    }
  }

  /// Capture belongs to the session that requested it, even if the native
  /// browser responds after logout. Unchanged cookies need no disk write.
  Future<bool> captureCookies(
    Future<List<WebsiteCookie>> Function() capture, {
    bool automatic = false,
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
      if (snapshot.hasSessionCookies &&
          snapshot.cookieHeader == state.snapshot?.cookieHeader) {
        return true;
      }
      return saveCookies(cookies);
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
  }) async {
    final generation = ++_generation;
    final cleaned = [
      for (final cookie in cookies)
        if (cookie.name.trim().isNotEmpty && cookie.value.isNotEmpty) cookie,
    ];
    if (cleaned.isEmpty) {
      state = state.copyWith(ready: true, message: '未检测到登录，请登录后再保存');
      return false;
    }
    final snapshot = WebsiteSessionSnapshot(
      cookies: cleaned,
      syncedAt: syncedAt ?? DateTime.now(),
    );
    if (!snapshot.hasSessionCookies) {
      state = state.copyWith(ready: true, message: '未检测到有效登录，请登录后再保存');
      return false;
    }
    try {
      await _write(() async {
        if (mounted && generation == _generation) await _store.write(snapshot);
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        state = state.copyWith(ready: true, message: '保存网站会话失败，请重试');
      }
      return false;
    }
    if (!mounted || generation != _generation) return false;
    state = WebsiteSessionState(
      ready: true,
      snapshot: snapshot,
      message: '网站登录已保存',
    );
    return true;
  }

  Future<void> clear({String? message}) async {
    final generation = ++_generation;
    state = WebsiteSessionState(ready: true, message: message ?? '已清除网站登录会话');
    try {
      await _write(_store.clear);
      await WebsiteCookieBridge.clearBgmCookies();
    } catch (_) {
      if (mounted && generation == _generation) {
        state = state.copyWith(message: '清理网站会话失败，请重试');
      }
    }
  }

  /// Reflect sign-out immediately and clear storage after pending saves.
  Future<void> markCleared({String? message}) {
    _generation++;
    state = WebsiteSessionState(ready: true, message: message);
    // Complete any in-flight save before clearing it. A newer save then queues
    // after this cleanup, so an old write cannot erase the new website session.
    return _write(_store.clear).catchError((Object _) {});
  }
}
