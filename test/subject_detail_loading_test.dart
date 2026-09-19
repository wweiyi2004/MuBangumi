import 'package:mubangumi/navigation/app_destination.dart';
import 'package:mubangumi/navigation/app_router.dart';
import 'package:mubangumi/state/short_review_draft.dart';
import 'support/memory_short_review_drafts.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mubangumi/widgets/mobile_subject_actions.dart';
import 'support/ux_visuals.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/auth/bangumi_oauth.dart';
import 'package:mubangumi/core/network/bangumi_api.dart';
import 'package:mubangumi/core/network/bangumi_endpoints.dart';
import 'package:mubangumi/core/network/bangumi_support.dart';
import 'package:mubangumi/core/network/netaba_api.dart';
import 'package:mubangumi/core/storage/snapshot_cache.dart';
import 'package:mubangumi/core/storage/bangumi_sync_store.dart';
import 'package:mubangumi/core/storage/token_store.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/models/netaba_models.dart';
import 'package:mubangumi/screens/subject_detail_screen.dart';
import 'package:mubangumi/state/session_controller.dart';

void main() {
  for (final scale in [1.0, 1.8]) {
    testWidgets(
      'phone actions stay reachable and comment input focuses at scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final api = _Api()..episodes.complete([_episode]);
        final cache = _Cache();
        final session = _Session(api, cache);
        final boundary = GlobalKey();
        final theme = await uxTheme(tester, dark: false);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              shortReviewDraftRepositoryProvider.overrideWithValue(
                MemoryShortReviewDrafts(),
              ),
              bangumiApiProvider.overrideWithValue(api),
              snapshotCacheProvider.overrideWithValue(cache),
              netabaApiProvider.overrideWithValue(_History()),
              sessionProvider.overrideWith((ref) => session),
            ],
            child: AppRouteScope(
              resolve: AppRouter.resolve,
              child: MaterialApp(
                theme: theme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: RepaintBoundary(key: boundary, child: child!),
                ),
                home: const SubjectDetailScreen(subject: _subject),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final actions = find.byType(MobileSubjectActions);
        expect(actions, findsOneWidget);
        final before = tester.getRect(actions);
        await tester.drag(
          find.byType(SingleChildScrollView).first,
          const Offset(0, -450),
        );
        await tester.pumpAndSettle();
        expect(tester.getRect(actions), before);
        await captureUx(tester, boundary, 'mobile24_subject_320_$scale');
        await tester.tap(
          find.descendant(of: actions, matching: find.text('记进度')),
        );
        await tester.pumpAndSettle();
        expect(find.byTooltip('关闭'), findsOneWidget);
        await tester.tap(find.byTooltip('关闭'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('写短评'));
        await tester.pumpAndSettle();
        final comment = find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == '吐槽 / 短评',
        );
        expect(tester.widget<TextField>(comment).autofocus, isTrue);
        final editable = find.descendant(
          of: comment,
          matching: find.byType(EditableText),
        );
        expect(
          tester.widget<EditableText>(editable).focusNode.hasFocus,
          isTrue,
        );
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        await tester.enterText(comment, '这是一条测试短评');
        await tester.pump();
        await captureUx(tester, boundary, 'mobile24_comment_320_$scale');
        expect(tester.takeException(), isNull);
        // Closing before the debounce expires still persists, and reopening restores.
        tester.view.viewInsets = const FakeViewPadding();
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byTooltip('保存草稿并关闭'));
        await tester.tap(find.byTooltip('保存草稿并关闭'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('写短评'));
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(comment).controller!.text, '这是一条测试短评');
        session.switchAccountForTest();
        await tester.pumpAndSettle();
        expect(find.text('登录状态已变化，原账号短评草稿会保留'), findsOneWidget);
        expect(comment, findsNothing);
        await tester.tap(find.text('保存草稿并关闭'));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      },
    );
  }

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
        sessionProvider.overrideWith((ref) => _Session(api, cache)),
      ],
      child: const AppRouteScope(
        resolve: AppRouter.resolve,
        child: MaterialApp(home: SubjectDetailScreen(subject: _subject)),
      ),
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
    int subjectId, {
    String? username,
  }) async {
    if (failRead) throw StateError('disk unavailable');
    return readResult == null ? null : await readResult!.future;
  }

  @override
  Future<void> writeEpisodeCollections(
    int subjectId,
    List<UserEpisodeCollection> items, {
    String? username,
  }) async {
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
  void switchAccountForTest() => state = state.copyWith(
    user: const BangumiUser(
      id: 2,
      username: 'another',
      nickname: '另一个账号',
      avatarUrl: '',
    ),
  );
  _Session(BangumiApi api, SnapshotCache cache)
    : super(
        api,
        BangumiOAuth(),
        _Tokens(),
        snapshotCache: cache,
        syncStore: _EmptyQueue(),
      ) {
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
}

// Inject the storage boundary instead of overriding the session's internal
// method dispatch, so detail tests exercise the real collection editor.
class _EmptyQueue extends BangumiSyncStore {
  @override
  Future<List<PendingBangumiMutation>> pendingFor(
    String username, {
    bool includeBlocked = false,
  }) async => const [];
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
