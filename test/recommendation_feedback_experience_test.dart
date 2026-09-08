import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/bangumi_api.dart';
import 'package:mubangumi/core/storage/browsing_store.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/models/recommendation_feedback.dart';
import 'package:mubangumi/screens/fan_recommend_page.dart';
import 'package:mubangumi/state/session_controller.dart';

import 'support/memory_recommendation_feedback.dart';
import 'support/progress_fixtures.dart';
import 'support/ux_visuals.dart';

final _boundary = GlobalKey();
const _firstTitle = '星际旅途：在遥远的星海中寻找故乡的少年';

void main() {
  testWidgets(
    'restore failure remains visible and retry works on a short phone screen',
    (tester) async {
      final env = _Environment();
      await _show(tester, env, width: 320, height: 640, scale: 1.8);
      await _run(tester);
      await _hide(tester, 100);
      env.repository.failedSubjects.add(100);
      await tester.tap(find.byTooltip('不感兴趣的作品'));
      await tester.pumpAndSettle();
      await _restore(tester, 100);
      final sheet = find.byType(BottomSheet);
      expect(
        find.descendant(of: sheet, matching: find.textContaining('未能恢复')),
        findsOneWidget,
      );
      env.repository.failedSubjects.clear();
      final retry = find.descendant(of: sheet, matching: find.text('重试保存'));
      await tester.ensureVisible(retry);
      await tester.pump();
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(find.text('没有隐藏的作品'), findsOneWidget);
    },
  );
  testWidgets(
    'an old account feedback load cannot hide a new accounts recommendations',
    (tester) async {
      final pending = Completer<List<HiddenRecommendation>>();
      final env = _Environment()..repository.pendingRead = pending.future;
      await _show(tester, env);
      env.repository.pendingRead = null;
      env.session.switchUser(2);
      await tester.pumpAndSettle();
      pending.complete([
        HiddenRecommendation.fromSubject(env.api.candidates.first),
      ]);
      await tester.pumpAndSettle();
      await _run(tester);
      expect(find.byKey(const ValueKey('recommendation-100')), findsOneWidget);
    },
  );

  testWidgets('a late network result does not replace a new accounts results', (
    tester,
  ) async {
    final env = _Environment();
    final pending = Completer<List<Subject>>();
    env.api.pending = pending.future;
    await _show(tester, env);
    await _run(tester, settle: false);
    env.api.pending = null;
    env.session.switchUser(2);
    await tester.pumpAndSettle();
    await _run(tester);
    pending.complete([_subject(999, '旧账号迟到候选')]);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('recommendation-100')), findsOneWidget);
    expect(find.text('旧账号迟到候选'), findsNothing);
  });

  testWidgets('restoring an already collected subject keeps it excluded', (
    tester,
  ) async {
    final env = _Environment();
    await _show(tester, env);
    await _run(tester);
    await _hide(tester, 100);
    env.session.collect(env.api.candidates.first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('不感兴趣的作品'));
    await tester.pumpAndSettle();
    await _restore(tester, 100);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('recommendation-100')), findsNothing);
    expect(find.byKey(const ValueKey('recommendation-101')), findsOneWidget);
  });

  testWidgets(
    'guest feedback needs no extra login and stays separate from a signed-in account',
    (tester) async {
      final env = _Environment()..session.guest();
      await _show(tester, env);
      await tester.tap(find.text('说出需求'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '治愈');
      await _run(tester);
      expect(tester.testTextInput.isVisible, isFalse);
      await _hide(tester, 100);
      expect(env.repository.records[0]!.keys, [100]);
      env.session.switchUser(1);
      await tester.pumpAndSettle();
      await _run(tester);
      await _reveal(tester, find.byKey(const ValueKey('recommendation-100')));
      expect(find.byKey(const ValueKey('recommendation-100')), findsOneWidget);
      expect(env.repository.records[1], isNull);
    },
  );
  testWidgets(
    'hide removes a recommendation immediately and reruns keep excluding it',
    (tester) async {
      final env = _Environment();
      await _show(tester, env);
      await _run(tester);
      final gate = Completer<void>();
      env.repository.pendingWrite = gate.future;
      await _hide(tester, 100, settle: false);
      expect(find.byKey(const ValueKey('recommendation-100')), findsNothing);
      gate.complete();
      await tester.pumpAndSettle();
      await _run(tester);
      expect(find.byKey(const ValueKey('recommendation-100')), findsNothing);
      expect(find.byKey(const ValueKey('recommendation-101')), findsOneWidget);
      expect(env.repository.records[1]!.keys, [100]);
    },
  );

  testWidgets(
    'a rebuilt page loads hidden IDs and restoring brings eligible candidates back',
    (tester) async {
      final env = _Environment();
      await _show(tester, env);
      await _run(tester);
      await _hide(tester, 100);
      await tester.pumpWidget(const SizedBox.shrink());
      final restarted = _Environment(repository: env.repository);
      await _show(tester, restarted);
      await _run(tester);
      expect(find.byKey(const ValueKey('recommendation-100')), findsNothing);
      await tester.tap(find.byTooltip('不感兴趣的作品'));
      await tester.pumpAndSettle();
      await _restore(tester, 100);
      expect(find.text('没有隐藏的作品'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('recommendation-100')), findsOneWidget);
      expect(env.repository.records[1], isEmpty);
    },
  );

  testWidgets(
    'hiding every candidate offers recovery without changing selected tags',
    (tester) async {
      final env = _Environment();
      await _show(tester, env);
      await _run(tester);
      await _hide(tester, 100);
      await _hide(tester, 101);
      expect(find.text('本次候选已全部隐藏，可以恢复作品或重新推荐'), findsOneWidget);
      expect(find.text('恢复隐藏作品'), findsOneWidget);
      expect(find.textContaining('放宽评分'), findsNothing);
      await tester.tap(find.text('恢复隐藏作品'));
      await tester.pumpAndSettle();
      await _restore(tester, 100);
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(find.text('本次候选已全部隐藏，可以恢复作品或重新推荐'), findsNothing);
      expect(find.byKey(const ValueKey('recommendation-100')), findsOneWidget);
    },
  );

  testWidgets(
    'saved exclusions also filter a delayed recommendation response',
    (tester) async {
      final env = _Environment();
      await _show(tester, env);
      await _run(tester);
      final gate = Completer<List<Subject>>();
      env.api.pending = gate.future;
      await _run(tester, settle: false);
      await _hide(tester, 100, settle: false);
      gate.complete(env.api.candidates);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('recommendation-100')), findsNothing);
      expect(find.byKey(const ValueKey('recommendation-101')), findsOneWidget);
    },
  );

  testWidgets(
    'switching accounts hides the old management list and keeps feedback separate',
    (tester) async {
      final env = _Environment();
      await _show(tester, env);
      await _run(tester);
      await _hide(tester, 100);
      await tester.tap(find.byTooltip('不感兴趣的作品'));
      await tester.pumpAndSettle();
      env.session.switchUser(2);
      await tester.pumpAndSettle();
      expect(find.text('账号已变化，请关闭后重新打开'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('hidden-recommendation-100')),
        findsNothing,
      );
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      await _run(tester);
      expect(find.byKey(const ValueKey('recommendation-100')), findsOneWidget);
      expect(env.repository.records[1]!.keys, [100]);
      expect(env.repository.records[2], isNull);
    },
  );

  testWidgets(
    'read failure blocks recommendation until feedback can be restored',
    (tester) async {
      final env = _Environment()..repository.failRead = true;
      await _show(tester, env);
      await _reveal(tester, find.text('开始推荐'), fromTop: true);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '开始推荐'))
            .onPressed,
        isNull,
      );
      expect(env.api.searches, 0);
      env.repository.failRead = false;
      await tester.tap(find.text('重新读取'));
      await tester.pumpAndSettle();
      await _run(tester);
      expect(find.byKey(const ValueKey('recommendation-100')), findsOneWidget);
    },
  );

  testWidgets(
    'failed hide restores the card and retry persists the same feedback',
    (tester) async {
      final env = _Environment()..repository.failedSubjects.add(100);
      await _show(tester, env);
      await _run(tester);
      await _hide(tester, 100);
      expect(find.byKey(const ValueKey('recommendation-100')), findsOneWidget);
      expect(find.text('重试保存'), findsOneWidget);
      env.repository.failedSubjects.clear();
      await _reveal(tester, find.text('重试保存'));
      await tester.tap(find.text('重试保存'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('recommendation-100')), findsNothing);
    },
  );

  testWidgets(
    'restoring feedback preserves partial loading notices and owned-item exclusions',
    (tester) async {
      final env = _Environment()..api.mode = 'partial';
      await _show(tester, env);
      await _run(tester);
      await _hide(tester, 100);
      expect(find.text('部分内容未能加载，当前推荐可能不完整'), findsOneWidget);
      env.session.collect(env.api.candidates.last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('recommendation-101')), findsNothing);
      await tester.tap(find.byTooltip('不感兴趣的作品'));
      await tester.pumpAndSettle();
      await _restore(tester, 100);
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('recommendation-100')), findsOneWidget);
      expect(find.byKey(const ValueKey('recommendation-101')), findsNothing);
      expect(find.text('部分内容未能加载，当前推荐可能不完整'), findsOneWidget);
    },
  );

  for (final width in [320.0, 390.0, 1200.0]) {
    for (final scale in [1.0, 1.8]) {
      for (final dark in [false, true]) {
        testWidgets('recommendation feedback $width scale $scale dark $dark', (
          tester,
        ) async {
          final env = _Environment();
          await _show(tester, env, width: width, scale: scale, dark: dark);
          await _run(tester);
          await _reveal(
            tester,
            find.byKey(const ValueKey('recommendation-100')),
          );
          await tester.pumpAndSettle();
          await captureUx(
            tester,
            _boundary,
            'm4_results_${width}_${scale}_$dark',
          );
          await _hide(tester, 100);
          await tester.tap(find.byTooltip('不感兴趣的作品'));
          await tester.pumpAndSettle();
          await captureUx(
            tester,
            _boundary,
            'm4_hidden_${width}_${scale}_$dark',
          );
          await _restore(tester, 100);
          expect(find.text('没有隐藏的作品'), findsOneWidget);
        });
      }
    }
  }
}

Future<void> _reveal(
  WidgetTester tester,
  Finder target, {
  bool fromTop = false,
}) async {
  if (fromTop || target.evaluate().isEmpty) {
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pump();
    await tester.scrollUntilVisible(
      target,
      250,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(target);
  await tester.pump();
}

Future<void> _run(WidgetTester tester, {bool settle = true}) async {
  await _reveal(tester, find.text('开始推荐'), fromTop: true);
  await tester.tap(find.text('开始推荐'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _hide(WidgetTester tester, int id, {bool settle = true}) async {
  final button = find.descendant(
    of: find.byKey(ValueKey('recommendation-$id')),
    matching: find.text('不感兴趣'),
  );
  await _reveal(tester, button);
  await tester.tap(button);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _restore(WidgetTester tester, int id) async {
  final button = find.descendant(
    of: find.byKey(ValueKey('hidden-recommendation-$id')),
    matching: find.text('恢复'),
  );
  await _reveal(tester, button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

class _Environment {
  _Environment({MemoryRecommendationFeedback? repository})
    : repository = repository ?? MemoryRecommendationFeedback();
  final MemoryRecommendationFeedback repository;
  final api = _Api();
  final session = _Session();
}

class _Session extends ProgressSession {
  _Session() : super(ProgressApi(), ProgressCache());
  @override
  void switchUser(int id) {
    super.switchUser(id);
    state = state.copyWith(collections: [_collection(_subject(1, '喜欢的作品'))]);
  }

  void collect(Subject subject) => state = state.copyWith(
    collections: [...state.collections, _collection(subject)],
  );
  void guest() => state = const SessionState(phase: SessionPhase.signedOut);
}

class _Api extends BangumiApi {
  final candidates = [_subject(100, _firstTitle), _subject(101, '温暖的日常故事')];
  Future<List<Subject>>? pending;
  String mode = 'success';
  int searches = 0;
  @override
  Future<List<Subject>> searchSubjects(
    String keyword, {
    int limit = 24,
    int offset = 0,
    String sort = 'match',
    int minimumRating = 0,
    int startYear = 0,
    List<String> tags = const [],
    List<String> metaTags = const [],
    SubjectType subjectType = SubjectType.anime,
  }) async {
    searches++;
    if (mode == 'failure' || (mode == 'partial' && searches > 1)) {
      throw StateError('offline');
    }
    return pending ?? candidates;
  }

  @override
  Future<List<Subject>> browseSubjects({
    required SubjectType type,
    int? year,
    int? month,
    String sort = 'rank',
    int limit = 24,
    int offset = 0,
  }) async {
    if (mode != 'success') throw StateError('offline');
    return candidates;
  }
}

Subject _subject(int id, String name) => Subject(
  id: id,
  name: name,
  nameCn: '',
  imageUrl: '',
  summary: '',
  episodeCount: 12,
  score: 8.5,
  rank: id,
  date: '2026-01-01',
  tags: const ['治愈', '日常'],
);
UserCollection _collection(Subject subject) => UserCollection(
  subjectId: subject.id,
  type: CollectionType.doing,
  rate: 9,
  episodeStatus: 0,
  updatedAt: null,
  subject: subject,
);

Future<void> _show(
  WidgetTester tester,
  _Environment env, {
  double width = 390,
  double height = 1000,
  double scale = 1,
  bool dark = false,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final theme = await uxTheme(tester, dark: dark);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        sessionProvider.overrideWith((ref) => env.session),
        bangumiApiProvider.overrideWithValue(env.api),
        recommendationFeedbackRepositoryProvider.overrideWithValue(
          env.repository,
        ),
      ],
      child: MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: RepaintBoundary(key: _boundary, child: child!),
        ),
        home: const FanRecommendPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
