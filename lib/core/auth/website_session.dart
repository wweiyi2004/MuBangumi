import 'dart:convert';

import 'package:crypto/crypto.dart';
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
    this.userAgent,
  });

  final List<WebsiteCookie> cookies;
  final DateTime syncedAt;

  /// Identity established by the same embedded OAuth flow or website chrome.
  /// Cookie capture alone must never assign this field.
  final int? verifiedUserId;
  final DateTime? verifiedAt;
  final int verificationVersion;

  /// Browser identity used when these website cookies were captured.
  final String? userAgent;

  Map<String, String> get requestHeaders => {
    'Cookie': cookieHeader,
    if (userAgent != null &&
        userAgent!.isNotEmpty &&
        userAgent!.length <= 1024 &&
        !RegExp(r'[\x00-\x1f\x7f]').hasMatch(userAgent!))
      'User-Agent': userAgent!,
  };

  bool isVerifiedFor(int userId, DateTime now) =>
      hasSessionCookies &&
      verificationVersion == 2 &&
      verifiedUserId == userId &&
      verifiedAt != null &&
      !verifiedAt!.isAfter(now) &&
      // The account binding belongs to these authentication cookies, not a
      // ten-minute timer. Website responses revoke it when login really fails.
      _authenticationKeyAt(now).isNotEmpty &&
      _authenticationKeyAt(verifiedAt!) == _authenticationKeyAt(now);

  WebsiteSessionSnapshot withVerifiedUser(int userId, {DateTime? at}) =>
      WebsiteSessionSnapshot(
        cookies: cookies,
        syncedAt: syncedAt,
        verifiedUserId: userId,
        verifiedAt: at ?? DateTime.now(),
        verificationVersion: 2,
        userAgent: userAgent,
      );

  WebsiteSessionSnapshot withoutVerification() => WebsiteSessionSnapshot(
    cookies: cookies,
    syncedAt: syncedAt,
    userAgent: userAgent,
  );

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
  String get authenticationKey => _authenticationKeyAt(DateTime.now());

  /// A rejection only belongs to this captured and verified request context.
  /// Re-verifying the same login or refreshing browser/challenge cookies must
  /// not let an earlier HTTP response revoke the new binding.
  String get requestKey =>
      sha256.convert(utf8.encode(jsonEncode(toJson()))).toString();

  String _authenticationKeyAt(DateTime at) {
    final active = cookies
        .where(
          (cookie) =>
              (cookie.expiresAt == null || cookie.expiresAt!.isAfter(at)) &&
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
    if (userAgent != null) 'user_agent': userAgent,
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
      userAgent: json['user_agent'] is String
          ? json['user_agent'] as String
          : null,
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
