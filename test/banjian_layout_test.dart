import 'package:mubangumi/navigation/app_destination.dart';
import 'package:mubangumi/navigation/app_router.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:banjian_server/banjian_server.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/theme/app_theme.dart';
import 'package:mubangumi/features/anime_appreciation/room_connection.dart';
import 'package:mubangumi/features/anime_appreciation/room_host.dart';
import 'package:mubangumi/features/anime_appreciation/room_pages.dart';
import 'package:mubangumi/features/anime_appreciation/room_admin_page.dart';
import 'package:mubangumi/features/anime_appreciation/room_wifi_share.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mubangumi/state/session_controller.dart';
import 'support/pm_fixtures.dart';

const capture = bool.fromEnvironment('LAYOUT_SCREENSHOTS');
final target = RoomInvite(
  Uri.parse('http://192.168.1.5:43928'),
  'abcdefghijklmnop',
  'abcdefghijklmnopqrstuvwxyz123456',
);
Json sample() => {
  'id': target.eventId,
  'invite': target.secret,
  'title': '周五的番键会',
  'ended': false,
  'memberCount': 12,
  'name': '小沐',
  'current': 'first',
  'version': 1,
  'rounds': [
    {
      'id': 'first',
      'subject': {
        'id': 400602,
        'title': '葬送的芙莉莲',
        'summary': '一起感受故事的细节，留下这次观影的感受。',
        'cover': '',
      },
      'status': 'open',
      'myScore': 8,
      'count': 9,
      'stats': null,
      'published': false,
      'publicComments': false,
      // The new server opens the wall once this participant has scored.
      'commentsOpen': true,
      'comments': [
        {'id': 'c1', 'text': '作画和配乐都在线，节奏很舒服。', 'hidden': false},
        {'id': 'c2', 'text': '辛美尔那段真的哭了', 'hidden': false},
        {'id': 'c3', 'text': '我觉得第一集就很好看', 'hidden': false, 'mine': true},
      ],
    },
    {
      'id': 'second',
      'subject': {'id': 328609, 'title': '孤独摇滚！', 'summary': '', 'cover': ''},
      'status': 'waiting',
      'count': 0,
      'stats': null,
      'comments': [],
    },
  ],
};

class PreviewParticipation extends ParticipationController {
  PreviewParticipation({this.joined = true}) {
    invite = target;
    event = sample();
    online = true;
  }
  bool joined;
  final _drafts = <String, dynamic>{};
  @override
  bool get active => joined;
  @override
  String get name => '小沐';
  @override
  Json get drafts => _drafts;
  @override
  Future<void> refresh() async {
    online = true;
  }

  @override
  Future<Json> preview(RoomInvite target) async => {
    'title': '周五的番键会',
    'ended': false,
  };
  @override
  Future<void> saveDraft(String round, {String? text, int? score}) async {
    _drafts[round] = {
      ...?(_drafts[round] as Json?),
      'text': ?text,
      'score': ?score,
    };
  }

  @override
  Future<void> submit(
    String action, {
    int? score,
    String? text,
    String? roundId,
  }) async {
    message = '已保存，等待服务确认';
    notifyListeners();
  }

  void push() {
    event!['memberCount'] = 13;
    notifyListeners();
  }
}

class PreviewWifiVault implements RoomSecretVault {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

class PreviewHost extends RoomHost {
  @override
  Future<void> refreshAddresses() async {}
  @override
  Future<RoomInvite> prepareInvite({String? preferred}) async =>
      makeInvite(preferred: preferred);
  PreviewHost() {
    running = true;
    addresses = ['http://192.168.1.5:43928'];
    networkAddresses = [
      RoomShareAddress('WLAN', Uri.parse(addresses.first)),
      RoomShareAddress('VMware VMnet8', Uri.parse('http://192.168.68.1:43928')),
    ];
    addresses = networkAddresses.map((v) => v.address).toList();
    base = Uri.parse(addresses.first);
    password = 'preview-password';
    event = sample();
    history = [
      {'id': target.eventId, 'title': '周五的番键会', 'ended': false, 'rounds': 2},
    ];
  }
  @override
  Future<void> stop() async {}
}

void main() {
  for (final variant in [
    'join',
    'participant',
    'participant-small',
    'participant-short',
    'participant-keyboard',
    'participant-large',
    'participant-dark',
    'participant-rerouted',
    'host',
    'settings',
  ]) {
    testWidgets('native BanJian $variant', (tester) async {
      tester.view.physicalSize = Size(
        variant == 'participant-small'
            ? 352
            : variant == 'participant-short'
            ? 360
            : 390,
        variant == 'participant-short'
            ? 640
            : variant == 'participant-keyboard'
            ? 740
            : 900,
      );
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = PreviewParticipation(joined: variant != 'join');
      if (variant == 'participant-rerouted') {
        controller.invite = RoomInvite(
          Uri.parse('http://10.1.2.3:43928'),
          target.eventId,
          target.secret,
        );
        controller.event!['rounds'][0]['subject']['cover'] = 'a' * 64;
      }
      final host = PreviewHost();
      final wifiVault = PreviewWifiVault();
      await const RoomWifiNetwork('番键会热点', 'preview-pass').save(wifiVault);
      final container = ProviderContainer(
        overrides: [
          participationProvider.overrideWith((_) => controller),
          roomHostProvider.overrideWith((_) => host),
          roomWifiVaultProvider.overrideWithValue(wifiVault),
          sessionProvider.overrideWith((_) => PmTestSession()),
        ],
      );
      addTearDown(container.dispose);
      if (capture) {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        await tester.runAsync(() async {
          final font = FontLoader('Microsoft YaHei UI');
          for (final file in ['msyh-ui.ttf', 'msyhbd-ui.ttf']) {
            font.addFont(
              Future.value(
                ByteData.sublistView(
                  await File('.dart_tool/pm-chat-fonts/$file').readAsBytes(),
                ),
              ),
            );
          }
          await font.load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
        });
      }
      final boundary = GlobalKey();
      final theme = variant.endsWith('dark') ? AppTheme.dark : AppTheme.light;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: AppRouteScope(
            resolve: AppRouter.resolve,
            child: MaterialApp(
              theme: capture
                  ? theme.copyWith(
                      textTheme: theme.textTheme.apply(
                        fontFamily: 'Microsoft YaHei UI',
                      ),
                    )
                  : theme,
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(390, 900),
                  viewInsets: EdgeInsets.only(
                    bottom: variant == 'participant-keyboard' ? 300 : 0,
                  ),
                  textScaler: TextScaler.linear(
                    variant.endsWith('large') ? 1.6 : 1,
                  ),
                ),
                child: RepaintBoundary(
                  key: boundary,
                  child: variant == 'host'
                      ? const RoomHostPage()
                      : variant == 'settings'
                      ? const ExperimentalFeaturesPage()
                      : RoomParticipationPage(invite: target),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (variant.startsWith('participant')) {
        final button = tester.getRect(find.text('匿名发送'));
        expect(
          button.bottom,
          lessThanOrEqualTo(
            tester.view.physicalSize.height -
                (variant == 'participant-keyboard' ? 300 : 0),
          ),
        );
        if (!variant.endsWith('large')) {
          final scrolling = tester.state<ScrollableState>(
            find
                .descendant(
                  of: find.byKey(const ValueKey('participant-content')),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          expect(
            scrolling.position.maxScrollExtent,
            0,
            reason: 'normal participant controls must fit without scrolling',
          );
        }
      }
      if (variant == 'participant-rerouted') {
        final picture = tester.widget<Image>(find.byType(Image).first);
        expect(
          (picture.image as NetworkImage).url,
          startsWith('http://10.1.2.3:43928/cover/'),
        );
      }
      if (variant == 'participant') {
        await tester.ensureVisible(find.byType(TextField).last);
        await tester.enterText(find.byType(TextField).last, '正在输入，实时更新不能打断');
        await tester.pump(const Duration(milliseconds: 350));
        controller.push();
        await tester.pump();
        expect(find.text('正在输入，实时更新不能打断'), findsOneWidget);
        final editable = tester.widget<EditableText>(
          find.byType(EditableText).last,
        );
        expect(editable.focusNode.hasFocus, true);
        await tester.pumpAndSettle();
      }
      if (capture) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 1.5);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final out = File(
            'docs/qa/banjian-implementation/native-$variant.png',
          );
          await out.parent.create(recursive: true);
          await out.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      if (variant == 'host') {
        await tester.ensureVisible(find.text('邀请参与'));
        await tester.tap(find.text('邀请参与'));
        await tester.pumpAndSettle();
        final link = tester
            .widgetList<SelectableText>(find.byType(SelectableText))
            .firstWhere((w) => w.data?.contains('/join/') ?? false)
            .data!;
        expect(RoomInvite.parse(link)!.candidates.length, 2);
        expect(find.textContaining('其他扫码工具直接进入网页'), findsOneWidget);
        expect(find.byType(QrImageView), findsNWidgets(2));
        expect(
          find.byKey(const ValueKey('WIFI:T:WPA;S:番键会热点;P:preview-pass;;')),
          findsOneWidget,
        );
        Navigator.of(tester.element(find.text('本机参与'))).pop();
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('进入管理'));
        await tester.tap(find.text('进入管理'));
        await tester.pumpAndSettle();
        expect(find.byType(RoomAdminPage), findsOneWidget);
      }
      if (variant == 'participant') {
        await tester.enterText(find.byType(TextField).last, '切番前刚输入的草稿');
        controller.event!['current'] = 'second';
        controller.push();
        await tester.pump();
        await tester.pump();
        expect(controller.drafts['first']['text'], '切番前刚输入的草稿');
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText).last)
              .controller
              .text,
          isEmpty,
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('invite without an activity asks to create one first', (
    tester,
  ) async {
    final host = PreviewHost()
      ..event = null
      ..history = [];
    final container = ProviderContainer(
      overrides: [
        roomHostProvider.overrideWith((_) => host),
        roomWifiVaultProvider.overrideWithValue(PreviewWifiVault()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: RoomHostPage()),
      ),
    );
    await tester.pumpAndSettle();
    final invite = find.widgetWithText(OutlinedButton, '邀请参与');
    await tester.ensureVisible(invite);
    expect(tester.widget<OutlinedButton>(invite).onPressed, isNotNull);
    await tester.tap(invite);
    await tester.pumpAndSettle();
    expect(find.text('先创建番键会'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('an ended activity offers the whole-activity summary', (
    tester,
  ) async {
    final controller = PreviewParticipation();
    controller.event!
      ..['ended'] = true
      ..['rounds'][0]['status'] = 'closed'
      ..['rounds'][0]['stats'] = {
        'count': 9,
        'mean': 7.8,
        'distribution': [0, 0, 0, 0, 0, 1, 2, 4, 2, 0],
      };
    final container = ProviderContainer(
      overrides: [
        participationProvider.overrideWith((_) => controller),
        sessionProvider.overrideWith((_) => PmTestSession()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: RoomParticipationPage(invite: target)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('活动已结束，记录仍可查看'), findsOneWidget);
    await tester.ensureVisible(find.text('查看整场汇总'));
    await tester.tap(find.text('查看整场汇总'));
    await tester.pumpAndSettle();
    expect(find.textContaining('按均分排名'), findsOneWidget);
    expect(find.text('7.8'), findsOneWidget);
    expect(find.text('9 人评分 · 我打了 8 分'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
