import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/backup/backup_archive.dart';
import '../core/backup/backup_plan.dart';
import '../core/sharing/config_transfer.dart';
import '../models/library_batch.dart';
import '../models/app_font.dart';
import 'session_controller.dart';
import 'backup_providers.dart';
import 'theme_controller.dart';
import 'font_controller.dart';
import 'custom_colors_controller.dart';
import 'friend_groups_controller.dart';
import 'background_controller.dart';

typedef ConfigExport =
    Future<ConfigSnapshot> Function(LibraryBatchAccount, Set<BackupCategory>);
final configExportProvider = Provider<ConfigExport>(
  (ref) => (account, categories) async {
    bool current() =>
        ref.read(sessionProvider.notifier).isCurrentBatchAccount(account);
    void check() {
      if (!current()) throw const BackupException('账号已变化，请重新打开迁移页面');
    }

    check();
    if (categories.any((c) => c.isDraft)) {
      throw const BackupException('配置迁移不包含草稿');
    }
    await Future.wait([
      ref.read(themeModeProvider.notifier).ready,
      ref.read(fontProvider.notifier).ready,
      ref.read(customColorsProvider.notifier).ready,
      ref.read(backgroundSettingsProvider.notifier).ready,
      ref.read(friendGroupsProvider(account.userId).notifier).ready,
    ]);
    check();
    final groups = ref.read(friendGroupsProvider(account.userId));
    if (groups.loading || groups.error != null) {
      throw const BackupException('好友分组尚未读取完成');
    }
    final bg = ref.read(backgroundSettingsProvider);
    final mode = ref.read(themeModeProvider);
    final archive = categories.isEmpty
        ? null
        : await (await ref.read(
            backupRepositoryProvider.future,
          )).export(BackupOwner(account.userId, account.username), categories);
    check();
    return ConfigSnapshot(
      owner: BackupOwner(account.userId, account.username),
      themeMode: mode.name,
      colors: ref.read(customColorsProvider),
      fontId: ref.read(fontProvider).selected?.id,
      groups: groups.groups,
      background: {
        'blur': bg.blur,
        'dim': bg.dim,
        'glass': bg.glass,
        'reduceTransparency': bg.reduceTransparency,
      },
      backup: archive,
    );
  },
);

typedef ConfigApply =
    Future<List<String>> Function(
      ConfigSnapshot,
      BackupPreview?,
      bool,
      bool,
      bool Function(),
    );
final configApplyProvider = Provider<ConfigApply>(
  (ref) => (snapshot, preview, appearance, friends, current) async {
    void check() {
      if (!current()) throw const BackupException('账号已变化，请重新打开迁移页面');
    }

    check();
    final user = ref.read(sessionProvider).user;
    if (snapshot.owner.id != user?.id) {
      throw const BackupException('请先登录配置所属的账号');
    }
    final warnings = <String>[];
    if (preview != null) {
      final result = await ref.read(backupApplyProvider)(
        BackupOwner(user!.id, user.username),
        preview,
        current,
      );
      warnings.addAll(result.warnings);
    }
    check();
    if (friends) {
      await ref.read(friendGroupsProvider(snapshot.owner.id).notifier).edit((
        g,
      ) {
        check();
        return g.merge(snapshot.groups);
      });
    }
    check();
    if (appearance) {
      await ref.read(customColorsProvider.notifier).choose(snapshot.colors);
      check();
      await ref
          .read(themeModeProvider.notifier)
          .setMode(ThemeMode.values.byName(snapshot.themeMode), strict: true);
      check();
      await ref
          .read(backgroundSettingsProvider.notifier)
          .importAdjustments(snapshot.background);
      check();
      final controller = ref.read(fontProvider.notifier);
      await controller.ready;
      check();
      final state = ref.read(fontProvider);
      final font = [...downloadableFonts, ...state.imported]
          .where(
            (f) => f.id == snapshot.fontId && state.installed.contains(f.id),
          )
          .firstOrNull;
      if (snapshot.fontId != null && font == null) {
        warnings.add('源设备字体尚未安装，暂时使用默认字体；可在字体设置中下载或导入同一字库。');
      }
      await controller.choose(font);
      if (ref.read(fontProvider).error != null) warnings.add('字体应用失败，当前字体已保留。');
    }
    return warnings;
  },
);
