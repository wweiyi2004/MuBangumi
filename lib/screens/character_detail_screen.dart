import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/network/bangumi_endpoints.dart';
import '../core/network/bangumi_support.dart';
import '../state/session_controller.dart';
import '../widgets/subject_widgets.dart';
import 'person_detail_screen.dart';
import 'subject_detail_screen.dart';

class CharacterDetailScreen extends ConsumerStatefulWidget {
  const CharacterDetailScreen({
    super.key,
    required this.characterId,
    this.seedName = '',
    this.seedImageUrl = '',
  });

  final int characterId;
  final String seedName;
  final String seedImageUrl;

  @override
  ConsumerState<CharacterDetailScreen> createState() =>
      _CharacterDetailScreenState();
}

class _CharacterDetailScreenState extends ConsumerState<CharacterDetailScreen> {
  CharacterDetail? _detail;
  List<MonoLinkedSubject> _subjects = const [];
  List<MonoLinkedPerson> _persons = const [];
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
        api.getCharacter(widget.characterId),
        api.getCharacterSubjects(widget.characterId),
        api.getCharacterPersons(widget.characterId),
      ]);
      if (!mounted) return;
      setState(() {
        _detail = results[0] as CharacterDetail;
        _subjects = results[1] as List<MonoLinkedSubject>;
        _persons = results[2] as List<MonoLinkedPerson>;
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
    final title = detail?.displayName ??
        (widget.seedName.isEmpty ? '角色' : widget.seedName);
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: '在 Bangumi 打开',
            onPressed: () => launchUrl(
              Uri.parse('https://bgm.tv/character/${widget.characterId}'),
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
                    title: '角色加载失败',
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
                  _MonoHeader(
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
                      if (detail?.gender.isNotEmpty == true)
                        detail!.gender,
                      if ((detail?.collectCount ?? 0) > 0)
                        '收藏 ${detail!.collectCount}',
                      if ((detail?.commentCount ?? 0) > 0)
                        '吐槽 ${detail!.commentCount}',
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
                  Text('出演条目', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  if (_subjects.isEmpty)
                    const EmptyState(
                      icon: Icons.movie_filter_outlined,
                      title: '暂无出演条目',
                      message: '这个角色还没有关联作品。',
                    )
                  else
                    for (final subject in _subjects.take(40))
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
                  Text('声优 / 相关人物',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  if (_persons.isEmpty)
                    const EmptyState(
                      icon: Icons.record_voice_over_outlined,
                      title: '暂无声优信息',
                      message: '这个角色还没有关联人物。',
                    )
                  else
                    for (final person in _persons.take(30))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: _Thumb(url: person.imageUrl, round: true),
                        title: Text(person.name),
                        subtitle: Text(
                          [
                            if (person.staff.isNotEmpty) person.staff,
                            if (person.subjectName.isNotEmpty)
                              person.subjectName,
                          ].join(' · '),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => PersonDetailScreen(
                              personId: person.id,
                              seedName: person.name,
                              seedImageUrl: person.imageUrl,
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

class _MonoHeader extends StatelessWidget {
  const _MonoHeader({
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
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 96,
                height: 128,
                child: imageUrl.isEmpty
                    ? ColoredBox(
                        color: scheme.surfaceContainerHighest,
                        child: const Icon(Icons.face_rounded, size: 40),
                      )
                    : CachedNetworkImage(
                        imageUrl: BangumiEndpoints.imageUrl(imageUrl),
                        fit: BoxFit.cover,
                        memCacheWidth: 192,
                        memCacheHeight: 256,
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
              round ? Icons.person_rounded : Icons.movie_filter_outlined,
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
