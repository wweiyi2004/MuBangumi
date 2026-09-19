import 'package:flutter/material.dart';
import '../widgets/brand_mark.dart';
import '../core/layout/app_layout.dart';
import 'app_background.dart';

class AppNavigationLayout extends StatelessWidget {
  const AppNavigationLayout({
    super.key,
    required this.index,
    required this.onChanged,
    required this.unreadCount,
    required this.onOpenSchedule,
    required this.body,
  });
  final int index, unreadCount;
  final ValueChanged<int> onChanged;
  final VoidCallback onOpenSchedule;
  final Widget body;
  static const destinations = [
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
    (
      icon: Icons.chat_bubble_outline_rounded,
      selected: Icons.chat_bubble_rounded,
      label: '消息',
    ),
    (
      icon: Icons.person_outline_rounded,
      selected: Icons.person_rounded,
      label: '我的',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final desktop = AppLayout.isDesktop(context);
    Widget icon(int i, bool selected) {
      final child = Icon(
        selected ? destinations[i].selected : destinations[i].icon,
      );
      return i == 3 && unreadCount > 0
          ? Badge(
              label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
              child: child,
            )
          : child;
    }

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (desktop)
              _DesktopNavigation(
                index: index,
                onChanged: onChanged,
                unreadCount: unreadCount,
                onOpenSchedule: onOpenSchedule,
              ),
            Expanded(child: body),
          ],
        ),
      ),
      bottomNavigationBar: desktop
          ? null
          : NavigationBar(
              height: AppLayout.navHeight(context),
              selectedIndex: index,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              onDestinationSelected: onChanged,
              destinations: [
                for (var i = 0; i < destinations.length; i++)
                  NavigationDestination(
                    icon: icon(i, false),
                    selectedIcon: icon(i, true),
                    label: destinations[i].label,
                  ),
              ],
            ),
    );
  }
}

class _DesktopNavigation extends StatelessWidget {
  const _DesktopNavigation({
    required this.index,
    required this.onChanged,
    required this.unreadCount,
    required this.onOpenSchedule,
  });

  final int index;
  final ValueChanged<int> onChanged;
  final int unreadCount;
  final VoidCallback onOpenSchedule;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassPanel(
      borderRadius: 0,
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
                  Expanded(
                    child: Text(
                      'MuBangumi',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (
                    var i = 0;
                    i < AppNavigationLayout.destinations.length;
                    i++
                  )
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
                        leading: i == 3 && unreadCount > 0
                            ? Badge(
                                label: Text(
                                  unreadCount > 99 ? '99+' : '$unreadCount',
                                ),
                                child: Icon(
                                  index == i
                                      ? AppNavigationLayout
                                            .destinations[i]
                                            .selected
                                      : AppNavigationLayout
                                            .destinations[i]
                                            .icon,
                                ),
                              )
                            : Icon(
                                index == i
                                    ? AppNavigationLayout
                                          .destinations[i]
                                          .selected
                                    : AppNavigationLayout.destinations[i].icon,
                              ),
                        title: Text(
                          AppNavigationLayout.destinations[i].label,
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
