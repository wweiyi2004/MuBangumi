import 'package:mubangumi/navigation/app_destination.dart';
import 'package:mubangumi/navigation/app_router.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/storage/community_draft_store.dart';
import 'package:mubangumi/widgets/community_composer.dart';

void main() {
  testWidgets('failed restore disables editing until retry succeeds', (
    tester,
  ) async {
    final store = _Store()..failLoad = true;
    await _show(tester, store);
    expect(
      tester.widget<TextField>(find.widgetWithText(TextField, '内容')).enabled,
      false,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '发送'))
          .onPressed,
      isNull,
    );
    store.failLoad = false;
    store.drafts['alice/topic/1'] = (title: '标题', content: '保留原稿');
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('保留原稿'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.widgetWithText(TextField, '内容')).enabled,
      true,
    );
    expect(store.writes, 0);
    await tester.tap(find.text('稍后再写'));
    await tester.pumpAndSettle();
  });
  testWidgets(
    'conflicting autosave keeps visible input and permits closing without overwriting',
    (tester) async {
      final store = _Store();
      await _show(tester, store);
      store.conflict = true;
      store.drafts['alice/topic/1'] = (title: '导入标题', content: '导入的内容');
      await tester.enterText(
        find.widgetWithText(TextField, '内容'),
        '编辑器中尚未保存的内容',
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('草稿已在其他操作中更新'), findsOneWidget);
      expect(find.text('编辑器中尚未保存的内容'), findsOneWidget);
      await tester.tap(find.text('不保存并关闭'));
      await tester.pumpAndSettle();
      expect(store.drafts['alice/topic/1']!.content, '导入的内容');
      expect(store.writes, 0);
    },
  );
  testWidgets(
    'changing account during verification cannot submit the old draft',
    (tester) async {
      final store = _Store();
      var current = true;
      var sent = 0;
      await _show(
        tester,
        store,
        isAccountCurrent: () => current,
        tokenProvider: (_) async {
          current = false;
          return 'test';
        },
        submit: (_, _, _) async {
          sent++;
        },
      );
      await tester.enterText(find.widgetWithText(TextField, '标题'), '标题');
      await tester.enterText(find.widgetWithText(TextField, '内容'), '原账号回复');
      await tester.pump();
      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();
      expect(sent, 0);
      expect(find.textContaining('登录账号已变化'), findsOneWidget);
      await tester.tap(find.text('稍后再写'));
      await tester.pumpAndSettle();
      expect(store.drafts['alice/topic/1']?.content, '原账号回复');
    },
  );

  testWidgets('moving the cursor after restore does not rewrite the draft', (
    tester,
  ) async {
    final store = _Store()
      ..drafts['alice/topic/1'] = (title: '标题', content: '原稿');
    await _show(tester, store);
    final input = tester.widget<TextField>(
      find.widgetWithText(TextField, '内容'),
    );
    input.controller!.selection = const TextSelection.collapsed(offset: 0);
    await tester.pump(const Duration(seconds: 1));
    expect(store.writes, 0);
    await tester.tap(find.text('稍后再写'));
    await tester.pumpAndSettle();
  });
  testWidgets('autosave restores in a new page and clears after sending', (
    tester,
  ) async {
    final store = _Store();
    await _show(tester, store);
    await tester.enterText(find.widgetWithText(TextField, '标题'), '标题');
    await tester.enterText(find.widgetWithText(TextField, '内容'), '长回复');
    await tester.pump(const Duration(milliseconds: 400));
    expect(store.drafts['alice/topic/1']?.content, '长回复');
    await tester.tap(find.text('稍后再写'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await _show(tester, store);
    expect(find.text('长回复'), findsOneWidget);
    expect(find.text('标题'), findsWidgets);
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    expect(store.drafts['alice/topic/1'], isNull);
    await tester.pump(const Duration(seconds: 1));
    expect(store.drafts['alice/topic/1'], isNull);
  });

  testWidgets('system back flushes an edit before its autosave timer', (
    tester,
  ) async {
    final store = _Store();
    await _show(tester, store);
    await tester.enterText(find.widgetWithText(TextField, '内容'), '刚输入');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('写回复'), findsNothing);
    expect(store.drafts['alice/topic/1']?.content, '刚输入');
  });

  testWidgets('failed save keeps the editor open and retry preserves content', (
    tester,
  ) async {
    final store = _Store()..failSave = true;
    await _show(tester, store);
    await tester.enterText(find.widgetWithText(TextField, '内容'), '不能丢');
    await tester.pump();
    await tester.tap(find.text('稍后再写'));
    await tester.pumpAndSettle();
    expect(find.text('写回复'), findsOneWidget);
    expect(find.text('草稿保存失败，请重试'), findsOneWidget);
    store.failSave = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(store.drafts['alice/topic/1']?.content, '不能丢');
    await tester.tap(find.text('稍后再写'));
    await tester.pumpAndSettle();
    expect(find.text('写回复'), findsNothing);
  });

  testWidgets(
    'slow restore disables editing and failed sends retain the draft',
    (tester) async {
      final restore = Completer<CommunityDraftData?>();
      final store = _Store()..pendingLoad = restore.future;
      await _show(
        tester,
        store,
        settle: false,
        submit: (_, _, _) async => throw StateError('发送失败'),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.widget<TextField>(find.widgetWithText(TextField, '内容')).enabled,
        isFalse,
      );
      restore.complete((title: '旧标题', content: '旧回复'));
      await tester.pumpAndSettle();
      expect(find.text('旧回复'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, '内容'), '新回复');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();
      expect(find.text('写回复'), findsOneWidget);
      expect(store.drafts['alice/topic/1']?.content, '新回复');
      await tester.tap(find.text('稍后再写'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'draft deletion failure does not turn a sent reply into a retry',
    (tester) async {
      final store = _Store();
      var sent = 0;
      await _show(
        tester,
        store,
        submit: (_, _, _) async {
          sent++;
          store.failSave = true;
        },
      );
      await tester.enterText(find.widgetWithText(TextField, '标题'), '标题');
      await tester.enterText(find.widgetWithText(TextField, '内容'), '回复');
      await tester.pump();
      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();
      expect(sent, 1);
      expect(find.text('写回复'), findsNothing);
      expect(find.textContaining('发送成功，但本地草稿未能清除'), findsOneWidget);
    },
  );
}

Future<void> _show(
  WidgetTester tester,
  _Store store, {
  bool settle = true,
  CommunitySubmit? submit,
  CommunityTokenProvider? tokenProvider,
  bool Function()? isAccountCurrent,
}) async {
  await tester.pumpWidget(
    AppRouteScope(
      resolve: AppRouter.resolve,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showCommunityComposer(
                context,
                heading: '写回复',
                requireTitle: true,
                draftKey: 'alice/topic/1',
                draftStore: store,
                tokenProvider: tokenProvider ?? (_) async => 'test',
                isAccountCurrent: isAccountCurrent,
                onSubmit: submit ?? (_, _, _) async {},
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  if (settle) await tester.pumpAndSettle();
}

class _Store extends CommunityDraftRepository {
  final drafts = <String, CommunityDraftData>{};
  bool failSave = false;
  bool failLoad = false;
  bool conflict = false;
  int writes = 0;
  Future<CommunityDraftData?>? pendingLoad;

  @override
  Future<CommunityDraftData?> load(String key) {
    if (failLoad) return Future.error(StateError('read failed'));
    return pendingLoad ?? Future.value(drafts[key]);
  }

  @override
  Future<int> saveVersioned(
    String key,
    CommunityDraftData draft, {
    required int expectedRevision,
  }) {
    if (conflict) return Future.error(const CommunityDraftConflict());
    return super.saveVersioned(key, draft, expectedRevision: expectedRevision);
  }

  @override
  Future<void> save(String key, CommunityDraftData draft) async {
    writes++;
    if (failSave) throw StateError('disk full');
    if (draft.title.isEmpty && draft.content.isEmpty) {
      drafts.remove(key);
    } else {
      drafts[key] = draft;
    }
  }
}
