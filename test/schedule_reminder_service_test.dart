import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/notifications/schedule_reminder_service.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  test(
    'calendar weekday stays correct across a daylight-saving transition',
    () {
      tzdata.initializeTimeZones();
      final location = tz.getLocation('America/New_York');
      final now = tz.TZDateTime(location, 2026, 3, 7, 23, 30);
      final next = nextWeeklyReminder(
        now: now,
        weekday: DateTime.sunday,
        hour: 20,
        minute: 0,
      );
      expect(next, tz.TZDateTime(location, 2026, 3, 8, 20));
      expect(next.weekday, DateTime.sunday);
      expect(next.timeZoneOffset, const Duration(hours: -4));
    },
  );

  test('UTC input preserves UTC when finding the next calendar weekday', () {
    final next = nextWeeklyReminder(
      now: DateTime.utc(2026, 9, 8, 23),
      weekday: DateTime.wednesday,
      hour: 20,
      minute: 0,
    );
    expect(next, DateTime.utc(2026, 9, 9, 20));
    expect(next.isUtc, isTrue);
  });
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
