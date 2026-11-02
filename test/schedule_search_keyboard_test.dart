import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/bangumi_api.dart';
import 'package:mubangumi/core/network/bangumi_support.dart';
import 'package:mubangumi/features/schedule/presentation/schedule_search_sheet.dart';
import 'package:mubangumi/state/schedule_controller.dart';
import 'package:mubangumi/state/session_controller.dart';

import 'support/schedule_fixtures.dart';

class _CalendarApi extends BangumiApi {
  @override
  Future<List<CalendarDay>> getCalendar() async => const [];
}

void main() {
  testWidgets('schedule search keeps its viewport above the keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bangumiApiProvider.overrideWithValue(_CalendarApi()),
          scheduleStoreProvider.overrideWithValue(MemorySchedules()),
          scheduleReminderProvider.overrideWithValue(MemoryScheduleReminders()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showScheduleSearchSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byType(DraggableScrollableSheet)).bottom,
      lessThanOrEqualTo(544),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
