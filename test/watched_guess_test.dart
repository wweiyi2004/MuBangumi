import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/bangumi_support.dart';
import 'package:mubangumi/core/onboarding/watched_guess.dart';
import 'package:mubangumi/core/theme/app_theme.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/screens/watched_intake_page.dart';
import 'package:mubangumi/state/session_controller.dart';

import 'support/library_batch_fixtures.dart';

Subject _subject(
  int id,
  int rank, {
  int year = 2016,
  int eps = 12,
  List<String> tags = const [],
  String? name,
}) => Subject.fromJson({
  'id': id,
  'type': 2,
  'name': name ?? '作品$id',
  'name_cn': name ?? '作品$id',
  'date': '$year-04-01',
  'eps': eps,
  'rating': {'rank': rank, 'score': 8},
  'tags': [
    for (final tag in tags) {'name': tag},
  ],
});

WatchedCandidate _candidate(
  int id,
  int rank, {
  int year = 2016,
  List<String> tags = const [],
  String? name,
}) => WatchedCandidate.fromSubject(
  _subject(id, rank, year: year, tags: tags, name: name),
);

void main() {
  test('sample years include both ends and a stride of three', () {
    expect(watchedGuessSampleYears(2015, 2026), [2015, 2018, 2021, 2024, 2026]);
    expect(watchedGuessSampleYears(2026, 2026), [2026]);
  });

  test('already collected titles stay out of the deck', () {
    final ranker = WatchedGuessRanker()
      ..add(_candidate(1, 1, name: '已经看过'))
      ..add(_candidate(2, 2, name: '还没记'));
    ranker.excludeOwned([1]);
    ranker.accept(
      _candidate(2, 2, name: '还没记'),
      related: [_candidate(1, 1, name: '已经看过')],
    );
    expect(
      ranker.next().map((guess) => guess.candidate.id),
      isNot(contains(1)),
    );
    expect(ranker.owns(1), isTrue);
  });

  test('ranked canon comes before unranked titles', () {
    final ranker = WatchedGuessRanker()
      ..add(_candidate(2, 20))
      ..add(_candidate(1, 3))
      ..add(const WatchedCandidate(id: 9, name: '未排名'));
    expect(ranker.next().map((guess) => guess.candidate.id), [1, 2, 9]);
    expect(ranker.next().first.reason, '2016 年高排名');
  });

  test('a watched title pulls its relatives ahead of the remaining canon', () {
    final ranker = WatchedGuessRanker()
      ..add(_candidate(1, 1, name: '进击的巨人'))
      ..add(_candidate(2, 2));
    ranker.accept(
      _candidate(1, 1, name: '进击的巨人'),
      related: const [WatchedCandidate(id: 8, name: '死亡笔记', nameCn: '死亡笔记')],
    );
    final next = ranker.next();
    expect(next.first.candidate.displayName, '死亡笔记');
    expect(next.first.reason, '和进击的巨人相近');
    expect(next.map((guess) => guess.candidate.id), isNot(contains(1)));
  });

  test(
    'three misses in a row cool that tag without hiding a direct relative',
    () {
      final ranker = WatchedGuessRanker()
        ..add(_candidate(11, 30, name: '已看过', tags: const ['音乐']));
      ranker.accept(_candidate(11, 30, name: '已看过', tags: const ['音乐']));
      for (var id = 1; id <= 4; id++) {
        ranker.add(_candidate(id, id, tags: const ['热血']));
      }
      ranker
        ..add(_candidate(5, 50, tags: const ['治愈']))
        ..add(_candidate(6, 60, tags: const ['悬疑']))
        ..add(_candidate(7, 70, tags: const ['推理']))
        ..add(_candidate(8, 80, tags: const ['恋爱']))
        ..add(_candidate(9, 90, tags: const ['科幻']))
        ..add(_candidate(10, 100, tags: const ['校园']));
      for (var id = 1; id <= 3; id++) {
        ranker.reject(_candidate(id, id, tags: const ['热血']));
      }
      expect(ranker.next().first.candidate.id, 5);
      ranker.noteRelated(11, [
        _candidate(4, 4, name: '热血续作', tags: const ['热血']),
      ]);
      final next = ranker.next().first;
      expect(next.candidate.id, 4);
      expect(next.reason, '和已看过相近');
    },
  );

  test('accepting breaks a reject streak', () {
    final ranker = WatchedGuessRanker()
      ..add(_candidate(1, 1, tags: const ['热血']))
      ..add(_candidate(2, 2, tags: const ['热血']))
      ..add(_candidate(3, 3, tags: const ['治愈']))
      ..add(_candidate(4, 4, tags: const ['热血']))
      ..add(_candidate(6, 6, tags: const ['热血']))
      ..add(_candidate(5, 40, tags: const ['音乐']))
      ..add(_candidate(7, 50, tags: const ['悬疑']))
      ..add(_candidate(8, 60, tags: const ['推理']))
      ..add(_candidate(9, 70, tags: const ['恋爱']))
      ..add(_candidate(10, 80, tags: const ['科幻']));
    ranker
      ..reject(_candidate(1, 1, tags: const ['热血']))
      ..reject(_candidate(2, 2, tags: const ['热血']))
      ..accept(_candidate(3, 3, tags: const ['治愈']))
      ..reject(_candidate(6, 6, tags: const ['热血']));
    expect(ranker.next().first.candidate.id, 4);
  });

  testWidgets('a kept card joins the pile and the next guess is drawn', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith(
            (_) => BatchTestSession(BatchTestApi([]), MemoryBatchQueue()),
          ),
        ],
        child: MaterialApp(
          home: WatchedIntakePage(
            loadDeck: () async => [
              _subject(1, 1, name: '进击的巨人'),
              _subject(2, 2, name: '未看过的番'),
            ],
            loadRelated: (id) async => id == 1
                ? const [
                    RelatedSubject(
                      id: 8,
                      name: 'Death Note',
                      nameCn: '死亡笔记',
                      imageUrl: '',
                      relation: '相似',
                      type: SubjectType.anime,
                    ),
                  ]
                : const [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('猜你看过'), findsOneWidget);
    expect(find.text('进击的巨人'), findsOneWidget);
    expect(find.text('2016 年高排名'), findsOneWidget);
    await tester.tap(find.text('看过'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('死亡笔记'), findsOneWidget);
    expect(find.text('和进击的巨人相近'), findsOneWidget);
    expect(find.text('待同步 1 部'), findsOneWidget);
    expect(find.text('同步 1 部'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('episode progress is confirmed onto the kept pile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith(
            (_) => BatchTestSession(BatchTestApi([]), MemoryBatchQueue()),
          ),
        ],
        child: MaterialApp(
          home: WatchedIntakePage(
            loadDeck: () async => [
              _subject(1, 1, name: '进击的巨人'),
              _subject(2, 2, name: '下一张'),
            ],
            loadRelated: (_) async => const [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('看到第几集'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();
    expect(find.text('看到第 3 / 12 话'), findsOneWidget);
    await tester.tap(find.text('确认'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('下一张'), findsOneWidget);
    expect(find.text('待同步 1 部'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'syncing finished and partial cards updates local progress and replays episode batch',
    (tester) async {
      tester.view.physicalSize = const Size(800, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      final api = BatchTestApi([])..offline = false;
      final queue = MemoryBatchQueue();
      final session = BatchTestSession(api, queue);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bangumiApiProvider.overrideWithValue(api),
            sessionProvider.overrideWith((_) => session),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: WatchedIntakePage(
              loadDeck: () async => [
                _subject(1, 1, name: '全看完了', eps: 12),
                _subject(2, 2, name: '看了一集', eps: 12),
              ],
              loadRelated: (_) async => const [],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('看过'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      await tester.tap(find.text('看到第几集'));
      await tester.pump();
      await tester.tap(find.text('确认'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(find.text('同步 2 部'), findsOneWidget);
      await tester.tap(find.text('同步 2 部'));
      await tester.pumpAndSettle();

      final done = session.state.collectionFor(1)!;
      final doing = session.state.collectionFor(2)!;
      expect(done.type, CollectionType.done);
      expect(done.episodeStatus, 12);
      expect(doing.type, CollectionType.doing);
      expect(doing.episodeStatus, 1);
      expect(api.episodeUpdates, [
        [101, 102],
        [201],
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'switching account clears kept pile and ignores late deck from previous account',
    (tester) async {
      tester.view.physicalSize = const Size(800, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      final api = BatchTestApi([]);
      final queue = MemoryBatchQueue();
      final session = BatchTestSession(api, queue);
      final firstRelated = Completer<List<RelatedSubject>>();
      var loadCalls = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bangumiApiProvider.overrideWithValue(api),
            sessionProvider.overrideWith((_) => session),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: WatchedIntakePage(
              loadDeck: () async {
                loadCalls++;
                return loadCalls == 1
                    ? [_subject(1, 1, name: '账号一的番')]
                    : [_subject(2, 1, name: '账号二的番')];
              },
              loadRelated: (_) => firstRelated.future,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('账号一的番'), findsOneWidget);

      await tester.tap(find.text('看过'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('待同步 1 部'), findsOneWidget);

      session.switchUser(2);
      await tester.pumpAndSettle();

      firstRelated.complete(const [
        RelatedSubject(
          id: 99,
          name: 'Stale',
          nameCn: '旧账号关联番',
          imageUrl: '',
          relation: '相似',
          type: SubjectType.anime,
        ),
      ]);
      await tester.pumpAndSettle();

      expect(find.text('账号二的番'), findsOneWidget);
      expect(find.text('旧账号关联番'), findsNothing);
      expect(find.text('本次挑选'), findsOneWidget);
      expect(find.text('同步 0 部'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 1200.0]) {
    for (final scale in [1.0, 1.8]) {
      testWidgets(
        'intake layout fits at width $width and text scale $scale without overflow',
        (tester) async {
          tester.view.physicalSize = Size(width, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                sessionProvider.overrideWith(
                  (_) => BatchTestSession(BatchTestApi([]), MemoryBatchQueue()),
                ),
              ],
              child: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: MaterialApp(
                  theme: scale > 1 ? AppTheme.dark : AppTheme.light,
                  home: WatchedIntakePage(
                    loadDeck: () async => [
                      _subject(1, 1, name: '名字特别长的经典动画作品测试标题'),
                    ],
                    loadRelated: (_) async => const [],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          await tester.tap(find.text('看到第几集'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
