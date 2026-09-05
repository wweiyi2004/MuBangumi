import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/auth/bangumi_oauth.dart';
import 'package:mubangumi/core/network/bangumi_api.dart';
import 'package:mubangumi/core/network/bangumi_endpoints.dart';
import 'package:mubangumi/core/storage/bangumi_sync_store.dart';
import 'package:mubangumi/core/storage/token_store.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/state/session_controller.dart';
import 'package:mubangumi/widgets/sync_issues_sheet.dart';

void main() {
  testWidgets('sync issue sheet explains and discards a blocked mutation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final issue = PendingBangumiMutation(
      id: 7,
      username: 'tester',
      kind: BangumiMutationKind.episode,
      mutationKey: 'episode:42',
      payload: {
        'subject_id': _subject.id,
        'subject': _subject.toJson(),
        'episode_id': 42,
        'type': 2,
      },
      createdAt: DateTime(2026, 8, 23, 20),
      updatedAt: DateTime(2026, 8, 23, 21, 10),
      revision: 3,
      attempts: 2,
      blocked: true,
      lastError: '服务器拒绝了章节状态',
    );
    final controller = _SyncIssuesController([issue]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sessionProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: Scaffold(body: SyncIssuesSheet())),
      ),
    );
    await tester.pump();

    expect(find.text('同步问题'), findsOneWidget);
    expect(find.text(_subject.displayName), findsOneWidget);
    expect(find.text('章节 #42：看过'), findsOneWidget);
    expect(find.text('服务器拒绝了章节状态'), findsOneWidget);
    expect(find.textContaining('尝试 2 次'), findsOneWidget);

    await tester.tap(find.text('不再上传'));
    await tester.pumpAndSettle();
    expect(find.text('不再上传这条修改？'), findsOneWidget);
    expect(find.textContaining('下次刷新成功后将恢复为官网上的内容'), findsOneWidget);

    await tester.tap(find.text('停止上传'));
    await tester.pumpAndSettle();

    expect(controller.discardCalls, 1);
    expect(find.text('当前没有需要处理的同步问题'), findsOneWidget);
  });
}

const _subject = Subject(
  id: 8,
  name: 'Test subject',
  nameCn: '测试条目',
  imageUrl: '',
  summary: '',
  episodeCount: 12,
  score: 8,
  rank: 100,
  date: '2026-01-01',
);

class _SyncIssuesController extends SessionController {
  _SyncIssuesController(this.issues)
    : super(BangumiApi(), BangumiOAuth(), _HangingTokenStore()) {
    state = SessionState(
      phase: SessionPhase.signedIn,
      user: const BangumiUser(
        id: 1,
        username: 'tester',
        nickname: 'Tester',
        avatarUrl: '',
      ),
      blockedSyncCount: issues.length,
      pendingSyncCount: issues.length,
    );
  }

  final List<PendingBangumiMutation> issues;
  int discardCalls = 0;

  @override
  Future<List<PendingBangumiMutation>> blockedSyncMutations() async =>
      List.unmodifiable(issues);

  @override
  Future<String?> retryBlockedMutation(PendingBangumiMutation mutation) async {
    issues.removeWhere((item) => item.id == mutation.id);
    _updateCounts();
    return null;
  }

  @override
  Future<String?> discardBlockedMutation(
    PendingBangumiMutation mutation,
  ) async {
    discardCalls++;
    issues.removeWhere(
      (item) => item.id == mutation.id && item.revision == mutation.revision,
    );
    _updateCounts();
    return null;
  }

  @override
  Future<void> syncPendingChanges({bool retryBlocked = false}) async {
    issues.clear();
    _updateCounts();
  }

  @override
  Future<void> refresh({bool showIndicator = true}) async {}

  void _updateCounts() {
    state = state.copyWith(
      blockedSyncCount: issues.length,
      pendingSyncCount: issues.length,
    );
  }
}

class _HangingTokenStore extends TokenStore {
  final Completer<String?> _readCompleter = Completer<String?>();

  @override
  Future<String?> read() => _readCompleter.future;

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<DateTime?> readExpiresAt() async => null;

  @override
  Future<OAuthConfig?> readOAuthConfig() async => null;

  @override
  Future<BangumiNetworkRoute> readNetworkRoute() async =>
      BangumiNetworkRoute.official;
}
