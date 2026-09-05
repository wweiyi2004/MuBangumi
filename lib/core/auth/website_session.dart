import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// One cookie captured from the Bangumi website WebView session.
class WebsiteCookie {
  const WebsiteCookie({
    required this.name,
    required this.value,
    this.domain = '.bgm.tv',
    this.path = '/',
    this.expiresAt,
    this.isSecure = true,
    this.isHttpOnly = false,
  });

  final String name;
  final String value;
  final String domain;
  final String path;
  final DateTime? expiresAt;
  final bool isSecure;
  final bool isHttpOnly;

  Map<String, dynamic> toJson() => {
    'name': name,
    'value': value,
    'domain': domain,
    'path': path,
    'expires_at': expiresAt?.toIso8601String(),
    'secure': isSecure,
    'http_only': isHttpOnly,
  };

  factory WebsiteCookie.fromJson(Map<String, dynamic> json) => WebsiteCookie(
    name: json['name']?.toString() ?? '',
    value: json['value']?.toString() ?? '',
    domain: json['domain']?.toString().isNotEmpty == true
        ? json['domain'].toString()
        : '.bgm.tv',
    path: json['path']?.toString().isNotEmpty == true
        ? json['path'].toString()
        : '/',
    expiresAt: DateTime.tryParse(json['expires_at']?.toString() ?? ''),
    isSecure: json['secure'] != false,
    isHttpOnly: json['http_only'] == true,
  );

  bool get looksLikeSession =>
      name.toLowerCase().contains('chii') ||
      name.toLowerCase().contains('auth') ||
      name.toLowerCase().contains('sid') ||
      name.toLowerCase().contains('session') ||
      name.toLowerCase().contains('token');

  bool get isExpired =>
      expiresAt != null && !expiresAt!.isAfter(DateTime.now());
}

/// Persisted website login snapshot (supplemental to OAuth).
class WebsiteSessionSnapshot {
  const WebsiteSessionSnapshot({required this.cookies, required this.syncedAt});

  final List<WebsiteCookie> cookies;
  final DateTime syncedAt;

  bool get hasSessionCookies => cookies.any(
    (cookie) =>
        cookie.name.isNotEmpty &&
        cookie.value.isNotEmpty &&
        !cookie.isExpired &&
        cookie.looksLikeSession,
  );

  bool get isEmpty => cookies.isEmpty;

  /// Cookie header for future Dio / HTML requests.
  String get cookieHeader => [
    for (final cookie in cookies)
      if (cookie.name.isNotEmpty && !cookie.isExpired)
        '${cookie.name}=${cookie.value}',
  ].join('; ');

  Map<String, dynamic> toJson() => {
    'synced_at': syncedAt.toIso8601String(),
    'cookies': [for (final cookie in cookies) cookie.toJson()],
  };

  factory WebsiteSessionSnapshot.fromJson(Map<String, dynamic> json) {
    final raw = json['cookies'];
    final cookies = <WebsiteCookie>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          final cookie = WebsiteCookie.fromJson(
            Map<String, dynamic>.from(item),
          );
          if (cookie.name.isNotEmpty) cookies.add(cookie);
        }
      }
    }
    return WebsiteSessionSnapshot(
      cookies: cookies,
      syncedAt:
          DateTime.tryParse(json['synced_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  /// Parse `document.cookie` / `a=b; c=d` style strings.
  static List<WebsiteCookie> parseDocumentCookie(
    String raw, {
    String domain = '.bgm.tv',
  }) {
    final cookies = <WebsiteCookie>[];
    for (final part in raw.split(';')) {
      final piece = part.trim();
      if (piece.isEmpty) continue;
      final eq = piece.indexOf('=');
      if (eq <= 0) continue;
      final name = piece.substring(0, eq).trim();
      final value = piece.substring(eq + 1).trim();
      if (name.isEmpty) continue;
      cookies.add(
        WebsiteCookie(name: name, value: value, domain: domain, path: '/'),
      );
    }
    return cookies;
  }
}

class WebsiteSessionStore {
  WebsiteSessionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'bangumi_website_session_v1';
  final FlutterSecureStorage _storage;

  Future<WebsiteSessionSnapshot?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final snapshot = WebsiteSessionSnapshot.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      return snapshot.isEmpty ? null : snapshot;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(WebsiteSessionSnapshot snapshot) async {
    await _storage.write(key: _key, value: jsonEncode(snapshot.toJson()));
  }

  Future<void> clear() => _storage.delete(key: _key);
}
