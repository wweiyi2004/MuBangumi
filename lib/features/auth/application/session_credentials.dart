import '../../../core/auth/bangumi_oauth.dart';
import '../../../core/network/bangumi_api.dart';
import '../../../core/network/bangumi_endpoints.dart';
import '../../../core/storage/token_store.dart';

/// Credential I/O and refresh policy. The session owns account generations;
/// this service never publishes UI state or decides which account to display.
class SessionCredentials {
  SessionCredentials({
    required this._oauth,
    required this._store,
    required this.currentGeneration,
    required this.isCurrent,
    required this.canRefresh,
    required this.onAccessTokenChanged,
    required this.onRefreshError,
  });

  final BangumiOAuth _oauth;
  final TokenStore _store;
  final int Function() currentGeneration;
  final bool Function(int generation) isCurrent;
  final bool Function() canRefresh;
  final void Function(String? token) onAccessTokenChanged;
  final Future<void> Function(Object error) onRefreshError;

  Future<void> _writes = Future<void>.value();
  Future<bool>? _refreshInFlight;
  String? _refreshToken;
  DateTime? _expiresAt;
  OAuthConfig? _config;
  String? _accessToken;
  bool _hasStoredCredentials = false;

  String? get accessToken => _accessToken;
  bool get hasStoredCredentials => _hasStoredCredentials;

  void setAccessToken(String? token) {
    _accessToken = token;
    onAccessTokenChanged(token);
  }

  /// Invalidate refresh memory without erasing the serialized write barrier.
  /// Logout must still wait for an already-running credential write.
  void reset({bool forgetStoredCredentials = false}) {
    _refreshInFlight = null;
    _refreshToken = null;
    _expiresAt = null;
    _config = null;
    if (forgetStoredCredentials) _hasStoredCredentials = false;
  }

  Future<StoredLogin?> readStored(int generation) async {
    final values = await Future.wait<Object?>([
      _store.readNetworkRoute(),
      _store.read(),
      _store.readRefreshToken(),
      _store.readExpiresAt(),
      _store.readOAuthConfig(),
    ]);
    if (!isCurrent(generation)) return null;
    final token = values[1] as String?;
    _refreshToken = values[2] as String?;
    _expiresAt = values[3] as DateTime?;
    _config = values[4] as OAuthConfig?;
    _hasStoredCredentials =
        token?.isNotEmpty == true || _refreshToken?.isNotEmpty == true;
    return StoredLogin(
      route: values[0]! as BangumiNetworkRoute,
      accessToken: token,
      shouldRefresh:
          _refreshToken?.isNotEmpty == true &&
          _config?.isValid == true &&
          (token == null ||
              _expiresAt == null ||
              _expiresAt!.isBefore(
                DateTime.now().add(const Duration(minutes: 5)),
              )),
    );
  }

  /// Shared by credential writes, verified-identity binding and logout cleanup.
  /// Stale queued writes are skipped; in-progress writes finish before cleanup.
  Future<bool> writeCurrent(int generation, Future<void> Function() write) {
    final future = _writes.then((_) async {
      if (!isCurrent(generation)) return false;
      await write();
      return isCurrent(generation);
    });
    _writes = future.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return future;
  }

  Future<bool> persistAccessToken(String token, int generation) async {
    if (!await writeCurrent(generation, () => _store.write(token))) {
      return false;
    }
    _hasStoredCredentials = true;
    return true;
  }

  Future<bool> persistTokens(
    OAuthTokenBundle tokens,
    int generation, {
    OAuthConfig? config,
  }) async {
    if (!await writeCurrent(generation, () async {
      if (config != null) {
        await _store.writeOAuthSession(config, tokens);
      } else {
        await _store.writeTokens(tokens);
      }
    })) {
      return false;
    }
    _config = config ?? _config;
    _refreshToken = tokens.refreshToken.isEmpty ? null : tokens.refreshToken;
    _expiresAt = tokens.expiresAt;
    _hasStoredCredentials = true;
    setAccessToken(tokens.accessToken);
    return true;
  }

  /// Bootstrap needs the error itself to distinguish offline restoration from
  /// revoked credentials. Normal API refreshes use [tryRefreshAccessToken].
  Future<String?> refreshAndPersist(int generation) async {
    final refreshToken = _refreshToken;
    final config = _config;
    if (!isCurrent(generation) || refreshToken == null || config == null) {
      return null;
    }
    final tokens = await _oauth.refresh(config, refreshToken);
    if (!await persistTokens(tokens, generation)) return null;
    return tokens.accessToken;
  }

  Future<void> ensureFreshToken() async {
    if (!canRefresh()) return;
    final expiresAt = _expiresAt;
    if (expiresAt != null &&
        expiresAt.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
      return;
    }
    await tryRefreshAccessToken();
  }

  Future<bool> tryRefreshAccessToken() {
    if (!canRefresh() || _refreshToken?.isNotEmpty != true || _config == null) {
      return Future.value(false);
    }
    final active = _refreshInFlight;
    if (active != null) return active;
    final future = _refresh(currentGeneration());
    _refreshInFlight = future;
    return future.whenComplete(() {
      if (identical(_refreshInFlight, future)) _refreshInFlight = null;
    });
  }

  Future<bool> _refresh(int generation) async {
    try {
      return await refreshAndPersist(generation) != null;
    } catch (error) {
      if (isCurrent(generation)) await onRefreshError(error);
      return false;
    }
  }

  bool invalidatesSession(Object error) =>
      (error is BangumiOAuthException && error.invalidatesSession) ||
      (error is BangumiApiException &&
          error.statusCode == 401 &&
          !error.retryable &&
          (_refreshToken == null || _refreshToken!.isEmpty));
}

class StoredLogin {
  const StoredLogin({
    required this.route,
    required this.accessToken,
    required this.shouldRefresh,
  });

  final BangumiNetworkRoute route;
  final String? accessToken;
  final bool shouldRefresh;
}
