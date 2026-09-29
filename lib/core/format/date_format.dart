String _two(int value) => value.toString().padLeft(2, '0');

String formatDate(DateTime time, {String separator = '-'}) =>
    '${time.year}$separator${_two(time.month)}$separator${_two(time.day)}';

String formatHourMinute(int hour, int minute) =>
    '${_two(hour)}:${_two(minute)}';

String formatDateTime(DateTime time, {String dateSeparator = '-'}) =>
    '${formatDate(time, separator: dateSeparator)} '
    '${formatHourMinute(time.hour, time.minute)}';

String formatFileStamp(DateTime time) =>
    '${time.year}${_two(time.month)}${_two(time.day)}_'
    '${_two(time.hour)}${_two(time.minute)}${_two(time.second)}';
