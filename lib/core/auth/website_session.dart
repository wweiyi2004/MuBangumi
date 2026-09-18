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
      const {
        'chii_auth',
        'chii_sid',
        'chii_cvlet_session',
        'chiinextsessionid',
      }.contains(name.toLowerCase()) &&
      const {
        'bgm.tv',
        'bangumi.tv',
        'chii.in',
      }.contains(domain.toLowerCase().replaceFirst(RegExp(r'^\.'), ''));

  bool get isExpired =>
      expiresAt != null && !expiresAt!.isAfter(DateTime.now());
}

/// Persisted website login snapshot (supplemental to OAuth).
class WebsiteSessionSnapshot {
  const WebsiteSessionSnapshot({
    required this.cookies,
    required this.syncedAt,
    this.verifiedUserId,
    this.verifiedAt,
    this.verificationVersion = 0,
  });

  final List<WebsiteCookie> cookies;
  final DateTime syncedAt;

  /// Identity established by the same embedded OAuth flow or website chrome.
  /// Cookie capture alone must never assign this field.
  final int? verifiedUserId;
  final DateTime? verifiedAt;
  final int verificationVersion;

  bool isVerifiedFor(int userId, DateTime now) =>
      hasSessionCookies &&
      verificationVersion == 2 &&
      verifiedUserId == userId &&
      verifiedAt != null &&
      !verifiedAt!.isAfter(now) &&
      now.difference(verifiedAt!) < const Duration(minutes: 10);

  WebsiteSessionSnapshot withVerifiedUser(int userId, {DateTime? at}) =>
      WebsiteSessionSnapshot(
        cookies: cookies,
        syncedAt: syncedAt,
        verifiedUserId: userId,
        verifiedAt: at ?? DateTime.now(),
        verificationVersion: 2,
      );

  WebsiteSessionSnapshot withoutVerification() =>
      WebsiteSessionSnapshot(cookies: cookies, syncedAt: syncedAt);

  bool get hasSessionCookies => cookies.any(
    (cookie) =>
        cookie.name.isNotEmpty &&
        cookie.value.isNotEmpty &&
        !cookie.isExpired &&
        cookie.looksLikeSession,
  );

  bool get isEmpty => cookies.isEmpty;

  /// Authentication cookies identify the session; challenge/theme cookies can
  /// refresh without invalidating a private-message draft or its form.
  String get authenticationKey {
    final active = cookies
        .where(
          (cookie) =>
              !cookie.isExpired &&
              cookie.value.isNotEmpty &&
              cookie.looksLikeSession,
        )
        .toList();
    final auth = active
        .where((cookie) => cookie.name.toLowerCase().endsWith('_auth'))
        .toList();
    final values = [
      for (final cookie in auth.isNotEmpty ? auth : active)
        '${cookie.name}=${cookie.value}',
    ]..sort();
    return values.join('; ');
  }

  /// Cookie header for future Dio / HTML requests.
  String get cookieHeader => [
    for (final cookie in cookies)
      if (cookie.name.isNotEmpty && !cookie.isExpired)
        '${cookie.name}=${cookie.value}',
  ].join('; ');

  Map<String, dynamic> toJson() => {
    'synced_at': syncedAt.toIso8601String(),
    'cookies': [for (final cookie in cookies) cookie.toJson()],
    if (verifiedUserId != null) 'verified_user_id': verifiedUserId,
    if (verifiedAt != null) 'verified_at': verifiedAt!.toIso8601String(),
    'verification_version': verificationVersion,
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
      verifiedUserId:
          json['verified_user_id'] is int &&
              (json['verified_user_id'] as int) > 0
          ? json['verified_user_id'] as int
          : null,
      syncedAt:
          DateTime.tryParse(json['synced_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      verifiedAt: DateTime.tryParse(json['verified_at']?.toString() ?? ''),
      verificationVersion: json['verification_version'] is int
          ? json['verification_version'] as int
          : 0,
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
