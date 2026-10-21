import '../widgets/bounded_image.dart';
import '../core/theme/anime_icon.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/insights/subject_meta_insights.dart';
import '../core/network/bangumi_support.dart';
import '../models/bangumi_models.dart';
import '../navigation/app_destination.dart';
import '../state/session_controller.dart';

class SubjectStaffPage extends ConsumerStatefulWidget {
  const SubjectStaffPage({
    super.key,
    required this.subject,
    this.seed = const [],
  });
  final Subject subject;
  final List<SubjectPerson> seed;
  @override
  ConsumerState<SubjectStaffPage> createState() => _SubjectStaffPageState();
}

class _SubjectStaffPageState extends ConsumerState<SubjectStaffPage> {
  late List<SubjectPerson> _people = widget.seed;
  bool _loading = false;
  String? _error;
  String _query = '';
  @override
  void initState() {
    super.initState();
    if (_people.isEmpty) unawaited(Future<void>.microtask(_load));
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final people = await ref
          .read(bangumiApiProvider)
          .getSubjectPersons(widget.subject.id);
      if (mounted) setState(() => _people = people);
    } catch (_) {
      if (mounted) setState(() => _error = '制作人员暂时无法加载，请重试');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final groups = groupSubjectStaffByRole(
      _people
          .where(
            (person) =>
                query.isEmpty ||
                '${person.displayName} ${person.name} ${person.relation}'
                    .toLowerCase()
                    .contains(query),
          )
          .toList(),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('制作人员'),
        actions: [
          IconButton(
            tooltip: '刷新制作人员',
            onPressed: _loading ? null : _load,
            icon: const AnimeIcon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.subject.displayName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      onChanged: (value) => setState(() => _query = value),
                      decoration: const InputDecoration(
                        hintText: '搜索名字或职位',
                        prefixIcon: AnimeIcon(Icons.search_rounded),
                      ),
                    ),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: LinearProgressIndicator(),
                      ),
                    if (_error != null)
                      TextButton(onPressed: _load, child: Text(_error!)),
                    if (!_loading && _error == null && groups.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('暂无匹配的制作人员'),
                      ),
                  ],
                ),
              ),
            ),
            for (final group in groups) ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    '${group.role} · ${group.people.length} 位',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList.builder(
                  itemCount: group.people.length,
                  itemBuilder: (context, index) {
                    final person = group.people[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      leading: CircleAvatar(
                        radius: 24,
                        backgroundImage: person.imageUrl.isEmpty
                            ? null
                            : boundedAvatarProvider(
                                context,
                                person.imageUrl,
                                diameter: 48,
                              ),
                        child: person.imageUrl.isEmpty
                            ? const AnimeIcon(Icons.person_outline_rounded)
                            : null,
                      ),
                      title: Text(person.displayName),
                      subtitle: person.name != person.displayName
                          ? Text(person.name)
                          : null,
                      trailing: const AnimeIcon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => PersonRoute(
                            personId: person.id,
                            seedName: person.displayName,
                            seedImageUrl: person.imageUrl,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }
}
