import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../auth/bangumi_oauth.dart';
import '../network/bangumi_endpoints.dart';

class TokenStore {
  static const _sessionKey = 'bangumi_credentials_v2';
  static const _accessKey = 'bangumi_access_token';
  static const _refreshKey = 'bangumi_refresh_token';
  static const _expiresKey = 'bangumi_token_expires_at';
  static const _clientIdKey = 'bangumi_oauth_client_id';
  static const _clientSecretKey = 'bangumi_oauth_client_secret';
  static const _networkRouteKey = 'bangumi_network_route';
  static const _storage = FlutterSecureStorage();

  Future<Map<String, dynamic>?> _readSession() async {
    final raw = await _storage.read(key: _sessionKey);
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid saved login');
    }
    return decoded;
  }

  Future<String?> read() async {
    final session = await _readSession();
    return session == null
        ? _storage.read(key: _accessKey)
        : session['access_token'] as String?;
  }

  Future<void> write(String token) async {
    OAuthConfig? config;
    try {
      config = await readOAuthConfig();
    } catch (_) {
      // A verified personal token can replace a damaged saved login record.
    }
    await _writeSession(token: token, config: config);
  }

  Future<String?> readRefreshToken() async {
    final session = await _readSession();
    return session == null
        ? _storage.read(key: _refreshKey)
        : session['refresh_token'] as String?;
  }

  Future<DateTime?> readExpiresAt() async {
    final session = await _readSession();
    final value = session == null
        ? await _storage.read(key: _expiresKey)
        : session['expires_at'] as String?;
    return value == null ? null : DateTime.tryParse(value);
  }

  Future<void> writeTokens(OAuthTokenBundle tokens) async {
    await _writeSession(
      token: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      expiresAt: tokens.expiresAt,
      config: await readOAuthConfig(),
    );
  }

  /// Commit the token pair and its OAuth app together, never as partial keys.
  Future<void> writeOAuthSession(OAuthConfig config, OAuthTokenBundle tokens) =>
      _writeSession(
        token: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        expiresAt: tokens.expiresAt,
        config: config,
      );

  Future<void> _writeSession({
    String? token,
    String? refreshToken,
    DateTime? expiresAt,
    OAuthConfig? config,
  }) async {
    await _storage.write(
      key: _sessionKey,
      value: jsonEncode({
        'access_token': token,
        'refresh_token': refreshToken?.isNotEmpty == true ? refreshToken : null,
        'expires_at': expiresAt?.toIso8601String(),
        'client_id': config?.clientId.trim(),
        'client_secret': config?.clientSecret.trim(),
      }),
    );
  }

  Future<OAuthConfig?> readOAuthConfig() async {
    final session = await _readSession();
    if (session != null) {
      final id = session['client_id'] as String?;
      final secret = session['client_secret'] as String?;
      return id == null || secret == null
          ? null
          : OAuthConfig(clientId: id, clientSecret: secret);
    }
    final values = await Future.wait([
      _storage.read(key: _clientIdKey),
      _storage.read(key: _clientSecretKey),
    ]);
    final clientId = values[0];
    final clientSecret = values[1];
    if (clientId == null || clientSecret == null) return null;
    return OAuthConfig(clientId: clientId, clientSecret: clientSecret);
  }

  Future<BangumiNetworkRoute> readNetworkRoute() async {
    final value = await _storage.read(key: _networkRouteKey);
    return BangumiNetworkRoute.values.firstWhere(
      (route) => route.name == value,
      orElse: () => BangumiNetworkRoute.official,
    );
  }

  Future<void> writeNetworkRoute(BangumiNetworkRoute route) =>
      _storage.write(key: _networkRouteKey, value: route.name);

  Future<void> clear() async {
    OAuthConfig? config;
    try {
      config = await readOAuthConfig();
    } catch (_) {}
    // Keep an authoritative signed-out record: legacy keys must never restore
    // an account if deleting one of those old keys fails or the app exits.
    await _writeSession(config: config);
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
    await _storage.delete(key: _expiresKey);
  }
}
