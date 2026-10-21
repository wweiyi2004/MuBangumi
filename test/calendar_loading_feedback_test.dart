import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/bangumi_api.dart';
import 'package:mubangumi/core/network/bangumi_support.dart';
import 'package:mubangumi/screens/calendar_page.dart';
import 'package:mubangumi/state/session_controller.dart';

class CalendarApi extends BangumiApi {
  Completer<List<CalendarDay>>? pending;
  @override
  Future<List<CalendarDay>> getCalendar() async =>
      pending?.future ??
      const [CalendarDay(weekday: 1, weekdayLabel: '周一', subjects: [])];
}

void main() {
  testWidgets(
    'calendar refresh keeps weekday controls visible and interactive after failure',
    (tester) async {
      final api = CalendarApi();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [bangumiApiProvider.overrideWithValue(api)],
          child: const MaterialApp(home: CalendarPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('周一 0'), findsOneWidget);
      api.pending = Completer<List<CalendarDay>>();
      await tester.tap(find.byTooltip('刷新'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 310));
      expect(find.text('周一 0'), findsOneWidget);
      expect(find.text('显示已有放送表，正在更新'), findsOneWidget);
      await tester.tap(find.text('周一 0'));
      api.pending!.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(find.text('周一 0'), findsOneWidget);
      expect(find.text('更新失败，点击重试'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
