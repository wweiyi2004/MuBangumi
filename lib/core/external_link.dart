import 'package:url_launcher/url_launcher.dart';

/// Opens a content-controlled [uri] in the system browser.
///
/// Item links, RSS entries and release-note Markdown come from third-party
/// data, so only http/https URLs are ever dispatched; arbitrary schemes
/// (intent://, file://, custom protocols) are dropped instead of handed to
/// whatever external app registered them.
Future<bool> launchExternalLink(Uri? uri) async {
  if (uri == null) return false;
  if (!uri.isScheme('http') && !uri.isScheme('https')) return false;
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
