import 'package:flutter/material.dart';

import '../app.dart';
import '../core/widget/home_widget_sync_host.dart';
import 'community_hub_page.dart';
import 'discover_page.dart';
import 'home_page.dart';
import 'library_page.dart';
import 'profile_page.dart';
import 'schedule_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  bool _communityOpened = false;
  bool _scheduleOpened = false;

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
      if (index == 3) _scheduleOpened = true;
      if (index == 4) _communityOpened = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(onDiscover: () => _selectPage(2)),
      const LibraryPage(),
      const DiscoverPage(),
      _scheduleOpened ? const SchedulePage() : const SizedBox.shrink(),
      _communityOpened ? const CommunityPage() : const SizedBox.shrink(),
      const ProfilePage(),
    ];
    final desktop = MediaQuery.sizeOf(context).width >= 900;
    return HomeWidgetSyncHost(
      onOpenSchedule: () => _selectPage(3),
      child: Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              if (desktop)
                _DesktopNavigation(index: _index, onChanged: _selectPage),
              Expanded(
                child: IndexedStack(index: _index, children: pages),
              ),
            ],
          ),
        ),
        bottomNavigationBar: desktop
            ? null
            : NavigationBar(
                selectedIndex: _index,
                labelBehavior:
                    NavigationDestinationLabelBehavior.onlyShowSelected,
                onDestinationSelected: _selectPage,
                destinations: [
                  for (final destination in _destinations)
                    NavigationDestination(
                      icon: Icon(destination.icon),
                      selectedIcon: Icon(destination.selected),
                      label: destination.label,
                    ),
                ],
              ),
      ),
    );
  }
}

class _DesktopNavigation extends StatelessWidget {
  const _DesktopNavigation({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
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
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
                child: ListTile(
                  selected: index == i,
                  selectedTileColor: scheme.primaryContainer.withValues(
                    alpha: .65,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  leading: Icon(
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
