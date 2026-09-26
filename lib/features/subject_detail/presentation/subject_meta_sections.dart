import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../core/network/bangumi_support.dart';
import '../../../core/insights/subject_meta_insights.dart';
import '../../../core/network/bangumi_endpoints.dart';
import '../../../widgets/subject_widgets.dart';
import '../../../core/theme/app_tokens.dart';

class SubjectMetaCount extends StatelessWidget {
  const SubjectMetaCount(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: Theme.of(context).textTheme.labelLarge?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

class _HorizontalCardRail extends StatefulWidget {
  const _HorizontalCardRail({
    required this.itemCount,
    required this.itemWidth,
    required this.height,
    required this.itemBuilder,
  });

  final int itemCount;
  final double itemWidth;
  final double height;
  final Widget Function(BuildContext context, int index) itemBuilder;

  @override
  State<_HorizontalCardRail> createState() => _HorizontalCardRailState();
}

class _HorizontalCardRailState extends State<_HorizontalCardRail> {
  final ScrollController _controller = ScrollController();
  bool _canGoBack = false;
  bool _canGoForward = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncButtons);
  }

  @override
  void didUpdateWidget(covariant _HorizontalCardRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemCount != widget.itemCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncButtons());
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_syncButtons)
      ..dispose();
    super.dispose();
  }

  void _syncButtons() {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    final canGoBack = position.pixels > position.minScrollExtent + 2;
    final canGoForward = position.pixels < position.maxScrollExtent - 2;
    if (canGoBack == _canGoBack && canGoForward == _canGoForward) return;
    setState(() {
      _canGoBack = canGoBack;
      _canGoForward = canGoForward;
    });
  }

  void _move(double direction) {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final target = (position.pixels + position.viewportDimension * direction)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncButtons());
    final showArrows = MediaQuery.sizeOf(context).width >= 600;
    return SizedBox(
      height: widget.height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ListView.separated(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            itemCount: widget.itemCount,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) => SizedBox(
              width: widget.itemWidth,
              child: widget.itemBuilder(context, index),
            ),
          ),
          if (showArrows && _canGoBack)
            Positioned(
              left: 4,
              child: IconButton.filledTonal(
                tooltip: '向前浏览',
                onPressed: () => _move(-.8),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
            ),
          if (showArrows && _canGoForward)
            Positioned(
              right: 4,
              child: IconButton.filledTonal(
                tooltip: '继续浏览',
                onPressed: () => _move(.8),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ),
        ],
      ),
    );
  }
}

class SubjectCharacterRail extends StatelessWidget {
  const SubjectCharacterRail({
    super.key,
    required this.characters,
    required this.onOpen,
  });

  final List<SubjectCharacter> characters;
  final ValueChanged<SubjectCharacter> onOpen;

  @override
  Widget build(BuildContext context) => _HorizontalCardRail(
    itemCount: characters.length,
    itemWidth: 216,
    height: 112,
    itemBuilder: (context, index) {
      final character = characters[index];
      return _CharacterCard(
        character: character,
        onTap: () => onOpen(character),
      );
    },
  );
}

class _CharacterCard extends StatelessWidget {
  const _CharacterCard({required this.character, required this.onTap});

  final SubjectCharacter character;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: AppRadius.medium,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              _MetaImage(
                url: character.imageUrl,
                width: 62,
                height: 92,
                icon: Icons.face_outlined,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      character.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (character.relation.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        character.relation,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      character.actorNames.isEmpty
                          ? '声优未收录'
                          : 'CV · ${character.actorNames.join(' / ')}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SubjectStaffRoleGroups extends StatefulWidget {
  const SubjectStaffRoleGroups({
    super.key,
    required this.people,
    required this.onOpen,
  });

  final List<SubjectPerson> people;
  final ValueChanged<SubjectPerson> onOpen;

  @override
  State<SubjectStaffRoleGroups> createState() => _StaffRoleGroupsState();
}

class _StaffRoleGroupsState extends State<SubjectStaffRoleGroups> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant SubjectStaffRoleGroups oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.people.length != widget.people.length) _expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    final groups = groupSubjectStaffByRole(widget.people);
    final previewCount = MediaQuery.sizeOf(context).width < 600 ? 4 : 6;
    final visibleCount = _expanded
        ? groups.length
        : groups.length < previewCount
        ? groups.length
        : previewCount;
    final visibleGroups = groups.take(visibleCount).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final group in visibleGroups) ...[
          _StaffRoleRow(group: group, onOpen: widget.onOpen),
          if (group != visibleGroups.last) const SizedBox(height: 16),
        ],
        if (groups.length > previewCount) ...[
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(
                _expanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
              ),
              label: Text(_expanded ? '收起职位' : '展开全部 ${groups.length} 类职位'),
            ),
          ),
        ],
      ],
    );
  }
}

class _StaffRoleRow extends StatelessWidget {
  const _StaffRoleRow({required this.group, required this.onOpen});

  final SubjectStaffRoleGroup group;
  final ValueChanged<SubjectPerson> onOpen;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              group.role,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          SubjectMetaCount('${group.people.length} 位'),
        ],
      ),
      const SizedBox(height: 8),
      _HorizontalCardRail(
        itemCount: group.people.length,
        itemWidth: 210,
        height: 82,
        itemBuilder: (context, index) {
          final person = group.people[index];
          return _StaffPersonCard(person: person, onTap: () => onOpen(person));
        },
      ),
    ],
  );
}

class _StaffPersonCard extends StatelessWidget {
  const _StaffPersonCard({required this.person, required this.onTap});

  final SubjectPerson person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final identity = person.type == 2
        ? '公司'
        : person.type == 3
        ? '团体'
        : person.career.join(' / ');
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: AppRadius.medium,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              _MetaImage(
                url: person.imageUrl,
                width: 48,
                height: 48,
                round: person.type != 2,
                icon: person.type == 2
                    ? Icons.business_outlined
                    : Icons.person_outline_rounded,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      person.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (identity.isNotEmpty) identity,
                        if (person.eps.isNotEmpty) '集数 ${person.eps}',
                        if (identity.isEmpty && person.eps.isEmpty) '人物资料',
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SubjectRelatedRail extends StatelessWidget {
  const SubjectRelatedRail({
    super.key,
    required this.subjects,
    required this.onOpen,
  });

  final List<RelatedSubject> subjects;
  final ValueChanged<RelatedSubject> onOpen;

  @override
  Widget build(BuildContext context) => _HorizontalCardRail(
    itemCount: subjects.length,
    itemWidth: 154,
    height: subjectPosterItemHeight(
      154,
      1,
      textScaler: MediaQuery.textScalerOf(context),
    ),
    itemBuilder: (context, index) {
      final item = subjects[index];
      return SubjectPosterCard(
        subject: item.toSubject(),
        statusLabel: item.relation.isEmpty ? '关联作品' : item.relation,
        metaLabel: item.type.label,
        onTap: () => onOpen(item),
      );
    },
  );
}

class _MetaImage extends StatelessWidget {
  const _MetaImage({
    required this.url,
    required this.width,
    required this.height,
    required this.icon,
    this.round = false,
  });

  final String url;
  final double width;
  final double height;
  final IconData icon;
  final bool round;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final borderRadius = BorderRadius.circular(round ? width / 2 : 12);
    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        width: width,
        height: height,
        child: url.isEmpty
            ? ColoredBox(
                color: scheme.surfaceContainerHighest,
                child: Icon(icon, color: scheme.onSurfaceVariant),
              )
            : CachedNetworkImage(
                imageUrl: BangumiEndpoints.imageUrl(url),
                fit: BoxFit.cover,
                memCacheWidth: (width * 2).round(),
                memCacheHeight: (height * 2).round(),
                errorWidget: (_, _, _) => ColoredBox(
                  color: scheme.surfaceContainerHighest,
                  child: Icon(icon, color: scheme.onSurfaceVariant),
                ),
              ),
      ),
    );
  }
}

class SubjectMetaSection extends StatelessWidget {
  const SubjectMetaSection({
    super.key,
    required this.title,
    required this.loading,
    required this.empty,
    required this.child,
    this.trailing,
    this.error,
    this.onRetry,
  });

  final String title;
  final bool loading;
  final bool empty;
  final Widget child;
  final Widget? trailing;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 10),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (empty)
            error != null
                ? Row(
                    children: [
                      Expanded(
                        child: Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                      if (onRetry != null)
                        TextButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: const Text('重试'),
                        ),
                    ],
                  )
                : Text(
                    '暂无数据',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  )
          else
            child,
        ],
      ),
    );
  }
}
