import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../auth/bangumi_oauth.dart';
import '../network/bangumi_endpoints.dart';

class TokenStore {
  static const _accessKey = 'bangumi_access_token';
  static const _refreshKey = 'bangumi_refresh_token';
  static const _expiresKey = 'bangumi_token_expires_at';
  static const _clientIdKey = 'bangumi_oauth_client_id';
  static const _clientSecretKey = 'bangumi_oauth_client_secret';
  static const _networkRouteKey = 'bangumi_network_route';
  static const _storage = FlutterSecureStorage();

  Future<String?> read() => _storage.read(key: _accessKey);

  Future<void> write(String token) async {
    await _storage.write(key: _accessKey, value: token);
    await _storage.delete(key: _refreshKey);
    await _storage.delete(key: _expiresKey);
  }

  Future<String?> readRefreshToken() => _storage.read(key: _refreshKey);

  Future<DateTime?> readExpiresAt() async {
    final value = await _storage.read(key: _expiresKey);
    return value == null ? null : DateTime.tryParse(value);
  }

  Future<void> writeTokens(OAuthTokenBundle tokens) async {
    await _storage.write(key: _accessKey, value: tokens.accessToken);
    if (tokens.refreshToken.isNotEmpty) {
      await _storage.write(key: _refreshKey, value: tokens.refreshToken);
    }
    await _storage.write(
      key: _expiresKey,
      value: tokens.expiresAt.toIso8601String(),
    );
  }

  Future<OAuthConfig?> readOAuthConfig() async {
    final values = await Future.wait([
      _storage.read(key: _clientIdKey),
      _storage.read(key: _clientSecretKey),
    ]);
    final clientId = values[0];
    final clientSecret = values[1];
    if (clientId == null || clientSecret == null) return null;
    return OAuthConfig(clientId: clientId, clientSecret: clientSecret);
  }

  Future<void> writeOAuthConfig(OAuthConfig config) async {
    await _storage.write(key: _clientIdKey, value: config.clientId.trim());
    await _storage.write(
      key: _clientSecretKey,
      value: config.clientSecret.trim(),
    );
  }

  Future<void> clearOAuthConfig() async {
    await _storage.delete(key: _clientIdKey);
    await _storage.delete(key: _clientSecretKey);
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
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
    await _storage.delete(key: _expiresKey);
  }
}
