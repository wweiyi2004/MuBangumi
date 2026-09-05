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
  });

  factory GithubRelease.fromJson(Map<String, dynamic> json) {
    final tagName = json['tag_name']?.toString().trim() ?? '';
    final version = parseReleaseVersion(tagName);
    if (version == null) {
      throw FormatException('Invalid GitHub release tag: $tagName');
    }
    return GithubRelease(
      tagName: tagName,
      version: version,
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
}

bool shouldOfferGithubRelease({
  required String currentVersion,
  required GithubRelease release,
  String? skippedTag,
}) {
  if (skippedTag != null && skippedTag == release.tagName) return false;
  return isNewerAppVersion(currentVersion, release.version);
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
