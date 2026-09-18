import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/pm_service.dart';
import 'package:mubangumi/core/storage/pm_draft_store.dart';
import 'package:mubangumi/models/pm_models.dart';
import 'package:mubangumi/screens/pm_page.dart';
import 'package:mubangumi/state/session_controller.dart';
import 'package:mubangumi/state/website_session_controller.dart';
import 'package:mubangumi/core/theme/app_theme.dart';

import 'support/memory_pm_draft_repository.dart';
import 'support/pm_fixtures.dart';

const _screenshots = bool.fromEnvironment('UX_SCREENSHOTS');
final _boundary = GlobalKey();

void main() {
  testWidgets(
    'back before debounce flushes all fields and reopening restores them',
    (tester) async {
      final env = _Environment();
      await _show(tester, env);
      await _fill(tester, recipient: 'alice', title: '标题', body: '第一行\n😀');
      await tester.pageBack();
      await tester.pumpAndSettle();
      final draft = (await env.repo.listCompose(1)).single;
      expect(
        [draft.recipient, draft.title, draft.body],
        ['alice', '标题', '第一行\n😀'],
      );
      await tester.tap(find.text('写信'));
      await tester.pumpAndSettle();
      expect(_texts(tester), ['alice', '标题', '第一行\n😀']);
      expect(env.service.sentBodies, isEmpty);
    },
  );

  testWidgets(
    'inactive flushes immediately and a rebuilt app restores saved content',
    (tester) async {
      final env = _Environment();
      await _show(tester, env);
      await _fill(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect((await env.repo.listCompose(1)).single.body, '正文');
      await tester.pumpWidget(const SizedBox.shrink());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final restarted = _Environment(repo: env.repo);
      await _show(tester, restarted);
      expect(_texts(tester), ['alice', '标题', '正文']);
    },
  );

  testWidgets('failed send retains draft and successful retry clears it', (
    tester,
  ) async {
    final env = _Environment()..service.failSend = true;
    await _show(tester, env);
    await _fill(tester);
    await _send(tester);
    expect((await env.repo.listCompose(1)).single.body, '正文');
    expect(_texts(tester).last, '正文');
    env.service.failSend = false;
    await _send(tester);
    expect(await env.repo.listCompose(1), isEmpty);
    expect(env.service.sentBodies, ['正文']);
    expect(find.text('写信'), findsOneWidget);
  });

  testWidgets(
    'cleanup failure prevents another POST and retries only deletion',
    (tester) async {
      final env = _Environment()..repo.failClear = true;
      await _show(tester, env);
      await _fill(tester);
      await _send(tester);
      expect(env.service.sentBodies, ['正文']);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(find.textContaining('勿重复发送'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == '新建草稿',
              ),
            )
            .onPressed,
        isNull,
      );
      env.repo.failClear = false;
      await tester.ensureVisible(find.text('重试清除'));
      await tester.tap(find.text('重试清除'));
      await tester.pumpAndSettle();
      expect(await env.repo.listCompose(1), isEmpty);
      expect(env.service.sentBodies, ['正文']);
      expect(find.text('写信'), findsOneWidget);
    },
  );

  testWidgets(
    'failed save keeps editor open and retry persists the same text',
    (tester) async {
      final env = _Environment()..repo.failSave = true;
      await _show(tester, env);
      await _fill(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('草稿尚未保存'), findsOneWidget);
      await tester.tap(find.text('留在页面'));
      await tester.pumpAndSettle();
      expect(_texts(tester).last, '正文');
      env.repo.failSave = false;
      await tester.ensureVisible(find.text('重试'));
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect((await env.repo.listCompose(1)).single.body, '正文');
      expect(find.text('草稿已保存在本机'), findsOneWidget);
    },
  );

  testWidgets('new draft and draft picker preserve older documents', (
    tester,
  ) async {
    final env = _Environment();
    await _show(tester, env);
    await _fill(tester, title: '较早的短信');
    await tester.tap(find.byTooltip('新建草稿'));
    await tester.pumpAndSettle();
    expect(_texts(tester), ['', '', '']);
    await _fill(tester, recipient: 'bob', title: '新的短信');
    await tester.tap(find.byTooltip('其他草稿'));
    await tester.pumpAndSettle();
    expect(find.text('较早的短信'), findsOneWidget);
    await tester.tap(find.text('较早的短信'));
    await tester.pumpAndSettle();
    expect(_texts(tester), ['alice', '较早的短信', '正文']);
    expect(await env.repo.listCompose(1), hasLength(2));
    expect(env.service.sentBodies, isEmpty);
  });

  testWidgets(
    'account change flushes original draft but never fills another account',
    (tester) async {
      final env = _Environment();
      await _show(tester, env);
      await _fill(tester, body: '账号一的草稿');
      env.session.switchUser(2);
      await tester.pumpAndSettle();
      expect(_texts(tester), ['', '', '']);
      expect((await env.repo.listCompose(1)).single.body, '账号一的草稿');
      expect(await env.repo.listCompose(2), isEmpty);
      env.website.account = 'account-b';
      env.website.verifiedUserId = 2;
      await env.container.read(websiteSessionProvider.notifier).reload();
      await tester.pumpAndSettle();
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(_texts(tester), ['', '', '']);
      await _fill(tester, body: '账号二的草稿');
      await tester.pump(const Duration(milliseconds: 400));
      expect((await env.repo.listCompose(2)).single.body, '账号二的草稿');
      expect((await env.repo.listCompose(1)).single.body, '账号一的草稿');
    },
  );

  testWidgets(
    'same-account reauthentication restores the edited recipient document',
    (tester) async {
      final env = _Environment();
      await _show(tester, env);
      await _fill(tester, recipient: 'bob', body: '改过收件人的草稿');
      env.website.account = 'renewed-session';
      await env.container.read(websiteSessionProvider.notifier).reload();
      await tester.pumpAndSettle();
      expect(_texts(tester), ['', '', '']);
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(_texts(tester), ['bob', '标题', '改过收件人的草稿']);
      expect(await env.repo.listCompose(1), hasLength(1));
      expect(env.service.sentBodies, isEmpty);
    },
  );

  testWidgets(
    'sending an older draft reports completion while preserving current work',
    (tester) async {
      final env = _Environment();
      await _show(tester, env);
      await _fill(tester, title: '早先的草稿', body: '发送这份');
      await tester.tap(find.byTooltip('新建草稿'));
      await tester.pumpAndSettle();
      await _fill(tester, title: '仍在编辑', body: '保留这份');
      await tester.tap(find.byTooltip('其他草稿'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('早先的草稿'));
      await tester.pumpAndSettle();
      await _send(tester);
      expect(_texts(tester), ['alice', '仍在编辑', '保留这份']);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(env.routeResults, [true]);
      expect((await env.repo.listCompose(1)).single.body, '保留这份');
      expect(env.service.sentBodies, ['发送这份']);
    },
  );

  testWidgets('a mismatched website account never restores private text', (
    tester,
  ) async {
    final env = _Environment()..website.verifiedUserId = 2;
    await env.repo.save(
      const PmDraft(
        id: 'old',
        ownerId: 1,
        kind: PmDraftKind.compose,
        body: 'private',
      ),
      expectedRevision: 0,
    );
    await _show(tester, env);
    expect(_texts(tester), ['', '', '']);
    expect(find.textContaining('网站登录与应用账号不一致'), findsOneWidget);
    expect(env.service.sentBodies, isEmpty);
    expect((await env.repo.listCompose(1)).single.body, 'private');
  });

  testWidgets('changing thread saves and restores separate reply drafts', (
    tester,
  ) async {
    final env = _Environment();
    await _show(tester, env, reply: true);
    await tester.enterText(find.byType(TextField), '回复 A');
    await tester.tap(find.text('话题 B'));
    await tester.pumpAndSettle();
    expect(_texts(tester), ['']);
    await tester.enterText(find.byType(TextField), '回复 B');
    await tester.tap(find.text('话题 A'));
    await tester.pumpAndSettle();
    expect(_texts(tester), ['回复 A']);
    expect(
      (await env.repo.read(1, PmDraft.replyId('42', 'b'))).draft!.body,
      '回复 B',
    );
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    expect(_texts(tester), ['']);
    expect((await env.repo.read(1, PmDraft.replyId('42', 'a'))).draft, isNull);
    expect(
      (await env.repo.read(1, PmDraft.replyId('42', 'b'))).draft!.body,
      '回复 B',
    );
  });

  testWidgets('failed save prevents thread switch from discarding text', (
    tester,
  ) async {
    final env = _Environment()..repo.failSave = true;
    await _show(tester, env, reply: true);
    await tester.enterText(find.byType(TextField), '未保存回复');
    await tester.tap(find.text('话题 B'));
    await tester.pumpAndSettle();
    expect(_texts(tester), ['未保存回复']);
    expect(env.service.loadedThreads, [null]);
    expect(find.text('草稿保存失败，请重试'), findsOneWidget);
    env.repo.failSave = false;
    await tester.tap(find.text('话题 B'));
    await tester.pumpAndSettle();
    expect(_texts(tester), ['']);
    expect(
      (await env.repo.read(1, PmDraft.replyId('42', 'a'))).draft!.body,
      '未保存回复',
    );
  });

  testWidgets(
    'send completing after route disposal clears only the sent draft',
    (tester) async {
      final pending = Completer<void>();
      final env = _Environment()..service.sendGate = pending.future;
      await _show(tester, env);
      await _fill(tester);
      await tester.ensureVisible(find.text('发送短信'));
      await tester.tap(find.text('发送短信'));
      await tester.pump();
      expect(env.service.sendAttempts, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete();
      await tester.pumpAndSettle();
      expect(await env.repo.listCompose(1), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 390.0, 1200.0]) {
    for (final scale in [1.0, 1.8]) {
      for (final dark in [false, true]) {
        testWidgets('draft UI fits $width scale $scale dark $dark', (
          tester,
        ) async {
          final env = _Environment();
          await _show(tester, env, width: width, scale: scale, dark: dark);
          await _fill(tester, title: '继续讨论这部作品', body: '上次还没有写完的想法……');
          tester.testTextInput.hide();
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pumpAndSettle();
          await _capture(tester, 'compose_${width}_${scale}_$dark');
          await tester.ensureVisible(find.text('发送短信'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pageBack();
          await tester.pumpAndSettle();
          await tester.tap(find.text('回复'));
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField), '我也很喜欢这部作品，稍后继续写。');
          tester.testTextInput.hide();
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pumpAndSettle();
          await _capture(tester, 'reply_${width}_${scale}_$dark');
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}

Future<void> _fill(
  WidgetTester tester, {
  String recipient = 'alice',
  String title = '标题',
  String body = '正文',
}) async {
  await tester.enterText(find.byType(TextField).at(0), recipient);
  await tester.enterText(find.byType(TextField).at(1), title);
  await tester.enterText(find.byType(TextField).at(2), body);
}

List<String> _texts(WidgetTester tester) => tester
    .widgetList<TextField>(find.byType(TextField))
    .map((field) => field.controller!.text)
    .toList();
Future<void> _send(WidgetTester tester) async {
  await tester.ensureVisible(find.text('发送短信'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('发送短信'));
  await tester.pumpAndSettle();
}

class _Environment {
  _Environment({MemoryPmDraftRepository? repo})
    : repo = repo ?? MemoryPmDraftRepository();
  final MemoryPmDraftRepository repo;
  final routeResults = <bool?>[];
  final website = PmTestWebsiteStore();
  final session = PmTestSession();
  late final service = _Service(website);
  late final container = ProviderContainer(
    overrides: [
      sessionProvider.overrideWith((ref) => session),
      websiteSessionStoreProvider.overrideWithValue(website),
      pmDraftRepositoryProvider.overrideWithValue(repo),
    ],
  );
}

Future<void> _show(
  WidgetTester tester,
  _Environment env, {
  bool reply = false,
  double width = 390,
  double scale = 1,
  bool dark = false,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(env.container.dispose);
  await env.container.read(websiteSessionProvider.notifier).reload();
  var theme = dark ? AppTheme.dark : AppTheme.light;
  if (_screenshots) {
    await tester.runAsync(() async {
      final bytes = await File('C:/Windows/Fonts/msyh.ttc').readAsBytes();
      await (FontLoader(
        'PmUxFont',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    });
    theme = theme.copyWith(
      textTheme: theme.textTheme.apply(fontFamily: 'PmUxFont'),
      filledButtonTheme: FilledButtonThemeData(
        style: theme.filledButtonTheme.style?.copyWith(
          textStyle: WidgetStatePropertyAll(
            theme.filledButtonTheme.style?.textStyle
                ?.resolve({})
                ?.copyWith(fontFamily: 'PmUxFont'),
          ),
        ),
      ),
      chipTheme: theme.chipTheme.copyWith(
        labelStyle: theme.chipTheme.labelStyle?.copyWith(
          fontFamily: 'PmUxFont',
        ),
        secondaryLabelStyle: theme.chipTheme.secondaryLabelStyle?.copyWith(
          fontFamily: 'PmUxFont',
        ),
      ),
    );
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: env.container,
      child: MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: RepaintBoundary(key: _boundary, child: child!),
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  onPressed: () async => env.routeResults.add(
                    await Navigator.of(context).push<bool>(
                      MaterialPageRoute<bool>(
                        builder: (_) => PmComposeScreen(service: env.service),
                      ),
                    ),
                  ),
                  child: const Text('写信'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<bool>(
                      builder: (_) => PmConversationScreen(
                        conversationId: '42',
                        title: '作品讨论',
                        service: env.service,
                      ),
                    ),
                  ),
                  child: const Text('回复'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text(reply ? '回复' : '写信'));
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (!_screenshots) return;
  await tester.runAsync(() async {
    final boundary =
        _boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '.dart_tool/pm_draft_$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

class _Service extends PmService {
  _Service(PmTestWebsiteStore store) : super(sessionStore: store);
  bool failSend = false;
  Future<void>? sendGate;
  final sentBodies = <String>[];
  final loadedThreads = <String?>[];
  int sendAttempts = 0;
  @override
  Future<PmComposeParams> loadComposeParams(String user) async =>
      PmComposeParams(formhash: 'hash', msgReceivers: user);
  @override
  Future<void> compose({
    required PmComposeParams params,
    required String title,
    required String body,
  }) async {
    sendAttempts++;
    await sendGate;
    if (failSend) throw const PmException('发送失败');
    sentBodies.add(body);
  }

  @override
  Future<void> reply({
    required PmReplyForm form,
    required String body,
    String? title,
  }) => compose(
    params: const PmComposeParams(formhash: 'hash', msgReceivers: 'alice'),
    title: title ?? '',
    body: body,
  );
  @override
  Future<PmConversationDetail> loadConversation(
    String id, {
    String? threadId,
  }) async {
    loadedThreads.add(threadId);
    final thread = threadId ?? 'a';
    return PmConversationDetail(
      peerName: 'Alice',
      peerUserId: 'alice',
      messages: const [
        PmMessage(
          name: 'Alice',
          userId: 'alice',
          contentHtml: '这部作品的设定很有趣，你觉得呢？',
          timeText: '今天',
        ),
      ],
      form: PmReplyForm(
        formhash: 'hash',
        msgReceivers: 'alice',
        related: thread,
      ),
      threads: [
        PmThreadFilter(id: 'a', title: '话题 A', current: thread == 'a'),
        PmThreadFilter(id: 'b', title: '话题 B', current: thread == 'b'),
      ],
    );
  }
}
