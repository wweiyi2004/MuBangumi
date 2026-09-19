import '../navigation/app_destination.dart';
import 'package:flutter/material.dart';
import '../core/network/community_service.dart';
import 'community_hub_page.dart';

class DiscoveryHubPage extends StatefulWidget {
  const DiscoveryHubPage({
    super.key,
    this.initialTab = 0,
    this.communityService,
  });
  final int initialTab;
  final CommunityService? communityService;
  @override
  State<DiscoveryHubPage> createState() => _DiscoveryHubPageState();
}

class _DiscoveryHubPageState extends State<DiscoveryHubPage> {
  late int _tab = widget.initialTab;
  late final _opened = <int>{widget.initialTab};
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: EdgeInsets.fromLTRB(
          MediaQuery.sizeOf(context).width < 600 ? 16 : 30,
          24,
          MediaQuery.sizeOf(context).width < 600 ? 16 : 30,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '发现',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            DefaultTabController(
              length: 2,
              initialIndex: widget.initialTab,
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                dividerHeight: 0,
                indicatorSize: TabBarIndicatorSize.label,
                labelColor: Theme.of(context).colorScheme.primary,
                unselectedLabelColor: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant,
                labelStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
                labelPadding: const EdgeInsets.symmetric(horizontal: 14),
                tabs: const [
                  Tab(height: 44, text: '找作品'),
                  Tab(height: 44, text: '超展开'),
                ],
                onTap: (index) => setState(() {
                  _tab = index;
                  _opened.add(index);
                }),
              ),
            ),
          ],
        ),
      ),
      Expanded(
        child: IndexedStack(
          index: _tab,
          children: [
            _opened.contains(0)
                ? const DiscoverRoute(showTitle: false)
                : const SizedBox.shrink(),
            _opened.contains(1)
                ? CommunityPage(
                    service: widget.communityService,
                    showTitle: false,
                  )
                : const SizedBox.shrink(),
          ],
        ),
      ),
    ],
  );
}
