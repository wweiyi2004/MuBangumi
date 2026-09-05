import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/notifications/schedule_reminder_service.dart';

void main() {
  test('uses a later time on the same weekday', () {
    final next = nextWeeklyReminder(
      now: DateTime(2026, 8, 24, 19, 30), // Monday.
      weekday: DateTime.monday,
      hour: 20,
      minute: 0,
    );

    expect(next, DateTime(2026, 8, 24, 20));
  });

  test('rolls an elapsed same-weekday time to next week', () {
    final next = nextWeeklyReminder(
      now: DateTime(2026, 8, 24, 20), // Exactly at the reminder time.
      weekday: DateTime.monday,
      hour: 20,
      minute: 0,
    );

    expect(next, DateTime(2026, 8, 31, 20));
  });

  test('finds the requested weekday later in the week', () {
    final next = nextWeeklyReminder(
      now: DateTime(2026, 8, 25, 9), // Tuesday.
      weekday: DateTime.friday,
      hour: 18,
      minute: 15,
    );

    expect(next, DateTime(2026, 8, 28, 18, 15));
  });
}
