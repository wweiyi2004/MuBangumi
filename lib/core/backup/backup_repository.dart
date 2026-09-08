import 'backup_archive.dart';
import 'backup_plan.dart';

abstract class BackupRepository {
  Future<BackupArchive> export(
    BackupOwner owner,
    Set<BackupCategory> categories,
  );
  Future<BackupPreview> preview(
    BackupOwner owner,
    BackupArchive archive,
    Set<BackupCategory> categories,
    BackupImportMode mode,
  );
  Future<bool> apply(
    BackupOwner owner,
    BackupPreview preview, {
    required bool Function() isCurrentOwner,
  });
}
