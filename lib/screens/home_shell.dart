import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../core/layout/app_layout.dart';
import '../core/notifications/schedule_reminder_service.dart';
import '../core/shortcuts/app_shortcut.dart';
import '../core/widget/home_widget_sync_host.dart';
import '../state/app_shortcut_controller.dart';
import '../state/background_controller.dart';
import '../state/notify_controller.dart';
import '../state/schedule_controller.dart';
import '../state/session_controller.dart';
import '../widgets/friend_qr_actions.dart';
import 'community_hub_page.dart';
import 'discover_page.dart';
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
  late final AppLifecycleListener _lifecycleListener;
  late final StreamSubscription<ScheduleReminderTarget> _reminderSubscription;

  static const _destinations = [
    (
      icon: Icons.play_circle_outline_rounded,
      selected: Icons.play_circle_rounded,
      label: '追番',
    ),
    (
      icon: Icons.video_library_outlined,
      selected: Icons.video_library_rounded,
      label: '收藏',
    ),
    (
      icon: Icons.explore_outlined,
      selected: Icons.explore_rounded,
      label: '发现',
    ),
    (icon: Icons.forum_outlined, selected: Icons.forum_rounded, label: '社区'),
    (
      icon: Icons.person_outline_rounded,
      selected: Icons.person_rounded,
      label: '我的',
    ),
  ];

  void _selectPage(int index) {
    setState(() {
      _index = index;
      if (index == 1) _libraryOpened = true;
      if (index == 2) _discoverOpened = true;
      if (index == 3) _communityOpened = true;
      if (index == 4) _profileOpened = true;
    });
    // Refresh badge when opening 我的.
    if (index == 4) {
      ref.read(notifyBadgeProvider.notifier).refresh();
    }
  }

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onStateChange: (state) {
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
      _consumeShortcut();
      final pending = ScheduleReminderService.shared.takePendingOpen();
      if (pending != null) unawaited(_openReminderTarget(pending));
      unawaited(
        ref.read(scheduleProvider.notifier).syncReminders(reportErrors: false),
      );
    });
  }

  @override
  void dispose() {
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
    ref.listen(pendingAppShortcutProvider, (previous, next) {
      if (next != null) _consumeShortcut();
    });
    final unread = ref.watch(notifyBadgeProvider.select((s) => s.unreadCount));
    final pages = [
      HomePage(onDiscover: () => _selectPage(2), onSchedule: _openSchedule),
      _libraryOpened ? const LibraryPage() : const SizedBox.shrink(),
      _discoverOpened ? const DiscoverPage() : const SizedBox.shrink(),
      _communityOpened ? const CommunityPage() : const SizedBox.shrink(),
      _profileOpened ? const ProfilePage() : const SizedBox.shrink(),
    ];
    final desktop = AppLayout.isDesktop(context);
    final navHeight = AppLayout.navHeight(context);
    final glassBg = ref.watch(
      backgroundSettingsProvider.select((s) => s.isActive),
    );
    return HomeWidgetSyncHost(
      onOpenSchedule: _openSchedule,
      child: Scaffold(
        backgroundColor: glassBg ? Colors.transparent : null,
        body: SafeArea(
          child: Row(
            children: [
              if (desktop)
                _DesktopNavigation(
                  index: _index,
                  onChanged: _selectPage,
                  unreadCount: unread,
                  glass: glassBg,
                  onOpenSchedule: _openSchedule,
                ),
              Expanded(
                child: IndexedStack(index: _index, children: pages),
              ),
            ],
          ),
        ),
        bottomNavigationBar: desktop
            ? null
            : NavigationBar(
                height: navHeight,
                selectedIndex: _index,
                labelBehavior: AppLayout.navLabelBehavior(context),
                onDestinationSelected: _selectPage,
                destinations: [
                  for (var i = 0; i < _destinations.length; i++)
                    NavigationDestination(
                      icon: _badgedIcon(
                        Icon(_destinations[i].icon),
                        count: i == 4 ? unread : 0,
                      ),
                      selectedIcon: _badgedIcon(
                        Icon(_destinations[i].selected),
                        count: i == 4 ? unread : 0,
                      ),
                      label: _destinations[i].label,
                    ),
                ],
              ),
      ),
    );
  }

  Widget _badgedIcon(Widget icon, {required int count}) {
    if (count <= 0) return icon;
    final label = count > 99 ? '99+' : '$count';
    return Badge(label: Text(label), child: icon);
  }
}

class _DesktopNavigation extends StatelessWidget {
  const _DesktopNavigation({
    required this.index,
    required this.onChanged,
    required this.unreadCount,
    required this.onOpenSchedule,
    this.glass = false,
  });

  final int index;
  final ValueChanged<int> onChanged;
  final int unreadCount;
  final VoidCallback onOpenSchedule;
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: glass ? scheme.surface.withValues(alpha: 0.55) : scheme.surface,
      child: Container(
        width: 190,
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 24, 16, 26),
              child: Row(
                children: [
                  BrandMark(size: 36),
                  SizedBox(width: 11),
                  Text(
                    'MuBangumi',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (var i = 0; i < _HomeShellState._destinations.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 3,
                      ),
                      child: ListTile(
                        selected: index == i,
                        selectedColor: scheme.primary,
                        selectedTileColor: scheme.primaryContainer.withValues(
                          alpha: .28,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        leading: i == 4 && unreadCount > 0
                            ? Badge(
                                label: Text(
                                  unreadCount > 99 ? '99+' : '$unreadCount',
                                ),
                                child: Icon(
                                  index == i
                                      ? _HomeShellState
                                            ._destinations[i]
                                            .selected
                                      : _HomeShellState._destinations[i].icon,
                                ),
                              )
                            : Icon(
                                index == i
                                    ? _HomeShellState._destinations[i].selected
                                    : _HomeShellState._destinations[i].icon,
                              ),
                        title: Text(
                          _HomeShellState._destinations[i].label,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        onTap: () => onChanged(i),
                      ),
                    ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      leading: const Icon(Icons.calendar_month_outlined),
                      title: const Text(
                        '新番表',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      trailing: const Icon(Icons.open_in_new_rounded, size: 17),
                      onTap: onOpenSchedule,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 16, 20),
              child: Text(
                '数据来自 Bangumi',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
