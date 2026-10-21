import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart' as mobile;
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart'
    as windows;

import 'website_session.dart';
import 'auth_cleanup_marker.dart';

/// Platform helpers to capture / inject Bangumi website cookies for WebViews.
class WebsiteCookieBridge {
  const WebsiteCookieBridge._();

  static const bgmOrigin = 'https://bgm.tv';
  static const bgmHost = 'bgm.tv';
  static const _cookieOrigins = [bgmOrigin];
  static const _androidCookies = MethodChannel('mubangumi/website_cookies');
  static const _appleCookies = MethodChannel('mubangumi/apple_website_cookies');

  static Future<void>? _cookieWrites;
  static Future<void>? _pendingCleanup;
  static bool _cleanupFailed = false;
  static bool _cleanupRunning = false;
  static int _testEpoch = 0;
  static Future<void> Function()? _testCleanup;
  static bool get cleanupNeedsRetry => _cleanupFailed;
  static Future<void>? get pendingCleanup => _pendingCleanup;
  static void requireCleanup() {
    _cleanupFailed = true;
  }

  @visibleForTesting
  static void resetForTests() {
    _testEpoch++;
    _cookieWrites = null;
    _pendingCleanup = null;
    _cleanupFailed = false;
    _cleanupRunning = false;
    _testCleanup = null;
  }

  @visibleForTesting
  static void setCleanupForTests(Future<void> Function()? cleanup) {
    _testCleanup = cleanup;
  }

  static Future<void> waitForPendingCleanup() async {
    final marker = await AuthCleanupMarker.current();
    if ((marker.websitePending || _cleanupFailed) && !_cleanupRunning) {
      if (marker.websiteStorePending) await WebsiteSessionStore().clear();
      await clearBgmCookies(strict: true);
    }
    try {
      await _pendingCleanup?.timeout(const Duration(seconds: 8));
    } catch (_) {
      throw StateError('上次网页会话清理尚未完成，请重试清理后登录');
    }
    if (_cleanupFailed) throw StateError('上次网页会话清理失败，请重试清理后登录');
    if ((await AuthCleanupMarker.current()).websitePending) {
      throw StateError('网页登录清理尚未完成，请重试清理后登录');
    }
  }

  static Future<void> _writeCookies(Future<void> Function() action) {
    final previous = _cookieWrites;
    final next = previous == null
        ? Future<void>.sync(action)
        : previous.then((_) => action());
    late final Future<void> settled;
    settled = next
        .then<void>((_) {}, onError: (Object _, StackTrace _) {})
        .whenComplete(() {
          if (identical(_cookieWrites, settled)) _cookieWrites = null;
        });
    _cookieWrites = settled;
    return next;
  }

  /// Logout stays responsive; subsequent injection must wait for the cleanup.
  static Future<void> clearBgmCookies({bool strict = false}) async {
    final epoch = _testEpoch;
    final testCleanup = _testCleanup;
    final String nonce;
    try {
      nonce = await AuthCleanupMarker.beginWebsiteCleanup();
    } catch (_) {
      _cleanupFailed = true;
      rethrow;
    }
    if (epoch != _testEpoch) return;
    final cleanup = _writeCookies(() async {
      try {
        if (testCleanup != null) {
          await testCleanup();
        } else if (Platform.isWindows) {
          await _clearWindowsCookies();
        } else if (Platform.isAndroid) {
          await _androidCookieManager().clearCookies();
        } else if (Platform.isIOS || Platform.isMacOS) {
          await mobile.WebViewCookieManager().clearCookies();
        }
        await AuthCleanupMarker.completeWebsiteCookies(nonce);
        if (epoch == _testEpoch) _cleanupFailed = false;
      } catch (_) {
        if (epoch == _testEpoch) _cleanupFailed = true;
        rethrow;
      }
    });
    _pendingCleanup = cleanup;
    _cleanupRunning = true;
    void settled() {
      if (identical(_pendingCleanup, cleanup)) _cleanupRunning = false;
    }

    unawaited(
      cleanup.then<void>(
        (_) => settled(),
        onError: (Object _, StackTrace _) => settled(),
      ),
    );
    if (Platform.isWindows && !strict) {
      runDetachedBestEffort(() => cleanup);
      return;
    }
    try {
      await cleanup.timeout(const Duration(seconds: 8));
    } catch (error, stack) {
      _reportCleanupFailure(error, stack);
      if (strict) rethrow;
    }
  }

  /// Runs [task] detached from the caller so slow platform cleanups never
  /// block sign-out. Failures are routed to [onFailure] (defaulting to a
  /// prefixed log line) instead of the zone's unhandled-error handler.
  @visibleForTesting
  static void runDetachedBestEffort(
    Future<void> Function() task, {
    void Function(Object error, StackTrace stack)? onFailure,
  }) {
    unawaited(() async {
      try {
        await task();
      } catch (error, stack) {
        (onFailure ?? _reportCleanupFailure)(error, stack);
      }
    }());
  }

  /// Greppable prefix so stale-cookie leftovers after sign-out are traceable.
  static const _cleanupFailurePrefix = '[BGM-COOKIE-CLEANUP]';

  static void _reportCleanupFailure(Object error, StackTrace stack) {
    debugPrint(
      '$_cleanupFailurePrefix WebsiteCookieBridge.clearBgmCookies failed; '
      'stale bgm.tv website session may survive sign-out: ${error.runtimeType}\n$stack',
    );
  }

  static Future<void> _clearWindowsCookies() async {
    final controller = windows.WebviewController();
    try {
      await controller.initialize();
      for (final origin in const [
        bgmOrigin,
        'https://bangumi.tv',
        'https://chii.in',
      ]) {
        final cookies = await controller.getCookies(origin);
        for (final name in cookies.map((cookie) => cookie.name).toSet()) {
          await controller.deleteCookies(name, uri: origin);
        }
      }
    } finally {
      try {
        await controller.dispose();
      } catch (_) {
        // Disposal failure must not mask the cleanup result.
      }
    }
  }

  /// Inject stored cookies into a mobile WebView cookie jar before navigation.
  static Future<void> injectMobile(List<WebsiteCookie> cookies) async {
    if (!(Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) return;
    final epoch = _testEpoch;
    await waitForPendingCleanup();
    if (epoch != _testEpoch) return;
    await _writeCookies(() async {
      if (epoch != _testEpoch) return;
      if (_cleanupFailed) throw StateError('上次网页会话清理失败，请重试清理后登录');
      if (cookies.isEmpty) return;
      if (!(Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) return;
      try {
        if (Platform.isAndroid) {
          await injectAndroidCookies(cookies);
          return;
        }
        if (Platform.isIOS) {
          await injectAppleCookies(cookies);
          return;
        }
        // iOS / macOS: common cookie manager setCookie (HttpOnly may be limited).
        final manager = mobile.WebViewCookieManager();
        for (final cookie in cookies.where((cookie) => !cookie.isExpired)) {
          await manager.setCookie(
            WebViewCookie(
              name: cookie.name,
              value: cookie.value,
              domain: _normalizedDomain(cookie.domain),
              path: cookie.path.isEmpty ? '/' : cookie.path,
            ),
          );
        }
      } catch (error, stack) {
        debugPrint(
          'WebsiteCookieBridge.injectMobile failed: ${error.runtimeType}\n$stack',
        );
      }
    });
  }

  /// Inject stored cookies into a Windows WebView2 controller.
  static Future<void> injectWindows(
    windows.WebviewController controller,
    List<WebsiteCookie> cookies,
  ) async {
    final epoch = _testEpoch;
    await waitForPendingCleanup();
    if (epoch != _testEpoch) return;
    await _writeCookies(() async {
      if (epoch != _testEpoch) return;
      if (_cleanupFailed) throw StateError('上次网页会话清理失败，请重试清理后登录');
      if (cookies.isEmpty) return;
      try {
        for (final cookie in cookies.where((cookie) => !cookie.isExpired)) {
          await controller.setCookie(
            windows.WebviewCookie(
              name: cookie.name,
              value: cookie.value,
              domain: _normalizedDomain(cookie.domain),
              path: cookie.path.isEmpty ? '/' : cookie.path,
              expires: cookie.expiresAt,
              isSecure: cookie.isSecure,
              isHttpOnly: cookie.isHttpOnly,
            ),
          );
        }
      } catch (error, stack) {
        debugPrint(
          'WebsiteCookieBridge.injectWindows failed: ${error.runtimeType}\n$stack',
        );
      }
    });
  }

  /// Read cookies from the active platform WebView session.
  static Future<List<WebsiteCookie>> capture({
    windows.WebviewController? windowsController,
    mobile.WebViewController? mobileController,
  }) async {
    await _cookieWrites;
    if (Platform.isWindows && windowsController != null) {
      return _captureWindows(windowsController);
    }
    if (Platform.isAndroid) {
      return captureAndroidCookies();
    }
    if (Platform.isIOS) {
      return captureAppleCookies();
    }
    if (Platform.isIOS || Platform.isMacOS) {
      try {
        // Read the native cookie store, including HttpOnly login cookies.
        final cookies = await mobile.WebViewCookieManager().platform.getCookies(
          Uri.parse(bgmOrigin),
        );
        if (cookies.isNotEmpty) {
          return [
            for (final cookie in cookies)
              WebsiteCookie(
                name: cookie.name,
                value: cookie.value,
                domain: cookie.domain,
                path: cookie.path,
              ),
          ];
        }
      } catch (_) {
        // Older platform implementations may only support document.cookie.
      }
    }
    if (mobileController != null) {
      return _captureDocumentCookie(mobileController);
    }
    return const [];
  }

  static Future<List<WebsiteCookie>> _captureWindows(
    windows.WebviewController controller,
  ) async {
    try {
      final byName = <String, WebsiteCookie>{};
      for (final origin in _cookieOrigins) {
        final cookies = await controller.getCookies(origin);
        for (final cookie in cookies) {
          if (cookie.name.isEmpty) continue;
          byName[cookie.name] = WebsiteCookie(
            name: cookie.name,
            value: cookie.value,
            domain: cookie.domain.isEmpty ? '.bgm.tv' : cookie.domain,
            path: cookie.path.isEmpty ? '/' : cookie.path,
            expiresAt: cookie.expires,
            isSecure: cookie.isSecure,
            isHttpOnly: cookie.isHttpOnly,
          );
        }
      }
      return byName.values.toList();
    } catch (error, stack) {
      debugPrint(
        'WebsiteCookieBridge._captureWindows failed: ${error.runtimeType}\n$stack',
      );
      return const [];
    }
  }

  @visibleForTesting
  static Future<List<WebsiteCookie>> captureAndroidCookies() async {
    final raw = await _androidCookies
        .invokeMethod<String>('readBgmCookies')
        .timeout(const Duration(seconds: 8));
    return WebsiteSessionSnapshot.parseDocumentCookie(raw ?? '');
  }

  @visibleForTesting
  static Future<void> injectAndroidCookies(List<WebsiteCookie> cookies) async {
    await _injectCookieHeaders(cookies, _androidCookies);
  }

  @visibleForTesting
  static Future<void> injectAppleCookies(List<WebsiteCookie> cookies) =>
      _injectCookieHeaders(cookies, _appleCookies);

  @visibleForTesting
  static Future<List<WebsiteCookie>> captureAppleCookies() async {
    final raw = await _appleCookies
        .invokeMethod<List<dynamic>>('readBgmCookies')
        .timeout(const Duration(seconds: 8));
    return [
      for (final row in raw ?? [])
        if (row is Map) WebsiteCookie.fromJson(Map<String, dynamic>.from(row)),
    ];
  }

  static Future<void> _injectCookieHeaders(
    List<WebsiteCookie> cookies,
    MethodChannel channel,
  ) async {
    for (final cookie in cookies.where((c) => !c.isExpired)) {
      final domain = cookie.domain.toLowerCase();
      final path = cookie.path.isEmpty ? '/' : cookie.path;
      if (!const ['bgm.tv', '.bgm.tv'].contains(domain) ||
          !RegExp(r'^[!#$%&\x27*+.^_`|~0-9A-Za-z-]+$').hasMatch(cookie.name) ||
          RegExp(r'[\x00-\x20\x7f;]').hasMatch(cookie.value) ||
          !path.startsWith('/') ||
          RegExp(r'[\x00-\x20\x7f;]').hasMatch(path)) {
        continue;
      }
      final header =
          '${cookie.name}=${cookie.value}; Domain=$domain; Path=$path'
          '${cookie.isSecure ? '; Secure' : ''}'
          '${cookie.isHttpOnly ? '; HttpOnly' : ''}'
          '${cookie.expiresAt == null ? '' : '; Expires=${HttpDate.format(cookie.expiresAt!.toUtc())}'}';
      await channel
          .invokeMethod<void>('setBgmCookie', {'header': header})
          .timeout(const Duration(seconds: 8));
    }
  }

  static Future<List<WebsiteCookie>> _captureDocumentCookie(
    mobile.WebViewController controller,
  ) async {
    try {
      final raw = await controller.runJavaScriptReturningResult(
        'document.cookie',
      );
      // Strip only the surrounding JS string quotes, never quotes that may
      // legitimately appear inside cookie values.
      var text = raw is String ? raw : raw.toString();
      text = text.trim();
      if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
        text = text.substring(1, text.length - 1);
      }
      return WebsiteSessionSnapshot.parseDocumentCookie(text);
    } catch (error, stack) {
      debugPrint(
        'WebsiteCookieBridge._captureDocumentCookie failed: ${error.runtimeType}\n$stack',
      );
      return const [];
    }
  }

  static AndroidWebViewCookieManager _androidCookieManager() {
    const params = PlatformWebViewCookieManagerCreationParams();
    return AndroidWebViewCookieManager(
      AndroidWebViewCookieManagerCreationParams.fromPlatformWebViewCookieManagerCreationParams(
        params,
      ),
    );
  }

  static String _normalizedDomain(String domain) {
    final value = domain.trim();
    if (value.isEmpty || value.contains('://')) return '.bgm.tv';
    if (value.startsWith('.')) return value;
    // Exact or subdomain match only: endsWith alone would treat a host like
    // notbgm.tv as a Bangumi domain.
    if (value == 'bgm.tv' || value.endsWith('.bgm.tv')) {
      return '.$value'.replaceAll('..', '.');
    }
    return value;
  }
}
