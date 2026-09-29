import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/format/date_format.dart';

void main() {
  test('formats dates with zero padding and configurable separators', () {
    final time = DateTime(2026, 3, 7, 4, 5, 6);
    expect(formatDate(time), '2026-03-07');
    expect(formatDate(time, separator: '.'), '2026.03.07');
    expect(formatDate(DateTime(2026, 12, 31)), '2026-12-31');
  });

  test('formats hour, minute and combined date time', () {
    final time = DateTime(2026, 3, 7, 4, 5, 6);
    expect(formatHourMinute(4, 5), '04:05');
    expect(formatHourMinute(23, 59), '23:59');
    expect(formatDateTime(time), '2026-03-07 04:05');
    expect(formatDateTime(time, dateSeparator: '/'), '2026/03/07 04:05');
  });

  test('formats a compact file stamp', () {
    expect(formatFileStamp(DateTime(2026, 3, 7, 4, 5, 6)), '20260307_040506');
    expect(
      formatFileStamp(DateTime(2026, 11, 20, 13, 45, 59)),
      '20261120_134559',
    );
  });
}
