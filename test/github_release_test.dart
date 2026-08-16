import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/update/github_release.dart';
import 'package:mubangumi/core/update/github_release_store.dart';
import 'package:mubangumi/widgets/github_release_dialog.dart';

void main() {
  group('parseReleaseVersion', () {
    test('strips a leading v and ignores a build suffix', () {
      expect(parseReleaseVersion('v1.7.0'), '1.7.0');
      expect(parseReleaseVersion('V1.7.0+8'), '1.7.0');
      expect(parseReleaseVersion('1.6.0'), '1.6.0');
    });

    test('returns null for empty or non-version tags', () {
      expect(parseReleaseVersion(''), isNull);
      expect(parseReleaseVersion('latest'), isNull);
    });
  });

  group('compareAppVersions', () {
    test('orders dotted versions numerically', () {
      expect(compareAppVersions('1.6.0', '1.7.0'), lessThan(0));
      expect(compareAppVersions('1.7.0', '1.7.0'), 0);
      expect(compareAppVersions('1.10.0', '1.9.0'), greaterThan(0));
      expect(compareAppVersions('1.7', '1.7.0'), 0);
    });
  });

  test('isNewerAppVersion treats the v prefix as the same version', () {
    expect(isNewerAppVersion('1.6.0', 'v1.7.0'), isTrue);
    expect(isNewerAppVersion('1.7.0', 'v1.7.0'), isFalse);
    expect(isNewerAppVersion('1.7.0', 'v1.6.0'), isFalse);
  });

  test('GithubRelease.fromJson reads tag, notes and html url', () {
    final release = GithubRelease.fromJson({
      'tag_name': 'v1.7.0',
      'name': 'MuBangumi v1.7.0',
      'body': '## 本次亮点\n\n- 共同好友',
      'html_url': 'https://github.com/wweiyi2004/MuBangumi/releases/tag/v1.7.0',
    });

    expect(release.tagName, 'v1.7.0');
    expect(release.version, '1.7.0');
    expect(release.name, 'MuBangumi v1.7.0');
    expect(release.body, contains('共同好友'));
    expect(
      release.htmlUrl,
      'https://github.com/wweiyi2004/MuBangumi/releases/tag/v1.7.0',
    );
  });

  test('GithubReleaseSkipStore persists the skipped tag in memory', () async {
    final store = GithubReleaseSkipStore(memory: {});
    expect(await store.readSkippedTag(), isNull);
    await store.skipTag('v1.7.0');
    expect(await store.readSkippedTag(), 'v1.7.0');
  });

  test('shouldOfferGithubRelease hides a skipped tag until a newer one', () {
    final release = GithubRelease.fromJson({
      'tag_name': 'v1.7.0',
      'html_url': 'https://github.com/wweiyi2004/MuBangumi/releases/tag/v1.7.0',
      'body': 'notes',
    });

    expect(
      shouldOfferGithubRelease(
        currentVersion: '1.6.0',
        release: release,
        skippedTag: null,
      ),
      isTrue,
    );
    expect(
      shouldOfferGithubRelease(
        currentVersion: '1.6.0',
        release: release,
        skippedTag: 'v1.7.0',
      ),
      isFalse,
    );
    expect(
      shouldOfferGithubRelease(
        currentVersion: '1.7.0',
        release: release,
        skippedTag: null,
      ),
      isFalse,
    );
  });

  test('buildGithubReleaseMarkdown includes version and notes', () {
    final markdown = buildGithubReleaseMarkdown(
      currentVersion: '1.6.0',
      currentBuild: '7',
      release: GithubRelease.fromJson({
        'tag_name': 'v1.7.0',
        'html_url': 'https://example.com/r',
        'body': '## 修复\n\n- **登录**',
      }),
    );

    expect(markdown, contains('## 发现新版本'));
    expect(markdown, contains('**1.6.0+7**'));
    expect(markdown, contains('**1.7.0**'));
    expect(markdown, contains('### 更新说明'));
    expect(markdown, contains('## 修复'));
    expect(markdown, contains('**登录**'));
  });

  testWidgets('GithubReleaseDialog renders notes and skip action', (
    tester,
  ) async {
    final release = GithubRelease.fromJson({
      'tag_name': 'v1.7.0',
      'html_url': 'https://github.com/wweiyi2004/MuBangumi/releases/tag/v1.7.0',
      'body': '- 共同好友\n- **线路测速**',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GithubReleaseDialog(
            markdown: buildGithubReleaseMarkdown(
              currentVersion: '1.6.0',
              currentBuild: '7',
              release: release,
            ),
          ),
        ),
      ),
    );

    expect(find.text('发现新版本'), findsWidgets);
    expect(find.text('跳过此版本'), findsOneWidget);
    expect(find.text('稍后'), findsOneWidget);
    expect(find.text('前往下载'), findsOneWidget);
    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(find.textContaining('共同好友'), findsWidgets);
    expect(find.textContaining('线路测速'), findsWidgets);
  });
}
