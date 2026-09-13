final _versionPattern = RegExp(
  r'^v?(\d+(?:\.\d+)*)(?:\+.*)?$',
  caseSensitive: false,
);

/// Digits from a GitHub tag or package version (`v1.7.0+8` → `1.7.0`).
String? parseReleaseVersion(String raw) {
  final match = _versionPattern.firstMatch(raw.trim());
  return match?.group(1);
}

int compareAppVersions(String a, String b) {
  final left = _versionParts(a);
  final right = _versionParts(b);
  final length = left.length > right.length ? left.length : right.length;
  for (var i = 0; i < length; i++) {
    final leftPart = i < left.length ? left[i] : 0;
    final rightPart = i < right.length ? right[i] : 0;
    if (leftPart != rightPart) return leftPart.compareTo(rightPart);
  }
  return 0;
}

bool isNewerAppVersion(String current, String latest) =>
    compareAppVersions(current, latest) < 0;

List<int> _versionParts(String raw) {
  final version = parseReleaseVersion(raw) ?? raw.trim();
  return [for (final part in version.split('.')) int.tryParse(part) ?? 0];
}

class GithubRelease {
  const GithubRelease({
    required this.tagName,
    required this.version,
    required this.htmlUrl,
    this.name,
    this.body,
    this.buildNumber,
    this.assets = const [],
  });

  factory GithubRelease.fromJson(Map<String, dynamic> json) {
    final tagName = json['tag_name']?.toString().trim() ?? '';
    final version = parseReleaseVersion(tagName);
    if (version == null ||
        json['draft'] == true ||
        json['prerelease'] == true ||
        !RegExp(
          r'^v?\d+(?:\.\d+)*(?:\+\d+)?$',
          caseSensitive: false,
        ).hasMatch(tagName)) {
      throw FormatException('Invalid GitHub release tag: $tagName');
    }
    return GithubRelease(
      tagName: tagName,
      version: version,
      buildNumber: int.tryParse(tagName.split('+').skip(1).join()),
      assets: [
        for (final item in (json['assets'] as List? ?? const []))
          if (item is Map<String, dynamic>) GithubReleaseAsset.fromJson(item),
      ],
      name: json['name']?.toString(),
      body: json['body']?.toString(),
      htmlUrl: json['html_url']?.toString() ?? '',
    );
  }

  final String tagName;
  final String version;
  final String htmlUrl;
  final String? name;
  final String? body;
  final int? buildNumber;
  final List<GithubReleaseAsset> assets;

  int? get effectiveBuildNumber {
    if (buildNumber != null) return buildNumber;
    final builds = assets
        .map((a) => RegExp(r'-build(\d+)-').firstMatch(a.name)?.group(1))
        .whereType<String>()
        .map(int.parse)
        .toSet();
    return builds.length == 1 ? builds.single : null;
  }
}

bool shouldOfferGithubRelease({
  required String currentVersion,
  required GithubRelease release,
  String? skippedTag,
  String? currentBuild,
}) {
  if (skippedTag != null && skippedTag == release.tagName) return false;
  final comparison = compareAppVersions(currentVersion, release.version);
  if (comparison != 0) return comparison < 0;
  final installed = int.tryParse(currentBuild ?? '');
  final available = release.effectiveBuildNumber;
  return installed != null && available != null && available > installed;
}

String buildGithubReleaseMarkdown({
  required String currentVersion,
  required String currentBuild,
  required GithubRelease release,
}) {
  final buffer = StringBuffer()
    ..writeln('## 发现新版本')
    ..writeln()
    ..writeln('当前版本：**$currentVersion+$currentBuild**')
    ..writeln()
    ..writeln('最新版本：**${release.version}**')
    ..writeln()
    ..writeln('请下载并安装新版本。');

  final notes = release.body?.trim();
  if (notes != null && notes.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('---')
      ..writeln()
      ..writeln('### 更新说明')
      ..writeln()
      ..writeln(notes);
  }
  return buffer.toString();
}

class GithubReleaseAsset {
  const GithubReleaseAsset({
    required this.name,
    required this.url,
    required this.size,
    this.digest,
  });
  factory GithubReleaseAsset.fromJson(Map<String, dynamic> json) =>
      GithubReleaseAsset(
        name: json['name']?.toString() ?? '',
        url: json['browser_download_url']?.toString() ?? '',
        size: json['size'] is num ? (json['size'] as num).toInt() : 0,
        digest: json['digest']?.toString(),
      );
  final String name, url;
  final int size;
  final String? digest;
  String? get sha256Hex {
    final match = RegExp(
      r'^sha256:([a-fA-F0-9]{64})$',
    ).firstMatch(digest ?? '');
    return match?.group(1)?.toLowerCase();
  }

  bool get trustedDownload {
    final uri = Uri.tryParse(url);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host == 'github.com' &&
        uri.port == 443 &&
        uri.userInfo.isEmpty &&
        uri.pathSegments.take(4).join('/') ==
            'wweiyi2004/MuBangumi/releases/download' &&
        uri.pathSegments.length == 6 &&
        uri.pathSegments.last == name &&
        RegExp(r'^[a-zA-Z0-9._+\-]+$').hasMatch(name) &&
        size > 0 &&
        size <= 512 * 1024 * 1024 &&
        sha256Hex != null;
  }
}

GithubReleaseAsset? selectReleaseAsset(
  GithubRelease release, {
  required String platform,
  List<String> androidAbis = const [],
}) {
  final candidates = release.assets
      .where(
        (a) =>
            a.trustedDownload &&
            Uri.parse(a.url).pathSegments[4] == release.tagName &&
            a.name.toLowerCase().startsWith(
              'mubangumi-${release.version.toLowerCase()}-',
            ),
      )
      .toList();
  if (platform == 'windows') {
    for (final a in candidates) {
      if (a.name.toLowerCase().endsWith('-windows-x64.zip')) return a;
    }
  }
  if (platform == 'android') {
    for (final abi in androidAbis) {
      for (final a in candidates) {
        if (a.name.toLowerCase().endsWith('-android-$abi.apk')) return a;
      }
    }
    for (final a in candidates) {
      if (a.name.toLowerCase().endsWith('-android.apk')) return a;
    }
  }
  return null;
}
