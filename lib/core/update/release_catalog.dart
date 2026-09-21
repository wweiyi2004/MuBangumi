import 'dart:convert';

import 'package:dio/dio.dart';

import 'github_release.dart';
import 'update_source.dart';

const githubLatestReleaseUrl =
    'https://api.github.com/repos/wweiyi2004/MuBangumi/releases/latest';
const mirrorManifestStart = '<!-- mubangumi-update-v1\n';
const mirrorManifestEnd = '\n-->';

/// The mirror publishes the original GitHub metadata and verified attachment
/// URLs in its release body. No GitHub request is required to use that mirror.
GithubRelease parseMirrorRelease(Map<String, dynamic> data, String repository) {
  final body = data['body'] as String? ?? '';
  final start = body.lastIndexOf(mirrorManifestStart);
  if (start < 0) throw const FormatException('missing mirror manifest');
  final offset = start + mirrorManifestStart.length;
  final end = body.indexOf(mirrorManifestEnd, offset);
  if (end < 0) throw const FormatException('incomplete mirror manifest');
  final manifest =
      jsonDecode(body.substring(offset, end)) as Map<String, dynamic>;
  if (manifest['schema'] != 1 ||
      manifest['repository'] != repository ||
      manifest['tag_name'] != data['tag_name'] ||
      data['prerelease'] == true ||
      data['draft'] == true) {
    throw const FormatException('invalid mirror manifest');
  }
  final release = GithubRelease.fromJson(manifest);
  final assets = [
    for (final a in release.assets)
      GithubReleaseAsset(
        name: a.name,
        url: a.url,
        size: a.size,
        digest: a.digest,
        mirrorUrl: a.mirrorUrl,
        mirrorRepository: repository,
      ),
  ];
  if (assets.isEmpty ||
      !assets.any((a) => a.trustedMirrorUrl != null) ||
      assets.any(
        (a) =>
            !a.trustedDownload ||
            (a.mirrorUrl != null && a.trustedMirrorUrl == null) ||
            Uri.parse(a.url).pathSegments[4] != release.tagName,
      )) {
    throw const FormatException('invalid mirror assets');
  }
  return GithubRelease(
    tagName: release.tagName,
    version: release.version,
    buildNumber: release.buildNumber,
    name: release.name,
    body: release.body,
    htmlUrl:
        'https://gitee.com/$repository/releases/tag/${Uri.encodeComponent(release.tagName)}',
    assets: assets,
  );
}

Future<GithubRelease> fetchReleaseCatalog(
  Dio dio, {
  String repository = giteeRepository,
  UpdateSource source = UpdateSource.auto,
}) async {
  Future<GithubRelease?> github() async {
    final token = CancelToken();
    try {
      final response = await dio
          .get<Map<String, dynamic>>(githubLatestReleaseUrl, cancelToken: token)
          .timeout(const Duration(seconds: 10));
      return GithubRelease.fromJson(response.data!);
    } catch (_) {
      return null;
    } finally {
      token.cancel();
    }
  }

  Future<GithubRelease?> domestic() async {
    final token = CancelToken();
    try {
      final response = await dio
          .get<Map<String, dynamic>>(
            'https://gitee.com/api/v5/repos/$repository/releases/latest',
            cancelToken: token,
            options: Options(
              headers: {'Accept': 'application/json'},
              sendTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
            ),
          )
          .timeout(const Duration(seconds: 10));
      return parseMirrorRelease(response.data!, repository);
    } catch (_) {
      return null;
    } finally {
      token.cancel();
    }
  }

  if (source == UpdateSource.github || !validGiteeRepository(repository)) {
    final result = await github();
    if (result != null) return result;
  } else if (source == UpdateSource.domestic) {
    final result = await domestic();
    if (result != null) return result;
  } else {
    // Compare both catalogs so an out-of-date mirror cannot hide a new version.
    final results = await Future.wait([domestic(), github()]);
    final mirror = results[0], original = results[1];
    if (mirror == null && original != null) return original;
    if (mirror != null && original == null) return mirror;
    if (mirror != null && original != null) {
      final comparison = compareAppVersions(mirror.version, original.version);
      if (comparison > 0 ||
          (comparison == 0 &&
              (mirror.effectiveBuildNumber ?? 0) >
                  (original.effectiveBuildNumber ?? 0))) {
        return mirror;
      }
      if (mirror.tagName != original.tagName) return original;
      // Preserve GitHub's checksum, only attaching byte-identical mirrors.
      return GithubRelease(
        tagName: original.tagName,
        version: original.version,
        buildNumber: original.buildNumber,
        name: original.name,
        body: original.body,
        htmlUrl: original.htmlUrl,
        assets: [
          for (final a in original.assets)
            GithubReleaseAsset(
              name: a.name,
              url: a.url,
              size: a.size,
              digest: a.digest,
              mirrorRepository: repository,
              mirrorUrl: mirror.assets
                  .where(
                    (m) =>
                        m.name == a.name &&
                        m.size == a.size &&
                        m.sha256Hex == a.sha256Hex,
                  )
                  .firstOrNull
                  ?.trustedMirrorUrl,
            ),
        ],
      );
    }
  }
  throw const FormatException('release catalog unavailable');
}
