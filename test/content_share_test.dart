import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mubangumi/core/sharing/share_content.dart';
import 'package:mubangumi/core/shortcuts/shared_bangumi_link.dart';
import 'package:mubangumi/core/social/friend_qr.dart';
import 'package:mubangumi/core/social/friend_qr_export.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/models/community_models.dart';
import 'package:mubangumi/widgets/content_share_card.dart';
import 'package:mubangumi/widgets/content_share_sheet.dart';
import 'support/ux_visuals.dart';

final _subject = Subject.fromJson({
  'id': 42,
  'name': 'Beyond the blue',
  'name_cn': '在蓝色彼端',
  'type': 2,
  'summary': '一段关于相遇与成长的故事。<b>在熟悉的日常中，发现新的风景。</b>',
  'date': '2026-07-01',
  'eps': 12,
  'platform': 'TV',
  'rating': {'score': 8.6, 'rank': 42, 'total': 12345},
  'collection': {'total': 54321},
});

void main() {
  FilePicker.platform = _Picker('cancel');
  for (final result in ['save', 'cancel', 'fail']) {
    testWidgets('PNG save action exports the preview and handles $result', (
      tester,
    ) async {
      final original = FilePicker.platform;
      final picker = _Picker(result);
      FilePicker.platform = picker;
      addTearDown(() => FilePicker.platform = original);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContentShareSheet(content: ShareContent.subject(_subject)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存图片'));
      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while (picker.bytes == null) {
          if (DateTime.now().isAfter(deadline)) {
            throw TimeoutException('PNG save was not called');
          }
          await tester.pump(const Duration(milliseconds: 20));
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(picker.filename, 'MuBangumi-subject-42.png');
      expect(
        FriendQr.decodePayloadFromImageBytes(picker.bytes!),
        'https://github.com/wweiyi2004/MuBangumi/releases/latest#subject/42',
      );
      expect(
        find.text('分享卡片已保存到所选位置'),
        result == 'save' ? findsOneWidget : findsNothing,
      );
      expect(
        find.textContaining('分享失败'),
        result == 'fail' ? findsOneWidget : findsNothing,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '保存图片'))
            .onPressed,
        isNotNull,
      );
    });
  }
  test('subject summary precedes canonical URL and carries public metrics', () {
    final content = ShareContent.subject(_subject);
    expect(content.linkText, startsWith('在蓝色彼端'));
    expect(content.linkText, contains('8.6 分'));
    expect(content.linkText, contains('收藏人数 54321'));
    expect(content.linkText, contains('发现新的风景。'));
    expect(content.linkText, endsWith('https://bgm.tv/subject/42'));
    expect(content.linkText, isNot(contains('<b>')));
    expect(
      plainShareText('[b]今天[/b][img]https://example.test/a.png[/img] &amp; 明天'),
      '今天 & 明天',
    );
  });

  for (final status in [true, false]) {
    test(
      'status and collection activity URLs round trip with author ownership: $status',
      () {
        final content = ShareContent.timeline(
          CommunityTimelineItem(
            id: 64,
            user: const CommunityUser(
              id: 9,
              username: 'alice',
              nickname: '爱丽丝',
            ),
            description: '看过 在蓝色彼端',
            content: '今天也有值得记录的小事。',
            createdAt: DateTime(2026, 9, 30),
            isStatus: status,
          ),
        );
        final link = SharedBangumiLink.parse(content.url)!;
        expect(link.kind, SharedBangumiKind.timeline);
        expect(link.id, 64);
        expect(link.username, 'alice');
        expect(link.isStatus, status);
        expect(content.linkText, contains('今天也有值得记录的小事。'));
      },
    );
  }

  for (final variant in ['subject', 'long', 'timeline']) {
    testWidgets('card exports a readable complete QR and fits $variant', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final subject = ShareContent.subject(_subject);
      final content = variant == 'timeline'
          ? ShareContent.timeline(
              CommunityTimelineItem(
                id: 64,
                user: const CommunityUser(
                  id: 9,
                  username: 'alice',
                  nickname: '爱丽丝',
                ),
                description: '今天的观影记录',
                content: '夏天结束了，但那些闪闪发亮的瞬间会留在记忆里。\n分享一部最近喜欢的作品，也期待遇见更多同样喜欢它的人。',
                createdAt: DateTime(2026, 9, 30),
                isStatus: true,
              ),
            )
          : variant == 'long'
          ? ShareContent(
              title: '一个非常长的作品名字' * 10,
              url: subject.url,
              fileKey: subject.fileKey,
              subtitle: 'A long original name ' * 10,
              excerpt: '简介与换行、表情 😀 测试。' * 80,
              detail: '动画 · TV · 2026-07-01 · 100 话 · 测试详情',
              score: 8.6,
              metrics: subject.metrics,
            )
          : subject;
      final key = GlobalKey();
      final theme = await uxTheme(tester, dark: false);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: key,
                child: ContentShareCard(content: content),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      Uint8List? bytes;
      await tester.runAsync(() async {
        bytes = await FriendQrExporter.captureBoundary(key, pixelRatio: 2);
      });
      expect(img.decodePng(bytes!)!.width, 1440);
      expect(FriendQr.decodePayloadFromImageBytes(bytes!), content.qrUrl);
      await captureUx(tester, key, 'share-card-$variant');
    });
  }

  testWidgets(
    'small-screen share sheet copies summary and link without clipping at large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.8)),
            child: child!,
          ),
          home: Scaffold(
            body: ContentShareSheet(content: ShareContent.subject(_subject)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('复制摘要链接'));
      await tester.pumpAndSettle();
      expect(copied, ShareContent.subject(_subject).linkText);
    },
  );
}

class _Picker extends FilePicker {
  _Picker(this.result);
  final String result;
  Uint8List? bytes;
  String? filename;
  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    this.bytes = bytes;
    filename = fileName;
    if (result == 'fail') throw StateError('synthetic write failure');
    return result == 'save' ? 'chosen.png' : null;
  }
}
