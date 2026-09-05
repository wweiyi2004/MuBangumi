import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/auth/bangumi_oauth.dart';
import 'package:mubangumi/core/network/bangumi_api.dart';
import 'package:mubangumi/core/network/bangumi_endpoints.dart';
import 'package:mubangumi/core/network/bangumi_support.dart';
import 'package:mubangumi/core/network/netaba_api.dart';
import 'package:mubangumi/core/storage/snapshot_cache.dart';
import 'package:mubangumi/core/storage/token_store.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/models/netaba_models.dart';
import 'package:mubangumi/screens/subject_detail_screen.dart';
import 'package:mubangumi/state/session_controller.dart';

void main() {
  testWidgets(
    'slow episodes do not delay fresh details or independent sections',
    (tester) async {
      final api = _Api();
      await _show(tester, api, _Cache());
      expect(api.episodeCalls, 1);
      expect(api.metaCalls, 3);
      expect(api.commentCalls, 1);
      expect(find.text('新资料'), findsOneWidget);
      expect(find.text('暂无章节数据'), findsNothing);
      expect(api.episodes.isCompleted, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      api.episodes.complete([_episode]);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('broken snapshot reads and writes cannot block live episodes', (
    tester,
  ) async {
    final api = _Api();
    final cache = _Cache()
      ..failRead = true
      ..failWrite = true;
    await _show(tester, api, cache);
    expect(api.episodeCalls, 1);
    api.episodes.complete([_episode]);
    await tester.pump();
    expect(find.text('已看 1 / 1'), findsOneWidget);
    expect(cache.writes, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('late disk episodes cannot overwrite a fresh response', (
    tester,
  ) async {
    final api = _Api();
    final cache = _Cache()
      ..readResult = Completer<List<UserEpisodeCollection>?>();
    await _show(tester, api, cache);
    api.episodes.complete([_episode]);
    await tester.pump();
    cache.readResult!.complete([_episode.copyWith(type: 0)]);
    await tester.pump();
    expect(find.text('已看 1 / 1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('failed episodes offer retry instead of an empty state', (
    tester,
  ) async {
    final api = _Api();
    await _show(tester, api, _Cache());
    api.episodes.completeError(StateError('network unavailable'));
    await tester.pump();
    expect(find.text('暂无章节数据'), findsNothing);
    final retry = find.text('章节加载失败，请重试');
    expect(retry, findsOneWidget);
    api.episodes = Completer<List<UserEpisodeCollection>>();
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pump();
    expect(api.episodeCalls, 2);
    api.episodes.complete([_episode]);
    await tester.pump();
    expect(find.text('已看 1 / 1'), findsOneWidget);
    expect(retry, findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}

Future<void> _show(WidgetTester tester, _Api api, _Cache cache) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bangumiApiProvider.overrideWithValue(api),
        snapshotCacheProvider.overrideWithValue(cache),
        netabaApiProvider.overrideWithValue(_History()),
        sessionProvider.overrideWith((ref) => _Session(api)),
      ],
      child: const MaterialApp(home: SubjectDetailScreen(subject: _subject)),
    ),
  );
  await tester.pump();
}

const _subject = Subject(
  id: 7,
  name: '作品',
  nameCn: '',
  imageUrl: '',
  summary: '',
  episodeCount: 1,
  score: 0,
  rank: 0,
  date: '',
);
const _episode = UserEpisodeCollection(
  episode: Episode(
    id: 1,
    type: 0,
    number: 1,
    sort: 1,
    name: '第一集',
    nameCn: '',
    airDate: '',
    description: '',
  ),
  type: 2,
  updatedAt: 0,
);

class _Api extends BangumiApi {
  var episodes = Completer<List<UserEpisodeCollection>>();
  int episodeCalls = 0, metaCalls = 0, commentCalls = 0;
  @override
  Future<Subject> getSubject(int subjectId) async =>
      Subject.fromJson({..._subject.toJson(), 'summary': '新资料'});
  @override
  Future<List<UserEpisodeCollection>> getEpisodeCollections(
    int subjectId, {
    int? episodeType,
  }) {
    episodeCalls++;
    return episodes.future;
  }

  @override
  Future<List<SubjectCharacter>> getSubjectCharacters(int subjectId) async {
    metaCalls++;
    return [];
  }

  @override
  Future<List<SubjectPerson>> getSubjectPersons(int subjectId) async {
    metaCalls++;
    return [];
  }

  @override
  Future<List<RelatedSubject>> getRelatedSubjects(int subjectId) async {
    metaCalls++;
    return [];
  }

  @override
  Future<List<SubjectComment>> getSubjectComments(
    int subjectId, {
    int page = 1,
  }) async {
    commentCalls++;
    return [];
  }
}

class _Cache extends SnapshotCache {
  bool failRead = false, failWrite = false;
  int writes = 0;
  Completer<List<UserEpisodeCollection>?>? readResult;
  @override
  Future<List<UserEpisodeCollection>?> readEpisodeCollections(
    int subjectId,
  ) async {
    if (failRead) throw StateError('disk unavailable');
    return readResult == null ? null : await readResult!.future;
  }

  @override
  Future<void> writeEpisodeCollections(
    int subjectId,
    List<UserEpisodeCollection> items,
  ) async {
    writes++;
    if (failWrite) throw StateError('disk full');
  }
}

class _History extends NetabaApi {
  @override
  Future<NetabaSubjectHistory> getSubjectHistory(int subjectId) async =>
      throw const NetabaApiException('暂无历史');
}

class _Session extends SessionController {
  _Session(BangumiApi api) : super(api, BangumiOAuth(), _Tokens()) {
    state = const SessionState(
      phase: SessionPhase.signedIn,
      user: BangumiUser(
        id: 1,
        username: 'tester',
        nickname: '测试',
        avatarUrl: '',
      ),
      collections: [
        UserCollection(
          subjectId: 7,
          type: CollectionType.doing,
          rate: 0,
          episodeStatus: 0,
          updatedAt: null,
          subject: _subject,
        ),
      ],
    );
  }
  @override
  Future<List<UserEpisodeCollection>> applyPendingEpisodeChanges(
    int subjectId,
    List<UserEpisodeCollection> source,
  ) async => source;
}

class _Tokens extends TokenStore {
  @override
  Future<BangumiNetworkRoute> readNetworkRoute() =>
      Completer<BangumiNetworkRoute>().future;
  @override
  Future<String?> read() async => null;
  @override
  Future<String?> readRefreshToken() async => null;
  @override
  Future<DateTime?> readExpiresAt() async => null;
  @override
  Future<OAuthConfig?> readOAuthConfig() async => null;
}
