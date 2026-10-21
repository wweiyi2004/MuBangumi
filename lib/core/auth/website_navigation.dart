bool isBangumiWebsiteNavigation(Uri uri) {
  if (uri.scheme != 'https' || uri.port != 443 || uri.userInfo.isNotEmpty) {
    return false;
  }
  final host = uri.host.toLowerCase();
  return const [
    'bgm.tv',
    'bangumi.tv',
    'chii.in',
  ].any((domain) => host == domain || host.endsWith('.$domain'));
}

bool isTurnstileNavigation(Uri uri) =>
    isBangumiWebsiteNavigation(uri) ||
    (uri.scheme == 'https' &&
        uri.host == 'challenges.cloudflare.com' &&
        uri.port == 443 &&
        uri.userInfo.isEmpty) ||
    (uri.scheme == 'about' && const ['blank', 'srcdoc'].contains(uri.path));
