import 'dart:async';
import '../features/anime_appreciation/room_pages.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/notifications/schedule_reminder_service.dart';
import '../core/shortcuts/app_shortcut.dart';
import '../core/widget/home_widget_sync_host.dart';
import '../state/app_shortcut_controller.dart';
import '../state/shared_link_controller.dart';
import '../core/shortcuts/shared_bangumi_link.dart';
import 'shared_bangumi_link_page.dart';
import '../state/notify_controller.dart';
import '../state/rss_controller.dart';
import '../state/schedule_controller.dart';
import '../state/session_controller.dart';
import '../widgets/friend_qr_actions.dart';
import 'messages_page.dart';
import 'discovery_hub_page.dart';
import '../widgets/app_navigation_layout.dart';
import 'home_page.dart';
import 'library_page.dart';
import 'profile_page.dart';
import 'schedule_page.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;
  bool _libraryOpened = false;
  bool _discoverOpened = false;
  bool _communityOpened = false;
  bool _profileOpened = false;
  bool _handlingSharedLinks = false;
  late final AppLifecycleListener _lifecycleListener;
  late final RssController _rssController;
  late final StreamSubscription<ScheduleReminderTarget> _reminderSubscription;

  void _selectPage(int index) {
    setState(() {
      _index = index;
      if (index == 1) _libraryOpened = true;
      if (index == 2) _discoverOpened = true;
      if (index == 3) _communityOpened = true;
      if (index == 4) _profileOpened = true;
    });
    if (index == 3) {
      ref.read(notifyBadgeProvider.notifier).refresh();
    }
  }

  @override
  void initState() {
    super.initState();
    _rssController = ref.read(rssProvider.notifier);
    _lifecycleListener = AppLifecycleListener(
      onStateChange: (state) {
        _rssController.setForeground(state == AppLifecycleState.resumed);
        ref
            .read(notifyBadgeProvider.notifier)
            .setForeground(state == AppLifecycleState.resumed);
      },
      onResume: () {
        if (mounted) {
          unawaited(ref.read(sessionProvider.notifier).syncPendingChanges());
          unawaited(
            ref
                .read(scheduleProvider.notifier)
                .syncReminders(reportErrors: false),
          );
        }
      },
    );
    _reminderSubscription = ScheduleReminderService.shared.openedTargets.listen(
      (target) => unawaited(_openReminderTarget(target)),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _rssController.setForeground(
        WidgetsBinding.instance.lifecycleState == null ||
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
      );
      _consumeShortcut();
      unawaited(_consumeSharedLinks());
      final pending = ScheduleReminderService.shared.takePendingOpen();
      if (pending != null) unawaited(_openReminderTarget(pending));
      unawaited(
        ref.read(scheduleProvider.notifier).syncReminders(reportErrors: false),
      );
    });
  }

  @override
  void dispose() {
    _rssController.setForeground(false);
    _reminderSubscription.cancel();
    _lifecycleListener.dispose();
    super.dispose();
  }

  void _openSchedule() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SchedulePage()));
  }

  Future<void> _openReminderTarget(ScheduleReminderTarget target) async {
    await ref.read(scheduleProvider.notifier).setSeason(target.season);
    if (mounted) _openSchedule();
  }

  void _consumeShortcut() {
    if (!mounted) return;
    final shortcut = ref.read(pendingAppShortcutProvider.notifier).take();
    if (shortcut != null) unawaited(_openShortcut(shortcut));
  }

  Future<void> _consumeSharedLinks() async {
    if (!mounted || _handlingSharedLinks) return;
    _handlingSharedLinks = true;
    try {
      while (mounted &&
          ref.read(sessionProvider).phase == SessionPhase.signedIn) {
        final request = ref.read(pendingSharedLinksProvider.notifier).take();
        if (request == null) break;
        if (request.links.isEmpty) {
          await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('没有可打开的 Bangumi 链接'),
              content: const Text('请分享条目、人物、角色或话题的网页链接。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('知道了'),
                ),
              ],
            ),
          );
          continue;
        }
        final link = request.links.length == 1
            ? request.links.single
            : await showModalBottomSheet<SharedBangumiLink>(
                context: context,
                showDragHandle: true,
                useSafeArea: true,
                builder: (context) => ListView(
                  shrinkWrap: true,
                  children: [
                    const ListTile(title: Text('选择要打开的链接')),
                    for (final link in request.links)
                      ListTile(
                        title: Text(link.label),
                        subtitle: Text(link.url),
                        onTap: () => Navigator.pop(context, link),
                      ),
                  ],
                ),
              );
        if (!mounted) return;
        if (link != null &&
            ref.read(sessionProvider).phase == SessionPhase.signedIn) {
          unawaited(
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SharedBangumiLinkPage(link: link),
              ),
            ),
          );
        }
      }
    } finally {
      _handlingSharedLinks = false;
    }
  }

  Future<void> _openShortcut(AppShortcut shortcut) async {
    final user = ref.read(sessionProvider).user;
    switch (shortcut) {
      case AppShortcut.schedule:
        _openSchedule();
      case AppShortcut.scan:
        if (user != null && mounted) {
          await scanAndAddFriend(context, myUsername: user.username);
        }
      case AppShortcut.myQr:
        if (user != null && mounted) {
          await showMyFriendQr(context, user);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(pendingSharedLinksProvider, (_, next) {
      if (next.isNotEmpty) unawaited(_consumeSharedLinks());
    });
    ref.listen(pendingAppShortcutProvider, (previous, next) {
      if (next != null) _consumeShortcut();
    });
    final unread = ref.watch(notifyBadgeProvider.select((s) => s.unreadCount));
    final pages = [
      HomePage(onDiscover: () => _selectPage(2), onSchedule: _openSchedule),
      _libraryOpened ? const LibraryPage() : const SizedBox.shrink(),
      _discoverOpened ? const DiscoveryHubPage() : const SizedBox.shrink(),
      _communityOpened ? const MessagesPage() : const SizedBox.shrink(),
      _profileOpened ? const ProfilePage() : const SizedBox.shrink(),
    ];
    return HomeWidgetSyncHost(
      onOpenSchedule: _openSchedule,
      child: AppNavigationLayout(
        index: _index,
        onChanged: _selectPage,
        unreadCount: unread,
        onOpenSchedule: _openSchedule,
        body: Column(
          children: [
            const ParticipationReturnTile(),
            Expanded(
              child: IndexedStack(index: _index, children: pages),
            ),
          ],
        ),
      ),
    );
  }
}
