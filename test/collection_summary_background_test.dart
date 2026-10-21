import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/insights/collection_summary.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/screens/collection_stats_page.dart';

List<UserCollection> fixture(int count) => [
  for (var i = 0; i < count; i++)
    UserCollection(
      subjectId: i + 1,
      type: CollectionType.done,
      rate: 8,
      episodeStatus: 12,
      updatedAt: DateTime(2020, i % 12 + 1),
      subject: Subject(
        id: i + 1,
        name: 'entry',
        nameCn: '',
        imageUrl: '',
        summary: '',
        episodeCount: 12,
        score: 8,
        rank: 1,
        date: '2020-01-01',
        type: i.isEven ? SubjectType.anime : SubjectType.book,
      ),
    ),
];

void main() {
  test(
    'background export preserves schema, Unicode, privacy and source counts',
    () async {
      final values = fixture(600);
      final bytes = await compute(encodeCollectionExport, (
        at: DateTime(2026),
        username: '合成账号',
        items: values,
        coverage: null,
      ));
      final data = jsonDecode(utf8.decode(bytes)) as Map;
      expect(data['schema_version'], 1);
      expect(data['username'], '合成账号');
      expect(data['count'], 600);
      expect(data['collections'], hasLength(600));
      expect(
        (data['collections'] as List).first,
        containsPair('subject_id', 1),
      );
      expect(
        (data['collections'] as List).first,
        containsPair('private', false),
      );
    },
  );
  testWidgets(
    'large summaries coalesce rapid filter changes and show the latest result only',
    (tester) async {
      final requests = <CollectionSummaryInput>[],
          gates = <Completer<CollectionSummary>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: CollectionStatsPage(
            username: 'alice',
            collections: fixture(1000),
            computeSummary: (input) {
              requests.add(input);
              final gate = Completer<CollectionSummary>();
              gates.add(gate);
              return gate.future;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '动画'));
      await tester.pump();
      await tester.tap(find.widgetWithText(ChoiceChip, '书籍'));
      await tester.pump();
      expect(requests, hasLength(1));
      gates.first.complete(summarizeCollections(requests.first));
      await tester.pumpAndSettle();
      expect(requests, hasLength(2));
      expect(requests.last.type, SubjectType.book);
      gates.last.complete(summarizeCollections(requests.last));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, -350));
      await tester.pumpAndSettle();
      expect(find.text('当前已完成 500'), findsOneWidget);
      expect(find.text('当前已完成 1000'), findsNothing);
    },
  );
  testWidgets(
    'an old account summary cannot replace the new account small snapshot',
    (tester) async {
      final gate = Completer<CollectionSummary>();
      late CollectionSummaryInput old;
      await tester.pumpWidget(
        MaterialApp(
          home: CollectionStatsPage(
            username: 'alice',
            collections: fixture(1000),
            computeSummary: (input) {
              old = input;
              return gate.future;
            },
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: CollectionStatsPage(username: 'bob', collections: fixture(2)),
        ),
      );
      gate.complete(summarizeCollections(old));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, -350));
      await tester.pumpAndSettle();
      expect(find.text('当前已完成 1000'), findsNothing);
      expect(find.text('当前已完成 2'), findsOneWidget);
    },
  );
  test(
    'annual month counts and default year are computed from the selected type',
    () {
      final summary = summarizeCollections((
        collections: fixture(1200),
        type: SubjectType.anime,
        year: null,
        currentYear: 2026,
      ));
      expect(summary.items, hasLength(600));
      expect(summary.review.year, 2020);
      expect(
        summary.review.months.fold<int>(0, (total, count) => total + count),
        600,
      );
    },
  );
}
