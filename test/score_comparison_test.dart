import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mubangumi/core/network/netaba_api.dart';
import 'package:mubangumi/screens/score_comparison_page.dart';
import 'package:mubangumi/state/session_controller.dart';
import 'support/pm_fixtures.dart';
import 'package:mubangumi/features/score_comparison/application/score_comparison_controller.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/models/netaba_models.dart';
import 'package:mubangumi/widgets/score_comparison_chart.dart';
import 'support/ux_visuals.dart';

Subject _subject(int id) => Subject.fromJson({'id': id, 'name_cn': '测试作品 $id'});
NetabaSubjectHistory _history(double score) => NetabaSubjectHistory(
  subject: const NetabaSubjectInfo(name: '', nameCn: ''),
  history: [
    NetabaHistoryPoint(recordedAt: DateTime(2026, 1, 1), score: score),
    NetabaHistoryPoint(recordedAt: DateTime(2026, 2, 1), score: score + .2),
  ],
);
void main() {
  testWidgets(
    'comparison picker reaches off-ranking collections and rejects a changed owner',
    (tester) async {
      final session = _ComparisonSession();
      final api = _HistorySource();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWith((ref) => session),
            netabaApiProvider.overrideWithValue(api),
          ],
          child: MaterialApp(
            home: ScoreComparisonPage(initial: [_subject(1), _subject(2)]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(api.requested.toSet(), {1, 2});
      await tester.tap(find.text('选择作品'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('测试作品 3'));
      await tester.pumpAndSettle();
      expect(api.requested.toSet(), {1, 2, 3});
      expect(find.text('数据源尚未收录此作品的历史评分'), findsOneWidget);
      await tester.tap(find.text('选择作品'));
      await tester.pumpAndSettle();
      session.switchUser(2);
      await tester.pumpAndSettle();
      expect(find.text('账号已变化，返回重新选择'), findsOneWidget);
      expect(find.text('测试作品 1'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'independent histories retain good data when another subject is missing',
    () async {
      final controller = ScoreComparisonController((id) async {
        if (id == 2) throw StateError('404');
        return _history(8);
      });
      addTearDown(controller.dispose);
      await Future.wait([
        controller.add(_subject(1)),
        controller.add(_subject(2)),
      ]);
      expect(controller.entries.first.history!.history, hasLength(2));
      expect(controller.entries.last.error, contains('尚未收录'));
    },
  );
  test('removing and readding never accepts the previous request', () async {
    final old = Completer<NetabaSubjectHistory>();
    var calls = 0;
    final controller = ScoreComparisonController(
      (id) => ++calls == 1 ? old.future : Future.value(_history(9)),
    );
    addTearDown(controller.dispose);
    final first = controller.add(_subject(1));
    controller.remove(1);
    await controller.add(_subject(1));
    old.complete(_history(4));
    await first;
    expect(controller.entries.single.history!.history.first.score, 9);
  });
  test(
    'account reset drops outstanding histories and caps selection at six',
    () async {
      final old = Completer<NetabaSubjectHistory>();
      final controller = ScoreComparisonController((id) => old.future);
      addTearDown(controller.dispose);
      final pending = controller.add(_subject(1));
      controller.reset();
      old.complete(_history(8));
      await pending;
      expect(controller.entries, isEmpty);
      for (var id = 1; id <= 7; id++) {
        await controller.add(_subject(id));
      }
      expect(controller.entries, hasLength(6));
    },
  );
  testWidgets(
    'uneven date series share one plot and expose actual sampled values',
    (tester) async {
      final key = GlobalKey();
      final theme = await uxTheme(tester, dark: false);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: RepaintBoundary(
              key: key,
              child: ColoredBox(
                color: theme.scaffoldBackgroundColor,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: ScoreComparisonChart(
                    lines: [
                      ScoreComparisonLine('星际牛仔', [
                        NetabaChartPoint(DateTime(2026, 1, 1), 8.8),
                        NetabaChartPoint(DateTime(2026, 3, 1), 9.1),
                      ], const Color(0xFFE34F87)),
                      ScoreComparisonLine('测试作品', [
                        NetabaChartPoint(DateTime(2026, 2, 1), 7.7),
                        NetabaChartPoint(DateTime(2026, 3, 1), 8.2),
                      ], const Color(0xFF377CC8)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2026/1/1'), findsOneWidget);
      expect(find.text('2026/3/1'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('score-comparison-plot')));
      await tester.pump();
      expect(find.textContaining('星际牛仔'), findsOneWidget);
      expect(find.textContaining('测试作品'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await captureUx(tester, key, 'multi-score-comparison');
    },
  );
}

class _ComparisonSession extends PmTestSession {
  _ComparisonSession() {
    state = state.copyWith(
      collections: [
        for (var id = 1; id <= 3; id++)
          UserCollection(
            subjectId: id,
            type: CollectionType.done,
            rate: 8,
            episodeStatus: 12,
            updatedAt: null,
            subject: _subject(id),
          ),
      ],
    );
  }
}

class _HistorySource extends NetabaApi {
  final requested = <int>[];
  @override
  Future<NetabaSubjectHistory> getSubjectHistory(int id) async {
    requested.add(id);
    if (id == 3) throw StateError('404');
    return _history(7 + id.toDouble());
  }
}
