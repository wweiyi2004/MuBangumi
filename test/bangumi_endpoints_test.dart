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
    // Legacy calendar lives outside /v0.
    expect(BangumiNetworkRoute.official.apiRootUrl, 'https://api.bgm.tv');
    expect(
      BangumiNetworkRoute.reverseProxy.apiRootUrl,
      'https://bgmapi.anibt.net',
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

  test('rewrites cover path to the requested size and keeps the query', () {
    const large = 'https://lain.bgm.tv/pic/cover/l/c4/ca/1_d2tF2.jpg?demo=1';
    expect(
      BangumiEndpoints.imageUrl(large, size: BangumiImageSize.common),
      'https://lain.bgm.tv/pic/cover/c/c4/ca/1_d2tF2.jpg?demo=1',
    );
    expect(
      BangumiEndpoints.imageUrl(large, size: BangumiImageSize.medium),
      'https://lain.bgm.tv/pic/cover/m/c4/ca/1_d2tF2.jpg?demo=1',
    );
    expect(
      BangumiEndpoints.imageUrl(large, size: BangumiImageSize.grid),
      'https://lain.bgm.tv/pic/cover/g/c4/ca/1_d2tF2.jpg?demo=1',
    );
  });

  test('rewrites cover size on the reverse-proxy host', () {
    const large = 'https://lain.bgm.tv/pic/cover/l/c4/ca/1_d2tF2.jpg';
    BangumiEndpoints.setRoute(BangumiNetworkRoute.reverseProxy);
    expect(
      BangumiEndpoints.imageUrl(large, size: BangumiImageSize.common),
      'https://bgmimg.anibt.net/pic/cover/c/c4/ca/1_d2tF2.jpg',
    );
  });

  test('rewrites user avatar path to the requested size', () {
    const large = 'https://lain.bgm.tv/pic/user/l/000/00/00/1.jpg';
    expect(
      BangumiEndpoints.imageUrl(large, size: BangumiImageSize.medium),
      'https://lain.bgm.tv/pic/user/m/000/00/00/1.jpg',
    );
  });

  test('does not rewrite size on unrelated image hosts', () {
    const url = 'https://example.com/pic/cover/l/a.png';
    expect(
      BangumiEndpoints.imageUrl(url, size: BangumiImageSize.common),
      url,
    );
  });
}
