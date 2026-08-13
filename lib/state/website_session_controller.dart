import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/website_cookie_bridge.dart';
import '../core/auth/website_session.dart';

final websiteSessionStoreProvider = Provider<WebsiteSessionStore>((ref) {
  return WebsiteSessionStore();
});

final websiteSessionProvider =
    StateNotifierProvider<WebsiteSessionController, WebsiteSessionState>((
      ref,
    ) {
      return WebsiteSessionController(ref.watch(websiteSessionStoreProvider));
    });

class WebsiteSessionState {
  const WebsiteSessionState({
    this.ready = false,
    this.snapshot,
    this.message,
  });

  final bool ready;
  final WebsiteSessionSnapshot? snapshot;
  final String? message;

  bool get isSynced => snapshot?.hasSessionCookies == true;

  String get statusLabel {
    if (!ready) return '检查中…';
    if (!isSynced) return '未同步 · 加组/私信需网站登录';
    final time = snapshot!.syncedAt;
    final stamp =
        '${time.month.toString().padLeft(2, '0')}-'
        '${time.day.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
    return '已同步 · $stamp';
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

  /// Bumped whenever the store is cleared (sign-out): in-flight saves that
  /// started before the clear must not resurrect the previous session.
  int _generation = 0;

  Future<void> reload() async {
    final snapshot = await _store.read();
    state = WebsiteSessionState(ready: true, snapshot: snapshot);
  }

  Future<bool> saveCookies(
    List<WebsiteCookie> cookies, {
    DateTime? syncedAt,
  }) async {
    final generation = _generation;
    final cleaned = [
      for (final cookie in cookies)
        if (cookie.name.trim().isNotEmpty && cookie.value.isNotEmpty) cookie,
    ];
    if (cleaned.isEmpty) {
      state = state.copyWith(
        ready: true,
        message: '未捕获到网站 Cookie，请确认已在页面中登录成功',
      );
      return false;
    }
    final snapshot = WebsiteSessionSnapshot(
      cookies: cleaned,
      syncedAt: syncedAt ?? DateTime.now(),
    );
    if (!snapshot.hasSessionCookies) {
      state = state.copyWith(
        ready: true,
        message: '已获取 Cookie，但未识别到登录会话。请登录后再点「保存」',
      );
      // Still persist — some environments only expose partial cookies.
    }
    await _store.write(snapshot);
    if (generation != _generation) {
      // The store was cleared (sign-out) while this save was in flight: the
      // snapshot just written belongs to the previous session. Undo the
      // write and keep the cleared in-memory state.
      try {
        await _store.clear();
      } catch (_) {
        // Best-effort: the generation check still prevents the stale write
        // from being trusted as the current session.
      }
      return false;
    }
    state = WebsiteSessionState(
      ready: true,
      snapshot: snapshot,
      message: snapshot.hasSessionCookies
          ? '网站登录已同步，加组/私信将自动带上会话'
          : '已保存 Cookie（会话特征较弱，若仍需登录请重试）',
    );
    return true;
  }

  Future<void> clear({String? message}) async {
    _generation++;
    await _store.clear();
    await WebsiteCookieBridge.clearBgmCookies();
    state = WebsiteSessionState(
      ready: true,
      message: message ?? '已清除网站登录会话',
    );
  }

  /// Reflect an external storage wipe (e.g. OAuth force sign-out) without
  /// re-deleting secure storage.
  void markCleared({String? message}) {
    _generation++;
    state = WebsiteSessionState(
      ready: true,
      message: message,
    );
  }
}
