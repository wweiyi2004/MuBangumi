import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/update/app_update_service.dart';
import 'package:mubangumi/state/update_controller.dart';
import 'package:mubangumi/widgets/update_ready_dialog.dart';

void main() {
  group('buildUpdateReadyMarkdown', () {
    test('includes version, patch and release notes sections', () {
      final markdown = buildUpdateReadyMarkdown(
        appVersion: '1.2.0',
        buildNumber: '3',
        nextPatch: 2,
        releaseNotesMarkdown: '## 修复\n\n- 登录崩溃\n- **进度同步**',
      );

      expect(markdown, contains('## 热更新已就绪'));
      expect(markdown, contains('**1.2.0+3**'));
      expect(markdown, contains('**Patch #2**'));
      expect(markdown, contains('### 更新说明'));
      expect(markdown, contains('## 修复'));
      expect(markdown, contains('- 登录崩溃'));
      expect(markdown, contains('**进度同步**'));
    });

    test('omits release notes section when notes are empty', () {
      final markdown = buildUpdateReadyMarkdown(
        appVersion: '1.2.0',
        buildNumber: '3',
        nextPatch: 1,
        releaseNotesMarkdown: '   ',
      );

      expect(markdown, isNot(contains('### 更新说明')));
    });
  });

  test('iOS uses App Store full releases and never exits itself', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    expect(supportsGithubReleaseDownloads, isFalse);
    expect(supportsProgrammaticUpdateExit, isFalse);
  });

  testWidgets('UpdateReadyDialog renders Markdown headings and emphasis', (
    tester,
  ) async {
    const markdown = '''
## 热更新已就绪

当前版本：**1.2.0+3**

即将应用：**Patch #2**

### 更新说明

- 修复登录
- **重要**改进
''';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: UpdateReadyDialog(markdown: markdown)),
      ),
    );

    expect(find.text('发现热更新'), findsOneWidget);
    expect(find.text('退出并生效'), findsOneWidget);
    expect(find.text('稍后'), findsOneWidget);
    expect(find.byType(MarkdownBody), findsOneWidget);

    // Headings and strong text should be present in the rich text tree.
    expect(find.textContaining('热更新已就绪'), findsWidgets);
    expect(find.textContaining('1.2.0+3'), findsWidgets);
    expect(find.textContaining('Patch #2'), findsWidgets);
    expect(find.textContaining('修复登录'), findsWidgets);
    expect(find.textContaining('重要'), findsWidgets);
  });

  testWidgets('iOS update dialog asks for a manual restart', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: UpdateReadyDialog(
            markdown: '## 热更新已就绪',
            allowImmediateExit: false,
          ),
        ),
      ),
    );

    expect(find.text('退出并生效'), findsNothing);
    expect(find.text('知道了，稍后手动重启'), findsOneWidget);
  });

  test('fetchLatestGithubRelease parses the published release', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          expect(options.path, contains('/releases/latest'));
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'tag_name': 'v1.7.0',
                'name': 'MuBangumi v1.7.0',
                'body': '## 亮点\n\n- 共同好友',
                'html_url':
                    'https://github.com/wweiyi2004/MuBangumi/releases/tag/v1.7.0',
              },
            ),
          );
        },
      ),
    );

    final release = await AppUpdateService(dio: dio).fetchLatestGithubRelease();

    expect(release?.tagName, 'v1.7.0');
    expect(release?.version, '1.7.0');
    expect(release?.body, contains('共同好友'));
  });

  test(
    'fetchLatestGithubRelease returns null when GitHub is unreachable',
    () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
              ),
            );
          },
        ),
      );

      expect(
        await AppUpdateService(dio: dio).fetchLatestGithubRelease(),
        isNull,
      );
    },
  );
}
