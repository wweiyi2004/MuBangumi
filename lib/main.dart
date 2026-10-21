import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/diagnostics/background_diagnostics.dart';
import 'core/diagnostics/package_probe.dart';
import 'core/notifications/schedule_reminder_service.dart';
import 'core/platform/window_close.dart';
import 'widgets/personal_data_migration_host.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (arguments.contains('--mubangumi-package-check')) {
    exit(await runPackageProbe());
  }
  BackgroundDiagnostics.start();
  await WindowCloseCoordinator.initialize();
  try {
    await ScheduleReminderService.shared.initialize();
  } catch (_) {
    // The app remains usable; enabling a reminder will surface the native error.
  }
  runApp(
    const ProviderScope(
      child: PersonalDataMigrationHost(child: MuBangumiApp()),
    ),
  );
}
