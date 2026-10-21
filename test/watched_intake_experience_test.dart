import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/bangumi_support.dart';
import 'package:mubangumi/core/onboarding/watched_catalog.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/screens/watched_intake_page.dart';
import 'package:mubangumi/state/session_controller.dart';
import 'package:mubangumi/state/watched_catalog_provider.dart';
import 'package:mubangumi/widgets/watched_intake_workspace.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'support/library_batch_fixtures.dart';
import 'support/ux_visuals.dart';

Subject _subject(int id, {String? title}) => Subject.fromJson({
  'id': id,
  'name_cn': title ?? '回忆中的第 $id 部番',
  'type': 2,
  'date': '2016-04-01',
  'eps': 12,
  'rating': {'score': 8.6, 'rank': id},
});

Future<void> _show(
  WidgetTester tester, {
  Future<List<Subject>> Function()? load,
  Future<List<RelatedSubject>> Function(int)? related,
  WatchedCatalog? catalog,
  BatchTestSession? session,
  double width = 390,
  double height = 780,
  double scale = 1,
  bool dark = false,
  GlobalKey? boundary,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fixtureSession =
      session ?? BatchTestSession(BatchTestApi([]), MemoryBatchQueue());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (catalog != null) watchedCatalogProvider.overrideWithValue(catalog),
        bangumiApiProvider.overrideWithValue(fixtureSession.api),
        sessionProvider.overrideWith((_) => fixtureSession),
      ],
      child: MaterialApp(
        theme: await uxTheme(tester, dark: dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: RepaintBoundary(key: boundary, child: child!),
        ),
        home: WatchedIntakePage(
          loadDeck: catalog == null
              ? (load ?? () async => [_subject(1), _subject(2)])
              : null,
          loadRelated: related ?? (_) async => [],
          clock: () => DateTime(2026, 10, 14),
        ),
      ),
    ),
  );
}

Future<void> _keep(WidgetTester tester) async {
  await tester.tap(find.text('看过'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 320));
  await tester.pump();
}

void main() {
  testWidgets(
    'intake batch does not overwrite a newer edit while another item is saving',
    (tester) async {
      final cache = _GatedSnapshot();
      final session = BatchTestSession(
        BatchTestApi([]),
        MemoryBatchQueue(),
        cache: cache,
      );
      await _show(tester, session: session);
      await tester.pumpAndSettle();
      await _keep(tester);
      await _keep(tester);
      await tester.tap(find.text('同步 2 部'));
      await tester.pump();
      final newer = session.changeCollection(
        _subject(2),
        CollectionType.wish,
        deferSync: true,
      );
      await tester.pump();
      cache.gate.complete();
      await newer;
      await tester.pumpAndSettle();
      expect(session.state.collectionFor(2)?.type, CollectionType.wish);
      expect(find.text('同步 1 部'), findsOneWidget);
      expect(find.textContaining('未覆盖新改动'), findsOneWidget);
    },
  );
  testWidgets('right swipe continues rightward through the exit animation', (
    tester,
  ) async {
    await _show(tester);
    await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('intake-card-1'));
    final before = tester.getTopLeft(card).dx;
    await tester.drag(card, const Offset(100, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getTopLeft(card).dx, greaterThan(before));
    await tester.pumpAndSettle();
    expect(find.text('回忆中的第 2 部番'), findsOneWidget);
  });
  testWidgets(
    'local intake acknowledgement releases the UI before slow network sync',
    (tester) async {
      final session = _SlowSyncSession();
      await _show(tester, session: session);
      await tester.pumpAndSettle();
      await _keep(tester);
      await tester.tap(find.text('同步 1 部'));
      await tester.pumpAndSettle();
      expect(session.state.collectionFor(1)?.type, CollectionType.done);
      expect(find.text('同步 0 部'), findsOneWidget);
      expect(find.text('回忆中的第 2 部番'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '看过'))
            .onPressed,
        isNotNull,
      );
      session.gate.complete();
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'poster preload bounds concurrency and skips intermediate card requests',
    (tester) async {
      final gate = Completer<void>();
      final urls = <String>[];
      Subject next(int id) => Subject(
        id: id,
        name: '',
        nameCn: '',
        summary: '',
        imageUrl: 'https://example.test/$id.jpg',
        episodeCount: 12,
        score: 8,
        rank: 1,
        date: '',
      );
      Future<void> showNext(int id) => tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 200,
              height: 300,
              child: WatchedIntakePreload(
                next: next(id),
                preload: (provider, _) async {
                  urls.add(
                    ((provider as ResizeImage).imageProvider
                            as CachedNetworkImageProvider)
                        .url,
                  );
                  if (urls.length == 1) await gate.future;
                },
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      await showNext(1);
      await tester.pump();
      await showNext(2);
      await tester.pump();
      await showNext(3);
      await tester.pump();
      expect(urls, ['https://example.test/1.jpg']);
      gate.complete();
      await tester.pumpAndSettle();
      expect(urls, [
        'https://example.test/1.jpg',
        'https://example.test/3.jpg',
      ]);
    },
  );
  test(
    'ready catalog pages appear before the rest; warm entry reuses them',
    () async {
      final first = Completer<List<Subject>>();
      var requests = 0;
      final catalog = WatchedCatalog(
        fetch: ({int? year, int offset = 0, int limit = 24}) {
          requests++;
          return first.future;
        },
      );
      final pending = catalog.load(2026).first;
      await Future<void>.delayed(Duration.zero);
      expect(requests, 2);
      first.complete([_subject(1)]);
      expect((await pending).subjects.single.id, 1);
      expect(catalog.cached.single.id, 1);
      expect((await catalog.load(2026).first).subjects.single.id, 1);
      expect(requests, 2);
    },
  );

  test(
    'concurrent entries share their first page; failed synchronous fetch can retry',
    () async {
      var requests = 0;
      final first = Completer<List<Subject>>();
      final catalog = WatchedCatalog(
        fetch: ({int? year, int offset = 0, int limit = 24}) {
          requests++;
          if (requests <= 2) throw StateError('offline');
          return first.future;
        },
      );
      expect((await catalog.load(2026).first).failed, isTrue);
      final a = catalog.load(2026).first;
      final b = catalog.load(2026).first;
      await Future<void>.delayed(Duration.zero);
      expect(requests, 4);
      first.complete([_subject(2)]);
      expect((await a).subjects.single.id, 2);
      expect((await b).subjects.single.id, 2);
    },
  );

  test(
    'expired pages refetch and another batch advances the catalog cursor',
    () async {
      var now = DateTime(2026);
      final offsets = <int>[];
      final catalog = WatchedCatalog(
        clock: () => now,
        fetch: ({int? year, int offset = 0, int limit = 24}) async {
          offsets.add(offset);
          return [_subject(offset + 1)];
        },
      );
      await catalog.load(2026).first;
      await Future<void>.delayed(Duration.zero);
      now = now.add(const Duration(minutes: 11));
      expect(catalog.cached, isEmpty);
      await catalog.load(2026).first;
      await catalog.load(2026, round: 1).first;
      expect(offsets, [0, 24, 0, 24, 72, 96]);
    },
  );

  test('a slow first request does not block a ready second page', () async {
    final slow = Completer<List<Subject>>();
    final catalog = WatchedCatalog(
      fetch: ({int? year, int offset = 0, int limit = 24}) {
        return offset == 0 ? slow.future : Future.value([_subject(2)]);
      },
    );
    final first = await catalog.load(2026).first;
    expect(first.subjects.single.id, 2);
    slow.complete([_subject(1)]);
    await Future<void>.delayed(Duration.zero);
  });

  testWidgets(
    'first card stays usable while the other catalog pages are slow',
    (tester) async {
      final slow = Completer<List<Subject>>();
      var requests = 0;
      final catalog = WatchedCatalog(
        fetch: ({int? year, int offset = 0, int limit = 24}) async {
          requests++;
          if (year == null && offset == 0) return [_subject(1), _subject(2)];
          return slow.future;
        },
      );
      await _show(tester, catalog: catalog);
      await tester.pump();
      await tester.pump();
      expect(find.text('回忆中的第 1 部番'), findsOneWidget);
      expect(find.text('继续为你找番 · 可以先挑选'), findsOneWidget);
      expect(requests, lessThanOrEqualTo(3));
      await _keep(tester);
      expect(find.text('回忆中的第 2 部番'), findsOneWidget);
      expect(find.text('同步 1 部'), findsOneWidget);
      slow.complete([]);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'network failure shows a retry instead of claiming no eligible anime',
    (tester) async {
      final key = GlobalKey();
      var requests = 0;
      await _show(
        tester,
        boundary: key,
        load: () async {
          requests++;
          if (requests == 1) throw StateError('offline');
          return [_subject(1)];
        },
      );
      await tester.pumpAndSettle();
      expect(find.text('候选暂时没能加载，请检查网络后重试'), findsOneWidget);
      await captureUx(tester, key, 'watched-intake-network-error');
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('回忆中的第 1 部番'), findsOneWidget);
    },
  );

  testWidgets(
    'entry loading has a stable card and gives way to the first title',
    (tester) async {
      final key = GlobalKey();
      final pending = Completer<List<Subject>>();
      await _show(tester, boundary: key, load: () => pending.future);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('正在找第一部番…'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await captureUx(tester, key, 'watched-intake-entry-loading');
      pending.complete([_subject(1)]);
      await tester.pumpAndSettle();
      expect(find.text('回忆中的第 1 部番'), findsOneWidget);
      expect(find.text('正在找第一部番…'), findsNothing);
    },
  );

  testWidgets('exhausted sample has a working next-batch action', (
    tester,
  ) async {
    final key = GlobalKey();
    var loads = 0;
    await _show(
      tester,
      boundary: key,
      load: () async => ++loads == 1 ? [] : [_subject(2)],
    );
    await tester.pumpAndSettle();
    expect(find.text('这叠牌抽完了'), findsOneWidget);
    await captureUx(tester, key, 'watched-intake-empty-sample');
    await tester.tap(find.text('再找一批'));
    await tester.pumpAndSettle();
    expect(find.text('回忆中的第 2 部番'), findsOneWidget);
  });

  testWidgets('undo restores a skipped card and a kept card', (tester) async {
    await _show(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('没看过'));
    await tester.pumpAndSettle();
    expect(find.text('回忆中的第 2 部番'), findsOneWidget);
    await tester.tap(find.byTooltip('撤销上一张'));
    await tester.pumpAndSettle();
    expect(find.text('回忆中的第 1 部番'), findsOneWidget);
    await _keep(tester);
    await tester.tap(find.byTooltip('撤销上一张'));
    await tester.pumpAndSettle();
    expect(find.text('回忆中的第 1 部番'), findsOneWidget);
    expect(find.text('同步 0 部'), findsOneWidget);
  });

  testWidgets('rapid repeated taps keep the same card only once', (
    tester,
  ) async {
    await _show(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('看过'));
    await tester.tap(find.text('看过'));
    await tester.pumpAndSettle();
    expect(find.text('同步 1 部'), findsOneWidget);
    expect(find.text('回忆中的第 2 部番'), findsOneWidget);
    await tester.tap(find.byTooltip('撤销上一张'));
    await tester.pumpAndSettle();
    expect(find.text('同步 0 部'), findsOneWidget);
  });

  testWidgets(
    'swipe feedback selects or skips without changing collection before sync',
    (tester) async {
      final api = BatchTestApi([]);
      final session = BatchTestSession(api, MemoryBatchQueue());
      await _show(tester, session: session);
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('intake-card-1')),
        const Offset(140, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('同步 1 部'), findsOneWidget);
      expect(session.state.collections, isEmpty);
      expect(api.replayed, isEmpty);
      await tester.drag(
        find.byKey(const ValueKey('intake-card-2')),
        const Offset(-140, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('这叠牌抽完了'), findsOneWidget);
      await tester.tap(find.byTooltip('撤销上一张'));
      await tester.pumpAndSettle();
      expect(find.text('回忆中的第 2 部番'), findsOneWidget);
    },
  );

  testWidgets('late related results do not replace the card being read', (
    tester,
  ) async {
    final related = Completer<List<RelatedSubject>>();
    await _show(tester, related: (_) => related.future);
    await tester.pumpAndSettle();
    await _keep(tester);
    related.complete(const [
      RelatedSubject(
        id: 99,
        name: 'Related',
        nameCn: '稍后到来的关联作品',
        imageUrl: '',
        relation: '续作',
        type: SubjectType.anime,
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('回忆中的第 2 部番'), findsOneWidget);
    expect(find.text('稍后到来的关联作品'), findsNothing);
    await tester.tap(find.text('没看过'));
    await tester.pumpAndSettle();
    expect(find.text('稍后到来的关联作品'), findsOneWidget);
  });

  testWidgets(
    'episode input validates boundaries and the review can remove a selection',
    (tester) async {
      await _show(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('看到第几集'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('看到第 1 / 12 话'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '13');
      await tester.tap(find.text('应用话数'));
      await tester.pumpAndSettle();
      expect(find.text('请输入 1–12 之间的整数'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), '7');
      await tester.tap(find.text('应用话数'));
      await tester.pumpAndSettle();
      expect(find.text('看到第 7 / 12 话'), findsOneWidget);
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('核对清单'));
      await tester.pumpAndSettle();
      expect(find.text('看到第 7 话'), findsOneWidget);
      await tester.tap(find.byTooltip('移出本次清单'));
      await tester.pumpAndSettle();
      expect(find.text('同步 0 部'), findsOneWidget);
      expect(find.text('回忆中的第 1 部番'), findsNothing);
    },
  );

  testWidgets('account change closes the review and discards old selections', (
    tester,
  ) async {
    final session = BatchTestSession(BatchTestApi([]), MemoryBatchQueue());
    await _show(tester, session: session);
    await tester.pumpAndSettle();
    await _keep(tester);
    await tester.tap(find.text('核对清单'));
    await tester.pumpAndSettle();
    session.switchUser(2);
    await tester.pumpAndSettle();
    expect(find.text('本次待同步清单'), findsNothing);
    expect(find.text('同步 0 部'), findsOneWidget);
  });

  testWidgets(
    'leaving protects unsaved picks and can explicitly discard them',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => WatchedIntakePage(
                        loadDeck: () async => [_subject(1), _subject(2)],
                        loadRelated: (_) async => [],
                      ),
                    ),
                  ),
                  child: const Text('进入补录'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('进入补录'));
      await tester.pumpAndSettle();
      await _keep(tester);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('还有未同步的挑选'), findsOneWidget);
      await tester.tap(find.text('继续挑选'));
      await tester.pumpAndSettle();
      expect(find.text('同步 1 部'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('放弃并离开'));
      await tester.pumpAndSettle();
      expect(find.text('进入补录'), findsOneWidget);
      expect(find.text('搬进看过的番'), findsNothing);
    },
  );

  for (final width in [320.0, 390.0, 1200.0]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.8]) {
        testWidgets('intake visual at $width dark=$dark scale=$scale', (
          tester,
        ) async {
          final key = GlobalKey();
          await _show(
            tester,
            width: width,
            height: width < 500 ? 740 : 800,
            scale: scale,
            dark: dark,
            boundary: key,
            load: () async => [
              _subject(1, title: '葬送的芙莉莲：旅途中还没有说完的故事'),
              _subject(2),
            ],
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await captureUx(tester, key, 'watched-intake-$width-$dark-$scale');
          await tester.tap(find.text('看到第几集'));
          await tester.pumpAndSettle();
          expect(find.text('看到第 1 / 12 话'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await captureUx(
            tester,
            key,
            'watched-intake-episode-$width-$dark-$scale',
          );
        });
      }
    }
  }

  testWidgets(
    'compact phone retains usable episode controls at large text size',
    (tester) async {
      final key = GlobalKey();
      await _show(tester, width: 320, height: 640, scale: 1.8, boundary: key);
      await tester.pumpAndSettle();
      await tester.tap(find.text('看到第几集'));
      await tester.pumpAndSettle();
      expect(find.text('看到第 1 / 12 话'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await captureUx(tester, key, 'watched-intake-compact-episode');
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('核对清单'));
      await tester.pumpAndSettle();
      expect(find.text('看到第 1 话'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await captureUx(tester, key, 'watched-intake-compact-review');
    },
  );
}

class _SlowSyncSession extends BatchTestSession {
  _SlowSyncSession() : super(BatchTestApi([]), MemoryBatchQueue());
  final gate = Completer<void>();
  @override
  Future<void> syncPendingChanges({bool retryBlocked = false}) => gate.future;
}

class _GatedSnapshot extends BatchTestCache {
  final gate = Completer<void>();
  @override
  Future<void> writeCollections(String username, List<UserCollection> items) =>
      gate.future;
}
