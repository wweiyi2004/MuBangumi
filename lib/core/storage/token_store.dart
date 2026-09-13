import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../models/bangumi_models.dart';
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
    final previousToken = await read();
    await _writeSession(
      token: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      expiresAt: tokens.expiresAt,
      config: await readOAuthConfig(),
      verifiedUser: previousToken == null
          ? null
          : await readVerifiedUser(previousToken),
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
    BangumiUser? verifiedUser,
  }) async {
    await _storage.write(
      key: _sessionKey,
      value: jsonEncode({
        'access_token': token,
        'refresh_token': refreshToken?.isNotEmpty == true ? refreshToken : null,
        'expires_at': expiresAt?.toIso8601String(),
        'client_id': config?.clientId.trim(),
        'client_secret': config?.clientSecret.trim(),
        if (verifiedUser != null) 'verified_user': verifiedUser.toJson(),
      }),
    );
  }

  /// Only identity stored alongside this exact credential may restore an
  /// offline account. SQLite's legacy session_last_user is not authentication.
  Future<BangumiUser?> readVerifiedUser(String token) async {
    final session = await _readSession();
    if (token.isEmpty || session?['access_token'] != token) return null;
    final raw = session?['verified_user'];
    if (raw is! Map) return null;
    try {
      final user = BangumiUser.fromJson(Map<String, dynamic>.from(raw));
      return user.id > 0 && user.username.trim().isNotEmpty ? user : null;
    } catch (_) {
      return null;
    }
  }

  /// Called only after /me succeeds, serialized with refresh/login/logout by
  /// SessionController. A refresh can rotate the token during /me; the current
  /// credential still belongs to the verified account within that generation.
  Future<void> bindVerifiedUser(String expectedToken, BangumiUser user) async {
    if (user.id <= 0 || user.username.trim().isEmpty) {
      throw const FormatException('Invalid verified account');
    }
    final session = await _readSession();
    final token = session == null ? await read() : session['access_token'];
    if (expectedToken.isEmpty || token != expectedToken) {
      throw StateError('Saved credentials changed before identity binding');
    }
    if (session != null) {
      await _storage.write(
        key: _sessionKey,
        value: jsonEncode({...session, 'verified_user': user.toJson()}),
      );
      return;
    }
    await _writeSession(
      token: expectedToken,
      refreshToken: await readRefreshToken(),
      expiresAt: await readExpiresAt(),
      config: await readOAuthConfig(),
      verifiedUser: user,
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
