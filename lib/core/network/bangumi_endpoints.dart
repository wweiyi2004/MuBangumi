enum BangumiNetworkRoute {
  official(
    '正常线路',
    'api.bgm.tv + lain.bgm.tv',
    'https://api.bgm.tv/v0',
    'lain.bgm.tv',
  ),
  reverseProxy(
    'Bangumi 反代',
    'bgmapi.anibt.net + bgmimg.anibt.net',
    'https://bgmapi.anibt.net/v0',
    'bgmimg.anibt.net',
  );

  const BangumiNetworkRoute(
    this.label,
    this.description,
    this.apiBaseUrl,
    this.imageHost,
  );

  final String label;
  final String description;

  /// OpenAPI v0 base, e.g. `https://api.bgm.tv/v0`.
  final String apiBaseUrl;
  final String imageHost;

  bool get isThirdParty => this == BangumiNetworkRoute.reverseProxy;

  /// API host root without `/v0` (legacy endpoints like `/calendar`).
  String get apiRootUrl {
    final base = apiBaseUrl;
    if (base.endsWith('/v0')) {
      return base.substring(0, base.length - 3);
    }
    if (base.endsWith('/v0/')) {
      return base.substring(0, base.length - 4);
    }
    return base;
  }
}

enum BangumiImageSize {
  grid('g'),
  medium('m'),
  common('c'),
  large('l');

  const BangumiImageSize(this.pathCode);

  final String pathCode;
}

class BangumiEndpoints {
  BangumiEndpoints._();

  static BangumiNetworkRoute _route = BangumiNetworkRoute.official;

  static BangumiNetworkRoute get route => _route;

  static void setRoute(BangumiNetworkRoute route) => _route = route;

  static final _sizePath = RegExp(r'^/(pic/(?:cover|user|crt))/[lmcgs](/.*)$');

  static String imageUrl(String rawUrl, {BangumiImageSize? size}) {
    final value = rawUrl.trim();
    if (value.isEmpty) return '';
    final normalized = value.startsWith('//') ? 'https:$value' : value;
    final uri = Uri.tryParse(normalized);
    if (uri == null) return normalized;
    const officialHost = 'lain.bgm.tv';
    const proxyHost = 'bgmimg.anibt.net';
    final targetHost = _route == BangumiNetworkRoute.reverseProxy
        ? proxyHost
        : officialHost;
    if (uri.host != officialHost && uri.host != proxyHost) return normalized;
    var path = uri.path;
    if (size != null) {
      final match = _sizePath.firstMatch(path);
      if (match != null) {
        path = '${match.group(1)}/${size.pathCode}${match.group(2)}';
      }
    }
    return uri
        .replace(scheme: 'https', host: targetHost, path: path)
        .toString();
  }

  /// Bangumi stores avatars at `/pic/user/{size}/{aaa}/{bb}/{cc}/{uid}.jpg`.
  static String userAvatarUrl(
    int userId, {
    BangumiImageSize size = BangumiImageSize.large,
  }) {
    if (userId <= 0) return '';
    final padded = userId.toString().padLeft(9, '0');
    return imageUrl(
      'https://lain.bgm.tv/pic/user/l/'
      '${padded.substring(0, 3)}/${padded.substring(3, 5)}/'
      '${padded.substring(5, 7)}/$userId.jpg',
      size: size,
    );
  }
}
