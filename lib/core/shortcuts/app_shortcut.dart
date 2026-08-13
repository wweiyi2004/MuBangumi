import 'dart:io';

import 'package:flutter/foundation.dart';

enum AppShortcut {
  scan,
  myQr,
  schedule;

  static const scanType = 'scan';
  static const myQrType = 'my_qr';
  static const scheduleType = 'schedule';

  /// Extra key used by `quick_actions` on Android. Static XML must match.
  static const androidExtraKey = 'some unique action key';

  static bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  String get type => switch (this) {
    scan => scanType,
    myQr => myQrType,
    schedule => scheduleType,
  };

  static AppShortcut? tryParse(String? type) {
    final value = type?.trim() ?? '';
    if (value.isEmpty) return null;
    for (final item in values) {
      if (item.type == value) return item;
    }
    return null;
  }
}
