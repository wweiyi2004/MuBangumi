import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/pm_service.dart';
import 'package:mubangumi/core/storage/pm_draft_store.dart';
import 'package:mubangumi/core/theme/app_theme.dart';
import 'package:mubangumi/models/pm_models.dart';
import 'package:mubangumi/screens/pm_page.dart';
import 'package:mubangumi/state/session_controller.dart';
import 'package:mubangumi/state/website_session_controller.dart';

import 'support/memory_pm_draft_repository.dart';
import 'support/pm_fixtures.dart';

const _captureEnabled = bool.fromEnvironment('PM_CHAT_SCREENSHOTS');
final _boundary = GlobalKey();

void main() {
  testWidgets(
    'reading history survives refresh and latest button returns to bottom',
    (tester) async {
      final env = _Env()..service.longHistory = true;
      await _show(tester, env);
      await tester.tap(find.text('本周新番'));
      await tester.pumpAndSettle();
      final list = find.descendant(
        of: find.byType(PmConversationScreen),
        matching: find.byType(ListView),
      );
      final scroll = tester.widget<ListView>(list).controller!;
      await tester.drag(list, const Offset(0, 500));
      await tester.pumpAndSettle();
      final offset = scroll.offset;
      expect(find.text('回到最新'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(PmConversationScreen),
          matching: find.byTooltip('刷新'),
        ),
      );
      await tester.pumpAndSettle();
      expect(scroll.offset, closeTo(offset, 1));
      await tester.tap(find.text('回到最新'));
      await tester.pumpAndSettle();
      expect(scroll.position.extentBefore, closeTo(0, 1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('switching while sending stays in the original conversation', (
    tester,
  ) async {
    final env = _Env();
    final gate = Completer<void>();
    env.service.sendGate = gate.future;
    await _show(tester, env);
    await tester.tap(find.text('本周新番'));
    await tester.pumpAndSettle();
    await tester.enterText(_input, '等待发送');
    await tester.pump();
    await tester.tap(find.text('发送'));
    await tester.pump();
    await tester.tap(find.text('周末计划'));
    await tester.pump();
    expect(env.service.loads, ['alice']);
    gate.complete();
    await tester.pumpAndSettle();
    expect(env.service.sent, ['等待发送']);
    await tester.tap(find.text('周末计划'));
    await tester.pumpAndSettle();
    expect(env.service.loads.last, 'bob');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'desktop switches conversations only after saving and restores drafts',
    (tester) async {
      final env = _Env();
      await _show(tester, env);
      await tester.tap(find.text('本周新番'));
      await tester.pumpAndSettle();
      await tester.enterText(_input, '还没写完的回复');
      env.repo.failSave = true;
      await tester.tap(find.text('周末计划'));
      await tester.pumpAndSettle();
      expect(_body(tester), '还没写完的回复');
      expect(env.service.loads, ['alice']);
      env.repo.failSave = false;
      await tester.tap(find.text('周末计划'));
      await tester.pumpAndSettle();
      expect(_body(tester), '');
      await tester.tap(find.text('本周新番'));
      await tester.pumpAndSettle();
      expect(_body(tester), '还没写完的回复');
      expect(env.service.sent, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'resizing preserves the active draft and mobile back opens the list',
    (tester) async {
      final env = _Env();
      await _show(tester, env);
      await tester.tap(find.text('本周新番'));
      await tester.pumpAndSettle();
      await tester.enterText(_input, '窗口缩小也保留');
      tester.view.physicalSize = const Size(390, 800);
      await tester.pumpAndSettle();
      expect(_body(tester), '窗口缩小也保留');
      expect(find.byType(PmConversationScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(PmConversationScreen), findsNothing);
      await tester.tap(find.text('本周新番'));
      await tester.pumpAndSettle();
      expect(_body(tester), '窗口缩小也保留');
      expect(env.service.sent, isEmpty);
    },
  );

  testWidgets(
    'empty send disabled, failed send retained, shortcut retry sends once',
    (tester) async {
      final env = _Env()..service.failSend = true;
      await _show(tester, env);
      await tester.tap(find.text('本周新番'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '发送'))
            .onPressed,
        isNull,
      );
      await tester.enterText(_input, '测试回复');
      await tester.pump();
      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();
      expect(_body(tester), '测试回复');
      env.service.failSend = false;
      await tester.tap(_input);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(env.service.sent, ['测试回复']);
      expect(_body(tester), '');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'search filters loaded conversations and clearing restores list',
    (tester) async {
      final env = _Env();
      await _show(tester, env);
      await tester.enterText(find.byType(TextField), '周末');
      await tester.pumpAndSettle();
      expect(find.text('本周新番'), findsNothing);
      expect(find.text('周末计划'), findsOneWidget);
      await tester.tap(find.byTooltip('清除搜索'));
      await tester.pumpAndSettle();
      expect(find.text('本周新番'), findsOneWidget);
    },
  );

  testWidgets(
    'account replacement during a pending switch never reopens old chat',
    (tester) async {
      final env = _Env();
      await _show(tester, env);
      await tester.tap(find.text('本周新番'));
      await tester.pumpAndSettle();
      await tester.enterText(_input, '旧账号草稿');
      final gate = Completer<void>();
      env.repo.saveGate = gate.future;
      await tester.tap(find.text('周末计划'));
      await tester.pump();
      env.store.account = 'replacement';
      await env.container.read(websiteSessionProvider.notifier).reload();
      await tester.pump();
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(PmConversationScreen), findsNothing);
      expect(find.text('旧账号草稿'), findsNothing);
      expect(env.service.loads, ['alice']);
      expect(tester.takeException(), isNull);
    },
  );

  for (final variant in ['desktop', 'dark', 'phone', 'large-text']) {
    testWidgets('$variant chat shows both avatars and keeps composer visible', (
      tester,
    ) async {
      final env = _Env();
      if (_captureEnabled) {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      }
      try {
        await _show(
          tester,
          env,
          width: variant == 'phone' ? 390 : 1200,
          dark: variant == 'dark',
          scale: variant == 'large-text' ? 1.4 : 1,
        );
        await tester.tap(find.text('本周新番'));
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel('我的头像'), findsOneWidget);
        expect(find.bySemanticsLabel('小夏的头像'), findsWidgets);
        expect(tester.getRect(_input).bottom, lessThanOrEqualTo(850));
        expect(tester.takeException(), isNull);
        if (_captureEnabled) {
          await tester.runAsync(() async {
            final boundary =
                _boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary;
            final image = await boundary.toImage();
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            await File(
              '.dart_tool/pm-chat-$variant.png',
            ).writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}

Finder get _input => find.widgetWithText(TextField, '输入回复…');
String _body(WidgetTester tester) =>
    tester.widget<TextField>(_input).controller!.text;

Future<void> _show(
  WidgetTester tester,
  _Env env, {
  double width = 1200,
  bool dark = false,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 850);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(env.container.dispose);
  await env.container.read(websiteSessionProvider.notifier).reload();
  if (_captureEnabled) {
    await tester.runAsync(() async {
      final font = FontLoader('Microsoft YaHei UI');
      for (final file in ['msyh-ui.ttf', 'msyhbd-ui.ttf']) {
        final bytes = await File(
          '.dart_tool/pm-chat-fonts/$file',
        ).readAsBytes();
        font.addFont(Future.value(ByteData.sublistView(bytes)));
      }
      await font.load();
      final emoji = await File('C:/Windows/Fonts/seguiemj.ttf').readAsBytes();
      await (FontLoader(
        'Segoe UI Emoji',
      )..addFont(Future.value(ByteData.sublistView(emoji)))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    });
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: env.container,
      child: MaterialApp(
        theme: dark ? AppTheme.dark : AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: RepaintBoundary(key: _boundary, child: child!),
        ),
        home: PmPage(service: env.service),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _Env {
  final repo = MemoryPmDraftRepository();
  final store = PmTestWebsiteStore();
  late final service = _Service(store);
  late final container = ProviderContainer(
    overrides: [
      sessionProvider.overrideWith((ref) => PmTestSession()),
      pmDraftRepositoryProvider.overrideWithValue(repo),
      websiteSessionStoreProvider.overrideWithValue(store),
    ],
  );
}

class _Service extends PmService {
  _Service(PmTestWebsiteStore store) : super(sessionStore: store);
  bool failSend = false;
  bool longHistory = false;
  Future<void>? sendGate;
  final loads = <String>[];
  final sent = <String>[];
  @override
  Future<List<PmConversation>> loadInbox({int page = 1}) async => page > 1
      ? []
      : const [
          PmConversation(
            id: 'alice',
            title: '本周新番',
            preview: '这周的新番你看了吗？',
            peerName: '小夏',
            peerUserId: 'alice',
            timeText: '14:32',
            isUnread: true,
          ),
          PmConversation(
            id: 'bob',
            title: '周末计划',
            preview: '周末一起补番吧',
            peerName: '阿月',
            peerUserId: 'bob',
            timeText: '昨天',
          ),
        ];
  @override
  Future<List<PmConversation>> loadOutbox({int page = 1}) async => [];
  @override
  Future<PmConversationDetail> loadConversation(
    String id, {
    String? threadId,
  }) async {
    loads.add(id);
    return PmConversationDetail(
      peerName: id == 'alice' ? '小夏' : '阿月',
      peerUserId: id,
      form: PmReplyForm(formhash: 'test', msgReceivers: id),
      messages: longHistory
          ? List.generate(
              30,
              (index) => PmMessage(
                name: '小夏',
                userId: 'alice',
                contentHtml: '第 $index 条历史消息',
                timeText: '14:$index',
              ),
            )
          : const [
              PmMessage(
                name: '小夏',
                userId: 'alice',
                contentHtml: '这周的新番你看了吗？<br>画面和配乐都很喜欢。',
                timeText: '今天 14:30',
              ),
              PmMessage(
                name: '我',
                userId: 'user1',
                contentHtml: '看了！最后那段很精彩。<br>已经开始期待下一集了 😊',
                timeText: '今天 14:30',
                isSelf: true,
              ),
              PmMessage(
                name: '小夏',
                userId: 'alice',
                contentHtml: '我也是，等更新后再一起聊聊吧～',
                timeText: '今天 14:32',
              ),
            ],
    );
  }

  @override
  Future<void> reply({
    required PmReplyForm form,
    required String body,
    String? title,
  }) async {
    await sendGate;
    if (failSend) throw const PmException('发送失败，请重试');
    sent.add(body);
  }
}
