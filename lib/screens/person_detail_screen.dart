import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/network/bangumi_endpoints.dart';
import '../core/network/bangumi_support.dart';
import '../state/session_controller.dart';
import '../widgets/subject_widgets.dart';
import 'character_detail_screen.dart';
import 'subject_detail_screen.dart';

class PersonDetailScreen extends ConsumerStatefulWidget {
  const PersonDetailScreen({
    super.key,
    required this.personId,
    this.seedName = '',
    this.seedImageUrl = '',
  });

  final int personId;
  final String seedName;
  final String seedImageUrl;

  @override
  ConsumerState<PersonDetailScreen> createState() => _PersonDetailScreenState();
}

class _PersonDetailScreenState extends ConsumerState<PersonDetailScreen> {
  PersonDetail? _detail;
  List<MonoLinkedSubject> _subjects = const [];
  List<MonoLinkedCharacter> _characters = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(bangumiApiProvider);
      final results = await Future.wait([
        api.getPerson(widget.personId),
        api.getPersonSubjects(widget.personId),
        api.getPersonCharacters(widget.personId),
      ]);
      if (!mounted) return;
      setState(() {
        _detail = results[0] as PersonDetail;
        _subjects = results[1] as List<MonoLinkedSubject>;
        _characters = results[2] as List<MonoLinkedCharacter>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final title =
        detail?.displayName ?? (widget.seedName.isEmpty ? '人物' : widget.seedName);
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: '在 Bangumi 打开',
            onPressed: () => launchUrl(
              Uri.parse('https://bgm.tv/person/${widget.personId}'),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.open_in_new_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading && detail == null
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : _error != null && detail == null
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  EmptyState(
                    icon: Icons.error_outline_rounded,
                    title: '人物加载失败',
                    message: _error!,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _load, child: const Text('重试')),
                ],
              )
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                children: [
                  _PersonHeader(
                    name: detail?.displayName ?? title,
                    subtitle: detail != null &&
                            detail.name.isNotEmpty &&
                            detail.name != detail.displayName
                        ? detail.name
                        : '',
                    imageUrl: detail?.imageUrl.isNotEmpty == true
                        ? detail!.imageUrl
                        : widget.seedImageUrl,
                    meta: [
                      ...?detail?.career,
                      if (detail?.gender.isNotEmpty == true) detail!.gender,
                      if ((detail?.collectCount ?? 0) > 0)
                        '收藏 ${detail!.collectCount}',
                    ],
                  ),
                  if (detail?.summary.isNotEmpty == true) ...[
                    const SizedBox(height: 18),
                    Text('简介', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                      detail!.summary.replaceAll('\r\n', '\n'),
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                  const SizedBox(height: 22),
                  Text('参与作品', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  if (_subjects.isEmpty)
                    const EmptyState(
                      icon: Icons.movie_filter_outlined,
                      title: '暂无参与作品',
                      message: '这个人物还没有关联条目。',
                    )
                  else
                    for (final subject in _subjects.take(50))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: _Thumb(url: subject.imageUrl),
                        title: Text(subject.displayName),
                        subtitle: Text(
                          [
                            subject.type.label,
                            if (subject.staff.isNotEmpty) subject.staff,
                          ].join(' · '),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => SubjectDetailScreen(
                              subject: subject.toSubject(),
                            ),
                          ),
                        ),
                      ),
                  const SizedBox(height: 18),
                  Text('饰演角色', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  if (_characters.isEmpty)
                    const EmptyState(
                      icon: Icons.face_outlined,
                      title: '暂无饰演角色',
                      message: '这个人物还没有关联角色。',
                    )
                  else
                    for (final character in _characters.take(50))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: _Thumb(url: character.imageUrl, round: true),
                        title: Text(character.name),
                        subtitle: Text(
                          [
                            if (character.staff.isNotEmpty) character.staff,
                            if (character.subjectName.isNotEmpty)
                              character.subjectName,
                          ].join(' · '),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => CharacterDetailScreen(
                              characterId: character.id,
                              seedName: character.name,
                              seedImageUrl: character.imageUrl,
                            ),
                          ),
                        ),
                      ),
                ],
              ),
      ),
    );
  }
}

class _PersonHeader extends StatelessWidget {
  const _PersonHeader({
    required this.name,
    required this.subtitle,
    required this.imageUrl,
    required this.meta,
  });

  final String name;
  final String subtitle;
  final String imageUrl;
  final List<String> meta;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(48),
              child: SizedBox(
                width: 96,
                height: 96,
                child: imageUrl.isEmpty
                    ? ColoredBox(
                        color: scheme.surfaceContainerHighest,
                        child: const Icon(Icons.person_rounded, size: 40),
                      )
                    : CachedNetworkImage(
                        imageUrl: BangumiEndpoints.imageUrl(imageUrl),
                        fit: BoxFit.cover,
                        memCacheWidth: 192,
                        memCacheHeight: 192,
                        errorWidget: (_, _, _) => ColoredBox(
                          color: scheme.surfaceContainerHighest,
                          child: const Icon(Icons.broken_image_outlined),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: Theme.of(context).textTheme.headlineSmall),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final item in meta)
                          Chip(
                            label: Text(item),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url, this.round = false});

  final String url;
  final bool round;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final child = url.isEmpty
        ? ColoredBox(
            color: scheme.surfaceContainerHighest,
            child: Icon(
              round ? Icons.face_rounded : Icons.movie_filter_outlined,
              size: 20,
            ),
          )
        : CachedNetworkImage(
            imageUrl: BangumiEndpoints.imageUrl(url),
            fit: BoxFit.cover,
            memCacheWidth: 96,
            memCacheHeight: 96,
            errorWidget: (_, _, _) => ColoredBox(
              color: scheme.surfaceContainerHighest,
              child: const Icon(Icons.broken_image_outlined, size: 18),
            ),
          );
    if (round) {
      return CircleAvatar(
        radius: 22,
        backgroundColor: scheme.surfaceContainerHighest,
        child: ClipOval(child: SizedBox(width: 44, height: 44, child: child)),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(width: 44, height: 60, child: child),
    );
  }
}
