import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart' as mobile;
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart'
    as windows;

import 'website_session.dart';

/// Platform helpers to capture / inject Bangumi website cookies for WebViews.
class WebsiteCookieBridge {
  const WebsiteCookieBridge._();

  static const bgmOrigin = 'https://bgm.tv';
  static const bgmHost = 'bgm.tv';

  /// Best-effort wipe of Bangumi-related cookies from platform WebView jars.
  static Future<void> clearBgmCookies() async {
    try {
      if (Platform.isAndroid) {
        await _androidCookieManager().clearCookies();
        return;
      }
      if (Platform.isIOS || Platform.isMacOS) {
        await mobile.WebViewCookieManager().clearCookies();
        return;
      }
      // Windows WebView2 clear requires a live controller; seed injection will
      // still overwrite known cookies on next open. No-op here.
    } catch (error, stack) {
      debugPrint('WebsiteCookieBridge.clearBgmCookies failed: $error\n$stack');
    }
  }

  /// Inject stored cookies into a mobile WebView cookie jar before navigation.
  static Future<void> injectMobile(List<WebsiteCookie> cookies) async {
    if (cookies.isEmpty) return;
    if (!(Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) return;
    try {
      if (Platform.isAndroid) {
        final manager = _androidCookieManager();
        for (final cookie in cookies) {
          await manager.setCookie(
            WebViewCookie(
              name: cookie.name,
              value: cookie.value,
              domain: _androidCookieUrl(cookie.domain),
              path: cookie.path.isEmpty ? '/' : cookie.path,
            ),
          );
        }
        return;
      }
      // iOS / macOS: common cookie manager setCookie (HttpOnly may be limited).
      final manager = mobile.WebViewCookieManager();
      for (final cookie in cookies) {
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
      debugPrint('WebsiteCookieBridge.injectMobile failed: $error\n$stack');
    }
  }

  /// Inject stored cookies into a Windows WebView2 controller.
  static Future<void> injectWindows(
    windows.WebviewController controller,
    List<WebsiteCookie> cookies,
  ) async {
    if (cookies.isEmpty) return;
    try {
      for (final cookie in cookies) {
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
      debugPrint('WebsiteCookieBridge.injectWindows failed: $error\n$stack');
    }
  }

  /// Read cookies from the active platform WebView session.
  static Future<List<WebsiteCookie>> capture({
    windows.WebviewController? windowsController,
    mobile.WebViewController? mobileController,
  }) async {
    if (Platform.isWindows && windowsController != null) {
      return _captureWindows(windowsController);
    }
    if (Platform.isAndroid) {
      final androidCookies = await _captureAndroid();
      if (androidCookies.isNotEmpty) return androidCookies;
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
      final cookies = await controller.getCookies(bgmOrigin);
      return [
        for (final cookie in cookies)
          if (cookie.name.isNotEmpty)
            WebsiteCookie(
              name: cookie.name,
              value: cookie.value,
              domain: cookie.domain.isEmpty ? '.bgm.tv' : cookie.domain,
              path: cookie.path.isEmpty ? '/' : cookie.path,
              expiresAt: cookie.expires,
              isSecure: cookie.isSecure,
              isHttpOnly: cookie.isHttpOnly,
            ),
      ];
    } catch (error, stack) {
      debugPrint('WebsiteCookieBridge._captureWindows failed: $error\n$stack');
      return const [];
    }
  }

  static Future<List<WebsiteCookie>> _captureAndroid() async {
    try {
      final manager = _androidCookieManager();
      final cookies = await manager.getCookies(Uri.parse(bgmOrigin));
      return [
        for (final cookie in cookies)
          if (cookie.name.isNotEmpty)
            WebsiteCookie(
              name: cookie.name,
              value: cookie.value,
              domain: _normalizedDomain(cookie.domain),
              path: cookie.path.isEmpty ? '/' : cookie.path,
              isSecure: true,
            ),
      ];
    } catch (error, stack) {
      debugPrint('WebsiteCookieBridge._captureAndroid failed: $error\n$stack');
      return const [];
    }
  }

  static Future<List<WebsiteCookie>> _captureDocumentCookie(
    mobile.WebViewController controller,
  ) async {
    try {
      final raw = await controller.runJavaScriptReturningResult(
        'document.cookie',
      );
      final text = raw.toString().replaceAll('"', '');
      return WebsiteSessionSnapshot.parseDocumentCookie(text);
    } catch (error, stack) {
      debugPrint(
        'WebsiteCookieBridge._captureDocumentCookie failed: $error\n$stack',
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
    if (value.endsWith('bgm.tv')) return '.$value'.replaceAll('..', '.');
    return value;
  }

  /// Android CookieManager.setCookie expects a URL, not a bare domain.
  static String _androidCookieUrl(String domain) {
    final host = _normalizedDomain(domain).replaceFirst(RegExp(r'^\.'), '');
    if (host.isEmpty) return bgmOrigin;
    return 'https://$host';
  }
}
