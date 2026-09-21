import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/update/release_catalog.dart';
import 'package:mubangumi/core/update/github_release.dart';
import 'package:mubangumi/core/update/update_source.dart';

const repository = 'owner/MuBangumi';
const name = 'MuBangumi-2.3.1-build4029-windows-x64.zip';
Map<String, dynamic> original({String tag = 'v2.3.1+4029', String? digest}) => {
  'tag_name': tag,
  'body': '- Changes',
  'assets': [
    {
      'name': name,
      'size': 123,
      'digest': digest ?? 'sha256:${'a' * 64}',
      'browser_download_url':
          'https://github.com/wweiyi2004/MuBangumi/releases/download/$tag/$name',
    },
  ],
};
Map<String, dynamic> domestic({
  String tag = 'v2.3.1+4029',
  String? digest,
  String? url,
}) {
  final manifest = original(tag: tag, digest: digest)
    ..['schema'] = 1
    ..['repository'] = repository;
  (manifest['assets'] as List).first['mirror_url'] =
      url ?? 'https://gitee.com/$repository/releases/download/$tag/$name';
  return {
    'tag_name': tag,
    'body': '$mirrorManifestStart${jsonEncode(manifest)}$mirrorManifestEnd',
  };
}

Dio api({Map<String, dynamic>? github, Map<String, dynamic>? gitee}) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final value = options.uri.host == 'gitee.com' ? gitee : github;
        if (value == null) {
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.connectionError,
            ),
          );
        } else {
          handler.resolve(
            Response(requestOptions: options, statusCode: 200, data: value),
          );
        }
      },
    ),
  );
  return dio;
}

void main() {
  test(
    'partial mirror preserves Android GitHub fallback and Windows mirror',
    () async {
      final manifest = original()
        ..['schema'] = 1
        ..['repository'] = repository;
      (manifest['assets'] as List).first['mirror_url'] =
          'https://gitee.com/$repository/releases/download/v2.3.1+4029/$name';
      const apkName = 'MuBangumi-2.3.1-build4029-android.apk';
      (manifest['assets'] as List).add({
        'name': apkName,
        'size': 111829288,
        'digest': 'sha256:${'b' * 64}',
        'browser_download_url':
            'https://github.com/wweiyi2004/MuBangumi/releases/download/v2.3.1+4029/$apkName',
      });
      final release = await fetchReleaseCatalog(
        api(
          gitee: {
            'tag_name': 'v2.3.1+4029',
            'body':
                '$mirrorManifestStart${jsonEncode(manifest)}$mirrorManifestEnd',
          },
        ),
        repository: repository,
      );
      expect(
        selectReleaseAsset(release, platform: 'windows')!.trustedMirrorUrl,
        isNotNull,
      );
      final android = selectReleaseAsset(
        release,
        platform: 'android',
        androidAbis: ['arm64-v8a'],
      );
      expect(android, isNotNull);
      expect(android!.trustedDownload, isTrue);
      expect(android.trustedMirrorUrl, isNull);
    },
  );
  test('catalog without any domestic attachment is not a completed mirror', () {
    final manifest = original()
      ..['schema'] = 1
      ..['repository'] = repository;
    expect(
      () => parseMirrorRelease({
        'tag_name': 'v2.3.1+4029',
        'body': '$mirrorManifestStart${jsonEncode(manifest)}$mirrorManifestEnd',
      }, repository),
      throwsFormatException,
    );
  });
  test('domestic metadata works when GitHub is unreachable', () async {
    final release = await fetchReleaseCatalog(
      api(gitee: domestic()),
      repository: repository,
    );
    expect(release.assets.single.trustedMirrorUrl, isNotNull);
    expect(release.assets.single.trustedDownload, isTrue);
  });
  test('missing mirror falls back to GitHub', () async {
    final release = await fetchReleaseCatalog(
      api(github: original()),
      repository: repository,
    );
    expect(release.tagName, 'v2.3.1+4029');
  });
  test('stale mirror does not hide a newer build', () async {
    final release = await fetchReleaseCatalog(
      api(
        github: original(),
        gitee: domestic(tag: 'v2.3.1+4028'),
      ),
      repository: repository,
    );
    expect(release.tagName, 'v2.3.1+4029');
    expect(release.assets.single.trustedMirrorUrl, isNull);
  });
  test('matching checksums attach mirror to original metadata', () async {
    final release = await fetchReleaseCatalog(
      api(github: original(), gitee: domestic()),
      repository: repository,
    );
    expect(release.assets.single.trustedMirrorUrl, isNotNull);
  });
  test('different checksums never permit cross-provider resume', () async {
    final release = await fetchReleaseCatalog(
      api(
        github: original(),
        gitee: domestic(digest: 'sha256:${'b' * 64}'),
      ),
      repository: repository,
    );
    expect(release.assets.single.trustedMirrorUrl, isNull);
  });
  test('rejects wrong repository and untrusted URLs', () {
    expect(
      () => parseMirrorRelease(domestic(), 'other/repo'),
      throwsFormatException,
    );
    expect(
      () => parseMirrorRelease(
        domestic(url: 'https://evil.test/app.apk'),
        repository,
      ),
      throwsFormatException,
    );
    expect(
      trustedGiteeAssetUrl(
        'https://gitee.com/other/repo/releases/download/v1.0/app.apk',
        repository,
      ),
      isFalse,
    );
    expect(validGiteeRepository('../repo'), isFalse);
  });
  test('unpublished mirror manifest is ignored', () {
    expect(
      () => parseMirrorRelease({
        'tag_name': 'v2.3.1+4029',
        'body': 'syncing',
      }, repository),
      throwsFormatException,
    );
    expect(
      () => parseMirrorRelease(domestic()..['prerelease'] = true, repository),
      throwsFormatException,
    );
  });
  test('both sources failing is an error, not up to date', () async {
    await expectLater(
      fetchReleaseCatalog(api(), repository: repository),
      throwsFormatException,
    );
  });
}
