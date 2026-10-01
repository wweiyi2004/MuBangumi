import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/backup/backup_archive.dart';
import 'package:mubangumi/core/backup/backup_plan.dart';
import 'package:mubangumi/core/backup/backup_repository.dart';
import 'package:mubangumi/core/sharing/config_transfer.dart';
import 'package:mubangumi/core/social/friend_groups.dart';
import 'package:mubangumi/core/theme/font_repository.dart';
import 'package:mubangumi/models/app_font.dart';
import 'package:mubangumi/state/backup_providers.dart';
import 'package:mubangumi/state/config_transfer_providers.dart';
import 'package:mubangumi/state/font_controller.dart';
import 'package:mubangumi/state/friend_groups_controller.dart';
import 'package:mubangumi/state/session_controller.dart';
import 'support/pm_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'same UID migration uses the receiving account username for local browsing keys',
    () async {
      final session = PmTestSession();
      String? importedFor;
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith((ref) => session),
          backupApplyProvider.overrideWithValue((
            owner,
            preview,
            current,
          ) async {
            importedFor = owner.username;
            return const BackupApplied(changed: false);
          }),
        ],
      );
      addTearDown(container.dispose);
      final archive = BackupArchive.create(
        owner: const BackupOwner(1, 'old_username'),
        data: {BackupCategory.browsing: []},
      );
      final snapshot = ConfigSnapshot(
        owner: archive.owner,
        themeMode: 'system',
        groups: FriendGroups(),
        background: const {
          'blur': 22.0,
          'dim': .32,
          'glass': .42,
          'reduceTransparency': false,
        },
        backup: archive,
      );
      final preview = BackupPreview.create(
        archive,
        {BackupCategory.browsing: []},
        {BackupCategory.browsing},
        BackupImportMode.merge,
      );
      await container.read(configApplyProvider)(
        snapshot,
        preview,
        false,
        false,
        () => true,
      );
      expect(importedFor, 'user1');
    },
  );
  test(
    'export includes only selected local data and account-owned groups',
    () async {
      final session = PmTestSession(), repository = Repository();
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith((ref) => session),
          fontRepositoryProvider.overrideWithValue(Fonts()),
          backupRepositoryProvider.overrideWith((ref) async => repository),
        ],
      );
      addTearDown(container.dispose);
      final group = container.read(friendGroupsProvider(1).notifier);
      await group.ready;
      await group.edit((g) => g.rename(null, '本地同好'));
      final snapshot = await container.read(configExportProvider)(
        session.batchAccount!,
        {BackupCategory.schedules, BackupCategory.rss},
      );
      expect(repository.categories, {
        BackupCategory.schedules,
        BackupCategory.rss,
      });
      expect(snapshot.groups.names.values.single, '本地同好');
      expect(snapshot.owner.id, 1);
      expect(snapshot.backup!.data.keys, {
        BackupCategory.schedules,
        BackupCategory.rss,
      });
      final json = snapshot.toJson().toString();
      for (final word in [
        'access_token',
        'Cookie',
        'imagePath',
        'privateDrafts',
        'communityDrafts',
      ]) {
        expect(json, isNot(contains(word)));
      }
    },
  );
  test(
    'export discards old-account data when the repository completes late',
    () async {
      final session = PmTestSession(),
          repository = Repository()..pending = Completer<BackupArchive>();
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith((ref) => session),
          fontRepositoryProvider.overrideWithValue(Fonts()),
          backupRepositoryProvider.overrideWith((ref) async => repository),
        ],
      );
      addTearDown(container.dispose);
      final exporting = container.read(configExportProvider)(
        session.batchAccount!,
        {BackupCategory.pins},
      );
      final rejected = expectLater(exporting, throwsA(isA<BackupException>()));
      await repository.started.future;
      session.switchUser(2);
      repository.pending!.complete(
        BackupArchive.create(
          owner: const BackupOwner(1, 'user1'),
          data: {BackupCategory.pins: []},
        ),
      );
      await rejected;
    },
  );
  test(
    'group import merges once, keeps local assignments and rejects changed accounts',
    () async {
      final session = PmTestSession();
      final container = ProviderContainer(
        overrides: [sessionProvider.overrideWith((ref) => session)],
      );
      addTearDown(container.dispose);
      final group = container.read(friendGroupsProvider(1).notifier);
      await group.ready;
      await group.edit((g) => g.rename(null, '保留分组'));
      var incoming = FriendGroups().rename(null, '新分组');
      incoming = incoming.assign('friend', incoming.names.keys.single);
      final snapshot = ConfigSnapshot(
        owner: const BackupOwner(1, 'user1'),
        themeMode: 'system',
        groups: incoming,
        background: const {
          'blur': 22.0,
          'dim': .32,
          'glass': .42,
          'reduceTransparency': false,
        },
      );
      final account = session.batchAccount!;
      bool current() => session.isCurrentBatchAccount(account);
      await container.read(configApplyProvider)(
        snapshot,
        null,
        false,
        true,
        current,
      );
      final first = group.state.groups.toJson();
      await container.read(configApplyProvider)(
        snapshot,
        null,
        false,
        true,
        current,
      );
      expect(group.state.groups.toJson(), first);
      expect(group.state.groups.names.length, 2);
      session.switchUser(2);
      await expectLater(
        container.read(configApplyProvider)(
          snapshot,
          null,
          false,
          true,
          current,
        ),
        throwsA(isA<BackupException>()),
      );
      expect(group.state.groups.toJson(), first);
    },
  );
}

class Repository implements BackupRepository {
  final started = Completer<void>();
  Completer<BackupArchive>? pending;
  Set<BackupCategory>? categories;
  @override
  Future<BackupArchive> export(
    BackupOwner owner,
    Set<BackupCategory> categories,
  ) {
    this.categories = categories;
    started.complete();
    return pending?.future ??
        Future.value(
          BackupArchive.create(
            owner: owner,
            data: {for (final c in categories) c: []},
          ),
        );
  }

  @override
  Future<BackupPreview> preview(
    BackupOwner owner,
    BackupArchive archive,
    Set<BackupCategory> categories,
    BackupImportMode mode,
  ) async => BackupPreview.create(
    archive,
    {for (final c in categories) c: []},
    categories,
    mode,
  );
  @override
  Future<bool> apply(
    BackupOwner owner,
    BackupPreview preview, {
    required bool Function() isCurrentOwner,
  }) async => false;
}

class Fonts implements FontRepository {
  @override
  Future<String?> readSelection() async => null;
  @override
  Future<void> saveSelection(String? id) async {}
  @override
  Future<Set<String>> installed() async => {};
  @override
  Future<void> activate(AppFont font) async {}
  @override
  Future<void> download(
    AppFont font,
    CancelToken cancel,
    void Function(double) progress,
  ) async => throw StateError('must never download');
  @override
  Future<void> remove(AppFont font) async {}
}
