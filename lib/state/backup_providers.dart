import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/backup/backup_archive.dart';
import '../core/backup/backup_files.dart';
import '../core/backup/backup_plan.dart';
import '../core/backup/backup_repository.dart';
import '../core/backup/sqlite_backup_repository.dart';
import '../core/storage/browsing_store.dart';
import 'home_pins_controller.dart';
import 'local_data_state.dart';
import 'recommendation_feedback_controller.dart';
import 'rss_controller.dart';
import 'schedule_controller.dart';
import 'schedule_view_controller.dart';
import 'user_preferences_controller.dart';

final backupRepositoryProvider = FutureProvider<BackupRepository>(
  (ref) => SqliteBackupRepository.shared(),
);
final backupFilesProvider = Provider<BackupFiles>(
  (ref) => PlatformBackupFiles(),
);

class BackupApplied {
  const BackupApplied({required this.changed, this.warnings = const []});
  final bool changed;
  final List<String> warnings;
}

typedef BackupApply =
    Future<BackupApplied> Function(
      BackupOwner owner,
      BackupPreview preview,
      bool Function() isCurrentOwner,
    );

/// Only this integration layer pauses controllers or refreshes visible state.
/// The session and Bangumi replay queue are deliberately not dependencies.
final backupApplyProvider = Provider<BackupApply>(
  (ref) => (owner, preview, isCurrentOwner) async {
    if (ref.read(localImportBusyProvider)) {
      throw const BackupException('另一次导入正在进行，请稍后再试');
    }
    if (!isCurrentOwner()) throw const BackupException('账号已变化，请重新打开备份页面');
    ref.read(localImportBusyProvider.notifier).state = true;
    ScheduleController? schedules;
    RssController? rss;
    var changed = false;
    final warnings = <String>[];
    try {
      final repository = await ref.read(backupRepositoryProvider.future);
      if (!isCurrentOwner()) throw const BackupException('账号已变化，请重新打开备份页面');
      if (preview.categories.contains(BackupCategory.schedules)) {
        final controller = ref.read(scheduleProvider.notifier);
        schedules = controller;
        await controller.pauseForImport();
      }
      if (preview.categories.contains(BackupCategory.rss)) {
        final controller = ref.read(rssProvider.notifier);
        rss = controller;
        await controller.pauseForImport();
      }
      changed = await repository.apply(
        owner,
        preview,
        isCurrentOwner: isCurrentOwner,
      );
      if (changed) {
        if (preview.categories.contains(BackupCategory.people)) {
          ref.invalidate(userPreferencesProvider);
        }
        if (preview.categories.contains(BackupCategory.pins)) {
          ref.invalidate(homePinsProvider(owner.id));
        }
        if (preview.categories.contains(BackupCategory.recommendations)) {
          ref.invalidate(recommendationFeedbackProvider(owner.id));
        }
        if (preview.categories.contains(BackupCategory.browsing)) {
          ref.invalidate(scheduleViewProvider(owner.id));
          ref.invalidate(recentSearchesProvider(owner.username));
          ref.read(localBrowsingEpochProvider.notifier).state++;
        }
      }
    } finally {
      // Reload even after a rejected preview/rollback: earlier work may have been
      // cancelled while pausing. Cleanup failures must not misreport a commit.
      if (rss != null) {
        try {
          if (!await rss.resumeAfterImport(imported: changed)) {
            warnings.add('RSS 读取暂未完成，可在新番表重试');
          }
        } catch (_) {
          warnings.add('RSS 读取暂未完成，可在新番表重试');
        }
      }
      if (schedules != null) {
        try {
          if (!await schedules.resumeAfterImport()) {
            warnings.add('新番表或系统提醒刷新失败，可在新番表重试');
          }
        } catch (_) {
          warnings.add('新番表或系统提醒刷新失败，可在新番表重试');
        }
      }
      ref.read(localImportBusyProvider.notifier).state = false;
    }
    return BackupApplied(
      changed: changed,
      warnings: List.unmodifiable(warnings),
    );
  },
);
