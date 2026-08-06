import 'bangumi_oauth.dart';

/// Built-in OAuth application for one-tap login (release-style UX).
///
/// Provide credentials at build time (recommended for CI / local release):
/// ```
/// flutter run --dart-define=BGM_CLIENT_ID=xxx --dart-define=BGM_CLIENT_SECRET=yyy
/// ```
///
/// Or edit the fallback constants below for private builds only.
/// Do **not** commit real secrets to a public repository.
///
/// Redirect URI must remain: [OAuthConfig.redirectUri]
class OAuthBuiltin {
  OAuthBuiltin._();

  static const clientId = String.fromEnvironment(
    'BGM_CLIENT_ID',
    defaultValue: _fallbackClientId,
  );

  static const clientSecret = String.fromEnvironment(
    'BGM_CLIENT_SECRET',
    defaultValue: _fallbackClientSecret,
  );

  /// Private-build fallbacks (leave empty in public source).
  static const _fallbackClientId = '';
  static const _fallbackClientSecret = '';

  static bool get isConfigured =>
      clientId.trim().isNotEmpty && clientSecret.trim().isNotEmpty;

  static OAuthConfig? get config {
    if (!isConfigured) return null;
    return OAuthConfig(clientId: clientId, clientSecret: clientSecret);
  }
}
