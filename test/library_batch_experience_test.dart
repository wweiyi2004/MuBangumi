import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/models/schedule_models.dart';
import 'package:mubangumi/screens/library_batch_page.dart';
import 'package:mubangumi/screens/library_page.dart';
import 'package:mubangumi/state/schedule_controller.dart';
import 'package:mubangumi/state/session_controller.dart';

import 'support/library_batch_fixtures.dart';
import 'support/schedule_fixtures.dart';
import 'support/ux_visuals.dart';

final _boundary = GlobalKey();

void main() {
  testWidgets(
    'selection can be cleared and long titles remain readable without changing selection',
    (tester) async {
      final env = _Environment();
      await _show(tester, env);
      await _select(tester, 1);
      await tester.longPress(find.byKey(const ValueKey('library-subject-1')));
      await tester.pumpAndSettle();
      expect(find.text('完整名称'), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('已选 1 部'), findsOneWidget);
      await tester.tap(find.text('清空选择'));
      await tester.pumpAndSettle();
      expect(find.text('已选 0 部'), findsOneWidget);
      await tester.tap(find.text('退出多选'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('library-select-1')), findsNothing);
    },
  );

  testWidgets(
    'back during execution stops after the current item and retains unfinished selection',
    (tester) async {
      final env = _Environment();
      await _show(tester, env);
      await _select(tester, 1);
      await _select(tester, 2);
      await tester.tap(find.text('改状态'));
      await tester.pumpAndSettle();
      final gate = Completer<void>();
      env.queue.saveGate = gate.future;
      await tester.tap(find.text('确认执行（2）'));
      await tester.pump();
      await tester.tap(find.byType(BackButton));
      await tester.pump();
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(LibraryBatchPage), findsNothing);
      expect(env.queue.calls, 1);
      expect(find.text('已选 1 部'), findsOneWidget);
    },
  );
  testWidgets(
    'selection across filters is visible and confirmation changes only selected items',
    (tester) async {
      final env = _Environment();
      await _show(tester, env);
      await _select(tester, 1);
      await tester.enterText(find.byType(TextField).first, '收藏作品 2');
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('已选 1 部 · 1 部在当前筛选外'), findsOneWidget);
      await tester.tap(find.text('全选当前结果'));
      await tester.pumpAndSettle();
      expect(find.text('已选 2 部 · 1 部在当前筛选外'), findsOneWidget);
      await tester.tap(find.text('改状态'));
      await tester.pumpAndSettle();
      expect(find.byType(LibraryBatchPage), findsOneWidget);
      expect(find.textContaining('预计修改 2 部'), findsOneWidget);
      expect(env.queue.calls, 0);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('已选 2 部 · 1 部在当前筛选外'), findsOneWidget);
      await tester.tap(find.text('改状态'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认执行（2）'));
      await tester.pumpAndSettle();
      expect(find.text('本机已保存 2'), findsOneWidget);
      expect(env.session.batchCollection(1)!.type, CollectionType.done);
      expect(env.session.batchCollection(2)!.type, CollectionType.done);
      expect(env.session.batchCollection(3)!.type, CollectionType.doing);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('library-selected-count')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'batch schedule preview names the fixed season and preserves existing entries',
    (tester) async {
      final env = _Environment();
      await _show(tester, env);
      await _select(tester, 1);
      await _select(tester, 2);
      await tester.tap(find.text('加入新番表'));
      await tester.pumpAndSettle();
      expect(find.textContaining('预计加入 1 部，1 部已存在'), findsOneWidget);
      expect(find.textContaining('待安排'), findsWidgets);
      await tester.tap(find.text('确认执行（2）'));
      await tester.pumpAndSettle();
      expect(find.text('本机已保存 1'), findsOneWidget);
      expect(find.text('未修改 1'), findsOneWidget);
      final saved = env.store.schedules[env.season.id]!;
      expect(saved.items.first.note, '保留安排');
      expect(saved.items.first.weekday, 5);
      expect(saved.items.last.subjectId, 2);
      expect(saved.items.last.weekday, isNull);
      expect(env.queue.calls, 0);
    },
  );

  testWidgets('save failure leaves only failed items for retry', (
    tester,
  ) async {
    final env = _Environment()..queue.failingIds.add(2);
    await _show(tester, env);
    await _select(tester, 1);
    await _select(tester, 2);
    await tester.tap(find.text('改状态'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认执行（2）'));
    await tester.pumpAndSettle();
    expect(find.text('本机已保存 1'), findsOneWidget);
    expect(find.text('保存失败 1'), findsOneWidget);
    final calls = env.queue.calls;
    env.queue.failingIds.clear();
    await tester.tap(find.text('仅重试保存失败项'));
    await tester.pumpAndSettle();
    expect(env.queue.calls, calls + 1);
    expect(find.text('本机已保存 2'), findsOneWidget);
  });

  testWidgets(
    'network rejection is reported as sync failure without losing locally saved work',
    (tester) async {
      final env = _Environment();
      env.api.offline = false;
      env.api.rejectedIds.add(2);
      await _show(tester, env);
      await _select(tester, 1);
      await _select(tester, 2);
      await tester.tap(find.text('改状态'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认执行（2）'));
      await tester.pumpAndSettle();
      expect(find.text('本机已保存 2'), findsOneWidget);
      expect(find.text('保存失败 0'), findsOneWidget);
      expect(find.textContaining('1 项同步失败'), findsOneWidget);
      await tester.tap(find.text('查看问题'));
      await tester.pumpAndSettle();
      env.api.rejectedIds.clear();
      await tester.tap(find.text('重试').last);
      await tester.pumpAndSettle();
      expect(await env.queue.countFor('batch1'), 0);
      expect(env.api.replayed, hasLength(2));
    },
  );

  testWidgets('account switch clears selection and stops remaining bulk work', (
    tester,
  ) async {
    final env = _Environment();
    await _show(tester, env);
    await _select(tester, 1);
    await _select(tester, 2);
    await tester.tap(find.text('改状态'));
    await tester.pumpAndSettle();
    final gate = Completer<void>();
    env.queue.saveGate = gate.future;
    await tester.tap(find.text('确认执行（2）'));
    await tester.pump();
    env.session.switchUser(2);
    await tester.pump();
    expect(find.textContaining('登录已变化'), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(env.queue.calls, 1);
    expect(await env.queue.countFor('batch1'), 1);
    expect(await env.queue.countFor('batch2'), 0);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('library-selected-count')), findsNothing);
  });

  for (final width in [320.0, 390.0, 1200.0]) {
    for (final scale in [1.0, 1.8]) {
      for (final dark in [false, true]) {
        testWidgets('bulk collection UI $width scale $scale dark $dark', (
          tester,
        ) async {
          final env = _Environment();
          await _show(tester, env, width: width, scale: scale, dark: dark);
          await _select(tester, 1);
          await _select(tester, 2);
          await captureUx(
            tester,
            _boundary,
            'm5_selection_${width}_${scale}_$dark',
          );
          await tester.tap(find.text('改状态'));
          await tester.pumpAndSettle();
          await captureUx(
            tester,
            _boundary,
            'm5_status_${width}_${scale}_$dark',
          );
          await tester.tap(find.text('确认执行（2）'));
          await tester.pumpAndSettle();
          await captureUx(
            tester,
            _boundary,
            'm5_result_${width}_${scale}_$dark',
          );
          await tester.tap(find.text('完成'));
          await tester.pumpAndSettle();
          await _select(tester, 1);
          await _select(tester, 2);
          await tester.tap(find.text('加入新番表'));
          await tester.pumpAndSettle();
          await captureUx(
            tester,
            _boundary,
            'm5_schedule_${width}_${scale}_$dark',
          );
        });
      }
    }
  }
}

Future<void> _select(WidgetTester tester, int id) async {
  if (find.byKey(const ValueKey('library-selected-count')).evaluate().isEmpty) {
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey('library-selection-toggle')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('library-selection-toggle')));
    await tester.pumpAndSettle();
  }
  tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position
      .jumpTo(0);
  await tester.pump();
  final target = find.byKey(ValueKey('library-select-$id'));
  await tester.scrollUntilVisible(
    target,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

class _Environment {
  _Environment() {
    store.schedules[season.id] = SeasonSchedule(
      season: season,
      items: [
        ScheduleItem.fromSubject(
          api.server.first.subject,
          weekday: 5,
        ).copyWith(note: '保留安排', reminderEnabled: true),
      ],
    );
  }
  final api = BatchTestApi([
    for (var id = 1; id <= 5; id++) batchFixtureCollection(id),
  ]);
  final queue = MemoryBatchQueue();
  final store = MemorySchedules();
  final reminders = MemoryScheduleReminders();
  final season = SeasonKey.current();
  late final session = BatchTestSession(api, queue);
  late final schedule = ScheduleController(store, reminders);
}

Future<void> _show(
  WidgetTester tester,
  _Environment env, {
  double width = 390,
  double scale = 1,
  bool dark = false,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final theme = await uxTheme(tester, dark: dark);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWith((ref) => env.session),
        scheduleProvider.overrideWith((ref) => env.schedule),
      ],
      child: MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: RepaintBoundary(key: _boundary, child: child!),
        ),
        home: const Scaffold(
          body: LibraryPage(
            initialSubjectType: null,
            initialCollectionType: null,
            rememberFilters: false,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
