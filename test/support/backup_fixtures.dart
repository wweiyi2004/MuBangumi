import 'dart:io';

import 'package:mubangumi/core/backup/backup_archive.dart';
import 'package:mubangumi/core/backup/sqlite_backup_repository.dart';
import 'package:mubangumi/core/storage/browsing_store.dart';
import 'package:mubangumi/core/storage/community_draft_store.dart';
import 'package:mubangumi/core/storage/pm_draft_store.dart';
import 'package:mubangumi/core/storage/rss_store.dart';
import 'package:mubangumi/core/storage/schedule_store.dart';
import 'package:mubangumi/core/storage/user_preference_store.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/models/recommendation_feedback.dart';
import 'package:mubangumi/models/rss_models.dart';
import 'package:mubangumi/models/schedule_models.dart';
import 'package:mubangumi/models/schedule_view.dart';
import 'package:path/path.dart' as path;

const backupOwner = BackupOwner(11, 'alice');
const otherBackupOwner = BackupOwner(22, 'bob');
final allBackupCategories = BackupCategory.values.toSet();
const backupDraftId = 'abcdefghijklmnopqrstuvwx';
const backupSeason = SeasonKey(year: 2026, quarter: 2);
const backupItem = ScheduleItem(
  subjectId: 123,
  name: ' 長い名前 🌸 ',
  nameCn: '很长的番剧名称',
  imageUrl: '//lain.bgm.tv/pic/cover/c/123.jpg',
  weekday: 2,
  sortOrder: 1,
  note: '保留\n所有字段',
  episodeCount: 12,
  reminderEnabled: true,
  reminderHour: 21,
  reminderMinute: 15,
);

Map<String, dynamic> backupPin(int id, int position) => {
  'subject_id': id,
  'position': position,
};
Map<String, dynamic> backupSearch(String keyword, int position) => {
  'kind': 'search',
  'keyword': keyword,
  'target': 'subject',
  'subject_type': 2,
  'position': position,
};
Map<String, dynamic> backupPerson(String username, String note) => {
  'username': username,
  'note': note,
  'blocked': true,
  'updated_at': 1234,
};

class BackupTestStores {
  BackupTestStores(this.dir) {
    schedules = ScheduleStore.test(
      databasePath: path.join(dir.path, 'schedule.sqlite'),
    );
    rss = RssStore.test(databasePath: path.join(dir.path, 'rss.sqlite'));
    people = UserPreferenceStore.test(
      databasePath: path.join(dir.path, 'people.sqlite'),
    );
    browsing = BrowsingStore(
      databasePath: path.join(dir.path, 'browsing.sqlite'),
    );
    community = CommunityDraftStore(
      databasePath: path.join(dir.path, 'community.sqlite'),
    );
    pm = PmDraftStore(databasePath: path.join(dir.path, 'pm.sqlite'));
  }
  final Directory dir;
  late final ScheduleStore schedules;
  late final RssStore rss;
  late final UserPreferenceStore people;
  late final BrowsingStore browsing;
  late final CommunityDraftStore community;
  late final PmDraftStore pm;
  SqliteBackupRepository repository({
    Future<void> Function(BackupCategory)? afterWrite,
  }) => SqliteBackupRepository(
    coordinatorPath: path.join(dir.path, 'import.sqlite'),
    databasePaths: {
      BackupDatabase.schedules: schedules.databaseForBackup,
      BackupDatabase.rss: rss.databaseForBackup,
      BackupDatabase.people: people.databaseForBackup,
      BackupDatabase.browsing: browsing.databaseForBackup,
      BackupDatabase.community: community.databaseForBackup,
      BackupDatabase.pm: pm.databaseForBackup,
    },
    afterCategoryWritten: afterWrite,
  );

  Future<void> seed() async {
    await schedules.save(
      SeasonSchedule(season: backupSeason, items: [backupItem]),
    );
    await schedules.writeReminderIds({123});
    final source = await rss.upsertSource(
      const RssSource(
        id: 0,
        name: '测试订阅',
        url: 'https://example.invalid/feed?tag=%E7%95%AA',
        etag: 'CACHE-SECRET',
      ),
    );
    await rss.upsertBinding(
      RssBinding(
        id: 0,
        sourceId: source.id,
        subjectId: 123,
        subjectName: '很长的番剧名称',
        seasonKey: backupSeason.id,
        matchKeywords: '字幕 1080',
        excludeKeywords: '合集',
      ),
    );
    await rss.insertItemsIgnoreDup([
      RssItem(
        id: 0,
        sourceId: source.id,
        subjectId: 123,
        guid: 'cached-guid',
        title: 'CACHE-ITEM',
        link: 'https://example.invalid/item',
      ),
    ]);
    await people.save(
      const LocalUserPreference(
        username: 'PERSON',
        note: '朋友\n备注',
        blocked: true,
      ),
    );
    await browsing.saveHomePins(11, [123, 456]);
    await browsing.saveHomePins(22, [999]);
    await browsing.saveLibrary('alice', {
      'subject_type': 2,
      'collection_type': 3,
      'progress': 'inProgress',
      'sort': 'rating',
      'minimum_rating': 8,
    });
    await browsing.saveScheduleView(11, ScheduleView.week);
    await browsing.rememberSearch('alice', const RecentSearch(keyword: '魔法'));
    await browsing.rememberSearch('alice', const RecentSearch(keyword: ' 星 '));
    await browsing.rememberSearch(
      'bob',
      const RecentSearch(keyword: 'OTHER-OWNER'),
    );
    await browsing.hideRecommendation(
      11,
      HiddenRecommendation(
        subjectId: 789,
        title: '不感兴趣',
        type: SubjectType.anime,
        hiddenAt: DateTime.utc(2026, 9, 8),
      ),
    );
    await community.save(communityDraftKey('alice', ['group', 'demo'])!, (
      title: '社区标题',
      content: ' 第一行\n[b]第二行[/b] ',
    ));
    await community.save(communityDraftKey('bob', ['timeline', 'post'])!, (
      title: '',
      content: 'OTHER-OWNER',
    ));
    await pm.save(
      const PmDraft(
        id: backupDraftId,
        ownerId: 11,
        kind: PmDraftKind.compose,
        recipient: 'ToSomeone',
        title: '私信标题',
        body: ' 原样\n保留 ',
      ),
      expectedRevision: 0,
    );
    await pm.save(
      PmDraft(
        id: PmDraft.replyId('42', '7'),
        ownerId: 11,
        kind: PmDraftKind.reply,
        conversationId: '42',
        threadId: '7',
        body: '回复',
      ),
      expectedRevision: 0,
    );
    await pm.save(
      const PmDraft(
        id: backupDraftId,
        ownerId: 22,
        kind: PmDraftKind.compose,
        body: 'OTHER-OWNER',
      ),
      expectedRevision: 0,
    );
  }

  Future<void> close() async {
    await schedules.close();
    await rss.close();
    await people.close();
    await browsing.close();
    await community.close();
    await pm.close();
  }
}
