import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../core/layout/app_layout.dart';
import '../core/widget/home_widget_sync_host.dart';
import '../state/background_controller.dart';
import '../state/notify_controller.dart';
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
  bool _scheduleOpened = false;
  bool _profileOpened = false;

  static const _destinations = [
    (icon: Icons.home_outlined, selected: Icons.home_rounded, label: '首页'),
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
    (
      icon: Icons.calendar_month_outlined,
      selected: Icons.calendar_month_rounded,
      label: '新番表',
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
      if (index == 3) _scheduleOpened = true;
      if (index == 4) _communityOpened = true;
      if (index == 5) _profileOpened = true;
    });
    // Refresh badge when opening 我的.
    if (index == 5) {
      ref.read(notifyBadgeProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(notifyBadgeProvider.select((s) => s.unreadCount));
    final pages = [
      HomePage(onDiscover: () => _selectPage(2)),
      _libraryOpened ? const LibraryPage() : const SizedBox.shrink(),
      _discoverOpened ? const DiscoverPage() : const SizedBox.shrink(),
      _scheduleOpened ? const SchedulePage() : const SizedBox.shrink(),
      _communityOpened ? const CommunityPage() : const SizedBox.shrink(),
      _profileOpened ? const ProfilePage() : const SizedBox.shrink(),
    ];
    final desktop = AppLayout.isDesktop(context);
    final navHeight = AppLayout.navHeight(context);
    final glassBg = ref.watch(
      backgroundSettingsProvider.select((s) => s.isActive),
    );
    return HomeWidgetSyncHost(
      onOpenSchedule: () => _selectPage(3),
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
                        count: i == 5 ? unread : 0,
                      ),
                      selectedIcon: _badgedIcon(
                        Icon(_destinations[i].selected),
                        count: i == 5 ? unread : 0,
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
    this.glass = false,
  });

  final int index;
  final ValueChanged<int> onChanged;
  final int unreadCount;
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: glass ? scheme.surface.withValues(alpha: 0.55) : scheme.surface,
      child: Container(
        width: 230,
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(26, 28, 20, 30),
              child: Row(
                children: [
                  BrandMark(size: 42),
                  SizedBox(width: 13),
                  Text(
                    'MuBangumi',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            for (var i = 0; i < _HomeShellState._destinations.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 3,
                ),
                child: ListTile(
                  selected: index == i,
                  selectedTileColor: scheme.primaryContainer.withValues(
                    alpha: .65,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  leading: i == 5 && unreadCount > 0
                      ? Badge(
                          label: Text(
                            unreadCount > 99 ? '99+' : '$unreadCount',
                          ),
                          child: Icon(
                            index == i
                                ? _HomeShellState._destinations[i].selected
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
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  onTap: () => onChanged(i),
                ),
              ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Powered by Bangumi API',
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
