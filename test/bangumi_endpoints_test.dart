import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/bangumi_endpoints.dart';

void main() {
  tearDown(() => BangumiEndpoints.setRoute(BangumiNetworkRoute.official));

  test('switches API base URL between official and reverse proxy', () {
    expect(BangumiNetworkRoute.official.apiBaseUrl, 'https://api.bgm.tv/v0');
    expect(
      BangumiNetworkRoute.reverseProxy.apiBaseUrl,
      'https://bgmapi.anibt.net/v0',
    );
  });

  test('rewrites Bangumi image URLs in both directions', () {
    const official = 'https://lain.bgm.tv/pic/cover/l/c4/ca/1_d2tF2.jpg?demo=1';
    const proxy =
        'https://bgmimg.anibt.net/pic/cover/l/c4/ca/1_d2tF2.jpg?demo=1';

    BangumiEndpoints.setRoute(BangumiNetworkRoute.reverseProxy);
    expect(BangumiEndpoints.imageUrl(official), proxy);

    BangumiEndpoints.setRoute(BangumiNetworkRoute.official);
    expect(BangumiEndpoints.imageUrl(proxy), official);
  });

  test('does not rewrite unrelated image hosts', () {
    const url = 'https://example.com/avatar.png';
    BangumiEndpoints.setRoute(BangumiNetworkRoute.reverseProxy);
    expect(BangumiEndpoints.imageUrl(url), url);
  });
}
