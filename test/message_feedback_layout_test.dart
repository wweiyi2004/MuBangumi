import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/pm_service.dart';
import 'package:mubangumi/features/pm/presentation/pm_queue_action.dart';
import 'package:mubangumi/models/pm_send_command.dart';
import 'package:mubangumi/screens/messages_page.dart';
import 'package:mubangumi/state/pm_send_queue_controller.dart';
import 'package:mubangumi/state/community_submission_controller.dart';
import 'package:mubangumi/widgets/content_loading.dart';
import 'package:mubangumi/widgets/community_submission_card.dart';
import 'support/memory_pm_outbox_repository.dart';
import 'support/ux_visuals.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'message header queue remains visible on a 360px conversation ($dark)',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final service = PmService();
        addTearDown(service.dispose);
        final queue = PmSendQueueController(
          repository: MemoryPmOutboxRepository(),
          service: service,
          currentUser: () => null,
        );
        queue.entries = [
          for (final status in [
            PmSendStatus.queued,
            PmSendStatus.sending,
            PmSendStatus.failed,
            PmSendStatus.uncertain,
          ])
            PmSendCommand(
              id: status.name,
              ownerId: 1,
              compose: true,
              receiver: '42',
              title: '标题',
              body: '正文',
              conversationId: '',
              threadId: '',
              related: '',
              createdAt: DateTime(2026),
              status: status,
            ),
        ];
        final gate = Completer<void>();
        final entry = CommunityPendingSubmission(
          title: '今晚一起看动画',
          content: '刚看完这集，想听听大家的想法。',
          isAccountCurrent: () => true,
          send: () => gate.future,
          finishDraft: (_) async {},
        );
        final key = GlobalKey();
        final theme = await uxTheme(tester, dark: dark);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              pmSendQueueProvider(service).overrideWith((ref) => queue),
            ],
            child: MaterialApp(
              theme: theme,
              home: Scaffold(
                body: RepaintBoundary(
                  key: key,
                  child: MessageHubLayout(
                    selectedTab: 0,
                    unreadCount: 2,
                    onSelectTab: (_) {},
                    onFriends: () {},
                    onScan: () {},
                    queueAction: PmQueueAction(service: service),
                    content: Column(
                      children: [
                        const LoadingStatus(active: true, message: '正在同步私信'),
                        CommunitySubmissionCard(entry: entry, onInspect: () {}),
                        const ContentSkeleton(rows: 2),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 310));
        expect(queue.activeCount, 2);
        expect(queue.attentionCount, 2);
        expect(find.byTooltip('发送队列 · 2 项需要处理'), findsOneWidget);
        final badge = tester.widget<Badge>(find.byType(Badge).first);
        expect(badge.backgroundColor, theme.colorScheme.error);
        expect(tester.takeException(), isNull);
        await captureUx(
          tester,
          key,
          'message-feedback-${dark ? 'dark' : 'light'}-360',
        );
        gate.complete();
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
