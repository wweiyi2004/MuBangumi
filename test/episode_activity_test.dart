import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/storage/bangumi_sync_store.dart';
import 'package:mubangumi/core/theme/app_theme.dart';
import 'package:mubangumi/core/theme/app_tokens.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/widgets/episode_activity_heatmap.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'support/ux_visuals.dart';

void main() {
  test(
    'specials use their real sort ordinal and never invent episode zero',
    () {
      final special = Episode.fromJson({
        'id': 1,
        'type': 1,
        'ep': 0,
        'sort': 3,
        'name_cn': '特典',
      });
      expect(special.number, 0);
      expect(special.gridLabel, 'SP3');
      expect(special.label, '特别篇 3');
      expect(Episode.fromJson({'type': 2, 'ep': 0, 'sort': 0}).gridLabel, 'OP');
      expect(
        Episode.fromJson({'type': 0, 'ep': 0, 'sort': 12.5}).gridLabel,
        '12.5',
      );
      expect(Episode.fromJson({'type': 0, 'ep': 3, 'sort': 4}).gridLabel, '3');
    },
  );
  test(
    'completion ledger coalesces repeated clicks and undo restores the original day',
    () async {
      var now = DateTime(2026, 10, 1);
      final store = BangumiSyncStore(
        databasePath: inMemoryDatabasePath,
        now: () => now,
      );
      addTearDown(store.close);
      Future<void> edit(
        int type,
        int before, {
        bool undo = false,
        String owner = 'alice',
        int episode = 7,
      }) => store.enqueue(
        username: owner,
        kind: BangumiMutationKind.episode,
        mutationKey: 'episode:$episode',
        payload: {
          'subject_id': 42,
          'episode_id': episode,
          'type': type,
          'activity_before': before,
          'activity_undo': undo,
        },
      );
      await edit(2, 0);
      await edit(2, 2);
      expect(await store.episodeActivityDays('alice'), {'2026-10-01': 1});
      expect(await store.pendingFor('alice'), hasLength(1));
      now = DateTime(2026, 10, 2);
      await edit(0, 2);
      expect(await store.episodeActivityDays('alice'), isEmpty);
      await edit(2, 0, undo: true);
      expect(await store.episodeActivityDays('alice'), {'2026-10-01': 1});
      await edit(2, 0, owner: 'bob');
      expect(await store.episodeActivityDays('bob'), {'2026-10-02': 1});
      expect(await store.episodeActivityDays('alice'), {'2026-10-01': 1});
      await edit(0, 2, episode: 8);
      await edit(2, 0, undo: true, episode: 8);
      expect(await store.episodeActivityDays('alice'), {'2026-10-01': 1});
    },
  );
  test('default primary actions use exact official Bangumi pink', () {
    expect(AppTheme.seed, AppPalette.bangumiPink);
    expect(AppPalette.bangumiPink, const Color(0xFFF09199));
    expect(AppTheme.light.colorScheme.primary, AppPalette.bangumiPink);
    expect(AppTheme.dark.colorScheme.primary, AppPalette.bangumiPink);
  });
  for (final width in [320.0, 520.0]) {
    testWidgets('activity calendar fits width $width at large text', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final today = DateTime(2026, 10, 1);
      final counts = {
        for (var i = 0; i < 150; i++)
          activityDayKey(today.subtract(Duration(days: i))): i % 12,
      };
      final key = GlobalKey();
      final theme = await uxTheme(tester, dark: false);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            episodeActivityProvider.overrideWith((ref) async => counts),
          ],
          child: MaterialApp(
            theme: theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.8)),
              child: child!,
            ),
            home: Scaffold(
              body: Center(
                child: RepaintBoundary(
                  key: key,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: EpisodeActivityHeatmap(today: today),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('每日追番'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await captureUx(tester, key, 'episode-heatmap-${width.toInt()}');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
