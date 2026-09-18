import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/bangumi_api.dart';
import 'package:mubangumi/core/network/bangumi_support.dart';
import 'package:mubangumi/features/schedule/application/schedule_search_controller.dart';
import 'package:mubangumi/models/bangumi_models.dart';

import 'support/progress_fixtures.dart';

void main() {
  late _SearchApi api;
  late ScheduleSearchController controller;
  setUp(() {
    api = _SearchApi();
    controller = ScheduleSearchController(api: () => api);
  });
  tearDown(() => controller.dispose());

  testWidgets('typing debounces and Enter cancels the pending duplicate', (
    tester,
  ) async {
    controller.changeQuery('old');
    await tester.pump(const Duration(milliseconds: 300));
    controller.changeQuery(' new ');
    await tester.pump(const Duration(milliseconds: 399));
    expect(api.searches, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(api.searches.single.keyword, 'new');
    api.searches.single.result.complete([progressCollection(1).subject]);
    await tester.pump();
    controller.changeQuery('submit');
    final submitted = controller.submit();
    api.searches.last.result.complete([]);
    await submitted;
    await tester.pump(const Duration(milliseconds: 500));
    expect(api.searches.length, 2);
    expect(controller.loading, isFalse);
  });

  testWidgets('type switch cancels debounce and ignores the old type error', (
    tester,
  ) async {
    controller.changeQuery('title');
    final old = controller.submit();
    controller.changeQuery('title');
    final current = controller.selectType(SubjectType.real);
    expect(api.searches.map((s) => s.type), [
      SubjectType.anime,
      SubjectType.real,
    ]);
    api.searches.last.result.complete([progressCollection(2).subject]);
    await current;
    api.searches.first.result.completeError(Exception('old type failed'));
    await old;
    await tester.pump(const Duration(milliseconds: 500));
    expect(api.searches.length, 2);
    expect(controller.results.single.id, 2);
    expect(controller.error, isNull);
    expect(controller.type, SubjectType.real);
  });

  testWidgets('a new keyword rejects old results before its debounce fires', (
    tester,
  ) async {
    controller.changeQuery('old');
    final old = controller.submit();
    controller.changeQuery('new');
    api.searches.single.result.complete([progressCollection(1).subject]);
    await old;
    expect(controller.results, isEmpty);
    expect(controller.loading, isTrue);
    await tester.pump(const Duration(milliseconds: 400));
    api.searches.last.result.complete([progressCollection(2).subject]);
    await tester.pump();
    expect(controller.results.single.id, 2);
  });

  testWidgets('clearing a query rejects an in-flight result and stays idle', (
    tester,
  ) async {
    controller.changeQuery('title');
    final old = controller.submit();
    controller.changeQuery('   ');
    api.searches.single.result.complete([progressCollection(1).subject]);
    await old;
    await tester.pump(const Duration(milliseconds: 500));
    expect(api.searches.length, 1);
    expect(controller.results, isEmpty);
    expect(controller.error, isNull);
    expect(controller.loading, isFalse);
  });

  testWidgets('retry clears the error and uses the current API dependency', (
    tester,
  ) async {
    controller.changeQuery('title');
    final failed = controller.submit();
    api.searches.single.result.completeError(Exception('offline'));
    await failed;
    expect(controller.error, 'offline');
    api = _SearchApi();
    final retry = controller.submit();
    expect(controller.error, isNull);
    expect(controller.loading, isTrue);
    api.searches.single.result.complete([progressCollection(2).subject]);
    await retry;
    expect(controller.results.single.id, 2);
    expect(controller.loading, isFalse);
  });

  testWidgets('dispose cancels debounce and suppresses late search/calendar', (
    tester,
  ) async {
    final closing = ScheduleSearchController(api: () => api);
    var publications = 0;
    closing.addListener(() => publications++);
    unawaited(closing.loadCalendar());
    closing.changeQuery('old');
    unawaited(closing.submit());
    closing.changeQuery('pending');
    closing.dispose();
    final before = publications;
    api.calendar.complete([]);
    api.searches.single.result.completeError(Exception('late'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(publications, before);
    expect(api.searches.length, 1);
  });

  testWidgets('calendar maps valid days independently of search results', (
    tester,
  ) async {
    unawaited(controller.loadCalendar());
    api.calendar.complete([
      CalendarDay(
        weekday: 5,
        weekdayLabel: '周五',
        subjects: [progressCollection(1).subject],
      ),
      CalendarDay(
        weekday: 8,
        weekdayLabel: 'invalid',
        subjects: [progressCollection(2).subject],
      ),
    ]);
    await tester.pump();
    expect(controller.calendarLoading, isFalse);
    expect(controller.officialDay(1), 5);
    expect(controller.officialDay(2), isNull);
    expect(controller.officialDay(3), isNull);
    expect(controller.results, isEmpty);
  });

  testWidgets('calendar timeout releases placement and ignores a late answer', (
    tester,
  ) async {
    unawaited(controller.loadCalendar());
    await tester.pump(const Duration(seconds: 8));
    expect(controller.calendarLoading, isFalse);
    expect(controller.error, isNull);
    api.calendar.complete([
      CalendarDay(
        weekday: 5,
        weekdayLabel: '周五',
        subjects: [progressCollection(1).subject],
      ),
    ]);
    await tester.pump();
    expect(controller.officialDay(1), isNull);
  });
}

class _SearchApi extends BangumiApi {
  Completer<List<CalendarDay>>? _calendar;
  // Create the future inside the requesting test's fake-async zone.
  Completer<List<CalendarDay>> get calendar =>
      _calendar ??= Completer<List<CalendarDay>>();
  final searches =
      <({String keyword, SubjectType type, Completer<List<Subject>> result})>[];

  @override
  Future<List<CalendarDay>> getCalendar() => calendar.future;

  @override
  Future<List<Subject>> searchSubjects(
    String keyword, {
    int limit = 24,
    int offset = 0,
    String sort = 'match',
    num minimumRating = 0,
    bool ratingExclusive = false,
    int startYear = 0,
    int endYear = 0,
    List<String> tags = const [],
    List<String> metaTags = const [],
    SubjectType subjectType = SubjectType.anime,
  }) {
    final result = Completer<List<Subject>>();
    searches.add((keyword: keyword, type: subjectType, result: result));
    return result.future;
  }
}
