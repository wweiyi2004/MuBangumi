import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/diagnostics/background_diagnostics.dart';
import 'core/notifications/schedule_reminder_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  BackgroundDiagnostics.start();
  try {
    await ScheduleReminderService.shared.initialize();
  } catch (_) {
    // The app remains usable; enabling a reminder will surface the native error.
  }
  runApp(const ProviderScope(child: MuBangumiApp()));
}
