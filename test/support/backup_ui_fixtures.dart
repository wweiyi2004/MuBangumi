import 'dart:ui';

import 'package:mubangumi/core/backup/backup_archive.dart';
import 'package:mubangumi/core/backup/backup_files.dart';
import 'package:mubangumi/core/backup/backup_plan.dart';
import 'package:mubangumi/core/backup/backup_repository.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/state/session_controller.dart';

import 'backup_fixtures.dart';
import 'library_batch_fixtures.dart';

BackupArchive uiBackup({BackupOwner owner = backupOwner}) =>
    BackupArchive.create(
      owner: owner,
      createdAt: DateTime.utc(2026, 9, 8),
      data: {
        BackupCategory.schedules: [
          {
            'season': backupSeason.toJson(),
            'items': [backupItem.toJson()],
          },
        ],
        BackupCategory.rss: [
          {
            'kind': 'source',
            'url': 'https://example.invalid/rss',
            'name': '追番更新源',
            'enabled': true,
            'created_at': 1,
            'position': 0,
          },
          {
            'kind': 'binding',
            'source_url': 'https://example.invalid/rss',
            'subject_id': 123,
            'subject_name': '番剧名称',
            'season_key': backupSeason.id,
            'match_keywords': '番剧',
            'exclude_keywords': '合集',
            'enabled': true,
            'created_at': 1,
            'position': 0,
          },
        ],
        BackupCategory.people: [backupPerson('someone', '备注')],
        BackupCategory.pins: [backupPin(123, 0), backupPin(456, 1)],
        BackupCategory.browsing: [backupSearch('魔法', 0)],
        BackupCategory.recommendations: [
          {
            'subject_id': 789,
            'title': '很长很长的番剧名称：另一条世界线中的旅途与尚未说完的故事',
            'subject_type': 2,
            'hidden_at': 1,
          },
        ],
        BackupCategory.communityDrafts: [
          {
            'target': ['group', 'demo'],
            'title': '社区草稿标题',
            'content': '正文',
            'updated_at': 1,
          },
        ],
        BackupCategory.privateDrafts: [
          {
            'id': backupDraftId,
            'kind': 'compose',
            'recipient': 'recipient',
            'title': '私信草稿标题',
            'body': '正文',
            'conversation_id': '',
            'thread_id': '',
            'updated_at': 1,
            'position': 0,
          },
        ],
      },
    );

class BackupUiSession extends BatchTestSession {
  BackupUiSession() : super(BatchTestApi([]), MemoryBatchQueue()) {
    useOwner(backupOwner);
  }
  int syncCalls = 0;
  void useOwner(BackupOwner owner, {int pending = 0}) => state = SessionState(
    phase: SessionPhase.signedIn,
    user: BangumiUser(
      id: owner.id,
      username: owner.username,
      nickname: owner.username,
      avatarUrl: '',
    ),
    pendingSyncCount: pending,
  );
  @override
  Future<void> syncPendingChanges({bool retryBlocked = false}) async {
    syncCalls++;
  }
}

class MemoryBackups implements BackupRepository {
  MemoryBackups({BackupRows? data}) : local = data ?? uiBackup().data;
  BackupRows local;
  int exports = 0, previews = 0, applies = 0;
  Future<void>? exportGate, previewGate, applyGate;
  Object? exportError, applyError;
  BackupArchive? lastExport;
  BackupPreview? lastPreview;
  @override
  Future<BackupArchive> export(
    BackupOwner owner,
    Set<BackupCategory> categories,
  ) async {
    exports++;
    await exportGate;
    if (exportError != null) throw exportError!;
    return lastExport = BackupArchive.create(
      owner: owner,
      data: {for (final c in categories) c: local[c] ?? []},
    );
  }

  @override
  Future<BackupPreview> preview(
    BackupOwner owner,
    BackupArchive archive,
    Set<BackupCategory> categories,
    BackupImportMode mode,
  ) async {
    previews++;
    await previewGate;
    return lastPreview = BackupPreview.create(archive, local, categories, mode);
  }

  @override
  Future<bool> apply(
    BackupOwner owner,
    BackupPreview preview, {
    required bool Function() isCurrentOwner,
  }) async {
    applies++;
    await applyGate;
    if (applyError != null) throw applyError!;
    if (!isCurrentOwner()) throw const BackupException('账号已变化');
    if (backupRowsDigest(local, preview.categories) != preview.beforeDigest) {
      throw const BackupException('本地数据在预览后发生了变化，请重新预览');
    }
    local = {
      ...local,
      ...mergeBackupRows(
        local,
        preview.archive.data,
        preview.categories,
        preview.mode,
      ),
    };
    return preview.hasChanges;
  }
}

class MemoryBackupFiles implements BackupFiles {
  PickedBackup? next = PickedBackup('MuBangumi-备份.json', uiBackup());
  Future<void>? pickGate;
  Object? pickError, saveError;
  bool cancelSave = false;
  int saves = 0, shares = 0;
  BackupArchive? saved;
  @override
  Future<PickedBackup?> pick() async {
    await pickGate;
    if (pickError != null) throw pickError!;
    return next;
  }

  @override
  Future<String?> save(BackupArchive archive) async {
    saves++;
    if (saveError != null) throw saveError!;
    if (cancelSave) return null;
    saved = archive;
    return 'selected-backup.json';
  }

  @override
  Future<void> share(BackupArchive archive, {required Rect origin}) async {
    shares++;
    saved = archive;
  }
}
