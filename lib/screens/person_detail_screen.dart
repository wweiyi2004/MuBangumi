import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/insights/company_insights.dart';
import '../core/network/bangumi_endpoints.dart';
import '../core/network/bangumi_support.dart';
import '../models/bangumi_models.dart';
import '../state/session_controller.dart';
import '../widgets/subject_widgets.dart';
import 'character_detail_screen.dart';
import 'subject_detail_screen.dart';

const _companyDetailBatchSize = 36;
const _companyDetailConcurrency = 4;

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
  final Map<int, Subject> _companySubjectDetails = {};
  final Set<int> _companyDetailFailures = {};
  bool _loadingCompanyDetails = false;
  String? _companyDetailMessage;
  String? _selectedCompanyRole;
  int _companyDetailRequestId = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _companyDetailRequestId++;
      _loading = true;
      _error = null;
      _companySubjectDetails.clear();
      _companyDetailFailures.clear();
      _loadingCompanyDetails = false;
      _companyDetailMessage = null;
      _selectedCompanyRole = null;
    });
    final api = ref.read(bangumiApiProvider);
    Object? detailError;
    // Independent sections: one failing request must not discard the others.
    final results = await Future.wait<Object?>([
      api.getPerson(widget.personId).then<Object?>((value) => value).catchError(
        (Object error) {
          detailError = error;
          return null;
        },
      ),
      api
          .getPersonSubjects(widget.personId)
          .then<Object?>((v) => v)
          .catchError((Object _) => const <MonoLinkedSubject>[]),
      api
          .getPersonCharacters(widget.personId)
          .then<Object?>((v) => v)
          .catchError((Object _) => const <MonoLinkedCharacter>[]),
    ]);
    if (!mounted) return;
    final detail = results[0] as PersonDetail?;
    setState(() {
      if (detail != null) _detail = detail;
      _subjects = results[1] as List<MonoLinkedSubject>;
      _characters = results[2] as List<MonoLinkedCharacter>;
      _loading = false;
      if (detail == null) {
        _error =
            detailError?.toString().replaceFirst(
              RegExp(r'^.*Exception:\s*'),
              '',
            ) ??
            '人物信息加载失败';
      }
    });
    if (detail != null && detail.type == 2) {
      unawaited(_loadMoreCompanyDetails());
    }
  }

  Future<void> _loadMoreCompanyDetails({bool retryFailures = false}) async {
    if (_loadingCompanyDetails) return;
    final requestId = _companyDetailRequestId;
    if (retryFailures) _companyDetailFailures.clear();
    final uniqueSubjects = uniqueCompanyWorkLinks(_subjects);
    final pending = uniqueSubjects
        .where(
          (item) =>
              !_companySubjectDetails.containsKey(item.id) &&
              !_companyDetailFailures.contains(item.id),
        )
        .take(_companyDetailBatchSize)
        .toList();
    if (pending.isEmpty) return;

    setState(() {
      _loadingCompanyDetails = true;
      _companyDetailMessage = null;
    });
    final api = ref.read(bangumiApiProvider);
    var successCount = 0;
    var failureCount = 0;
    for (
      var start = 0;
      start < pending.length;
      start += _companyDetailConcurrency
    ) {
      final end = (start + _companyDetailConcurrency).clamp(0, pending.length);
      final chunk = pending.sublist(start, end);
      final results = await Future.wait([
        for (final link in chunk)
          (() async {
            try {
              return MapEntry<int, Subject?>(
                link.id,
                await api.getSubject(link.id),
              );
            } catch (_) {
              return MapEntry<int, Subject?>(link.id, null);
            }
          })(),
      ]);
      if (!mounted || requestId != _companyDetailRequestId) return;
      setState(() {
        for (final result in results) {
          final subject = result.value;
          if (subject == null) {
            _companyDetailFailures.add(result.key);
            failureCount++;
          } else {
            _companySubjectDetails[result.key] = subject;
            successCount++;
          }
        }
      });
    }
    if (!mounted || requestId != _companyDetailRequestId) return;
    setState(() {
      _loadingCompanyDetails = false;
      if (failureCount > 0) {
        _companyDetailMessage = successCount == 0
            ? '这批年份资料暂时无法取得，可以稍后重试。'
            : '本批有 $failureCount 部未能补全，可以稍后重试。';
      }
    });
  }

  List<Widget> _buildCompanyContent(PersonDetail detail) {
    final allCredits = buildCompanyWorkCredits(
      _subjects,
      _companySubjectDetails,
    );
    final roleCounts = countCompanyRoles(_subjects);
    final filteredLinks = _selectedCompanyRole == null
        ? _subjects
        : _subjects
              .where(
                (link) =>
                    normalizedCompanyRole(link.staff) == _selectedCompanyRole,
              )
              .toList();
    final filteredCredits = buildCompanyWorkCredits(
      filteredLinks,
      _companySubjectDetails,
    );
    final grouped = groupCompanyCreditsByYear(filteredCredits);
    final datedCount = allCredits.where((credit) => credit.year != null).length;
    final animationProductionCount = _subjects
        .where((item) => item.staff.trim() == '动画制作')
        .map((item) => item.id)
        .toSet()
        .length;
    final allYears = allCredits
        .map((credit) => credit.year)
        .whereType<int>()
        .toList();
    final oldestYear = allYears.isEmpty
        ? null
        : allYears.reduce((a, b) => a < b ? a : b);
    final newestYear = allYears.isEmpty
        ? null
        : allYears.reduce((a, b) => a > b ? a : b);
    final yearSpan = oldestYear == null
        ? '整理中'
        : oldestYear == newestYear
        ? '$oldestYear'
        : '$oldestYear–$newestYear';
    final undated = filteredCredits
        .where((credit) => credit.subject != null && credit.year == null)
        .toList();
    final awaiting = filteredCredits
        .where((credit) => credit.subject == null)
        .toList();
    final uniqueSubjects = uniqueCompanyWorkLinks(_subjects);
    final hasUnattempted = uniqueSubjects.any(
      (item) =>
          !_companySubjectDetails.containsKey(item.id) &&
          !_companyDetailFailures.contains(item.id),
    );
    final canRetryFailures =
        !hasUnattempted && _companyDetailFailures.isNotEmpty;

    return [
      if (detail.summary.isNotEmpty) ...[
        const SizedBox(height: 18),
        Text('公司简介', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        _CompanySummary(text: detail.summary.replaceAll('\r\n', '\n')),
      ],
      const SizedBox(height: 22),
      Text('公司档案', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 10),
      _CompanyMetrics(
        items: [
          ('关联作品', '${allCredits.length}', Icons.movie_filter_rounded),
          ('已取得日期', '$datedCount', Icons.event_available_rounded),
          ('已整理年代', yearSpan, Icons.timeline_rounded),
          ('标注动画制作', '$animationProductionCount', Icons.animation_rounded),
        ],
      ),
      const SizedBox(height: 12),
      _CompanyDataProgress(
        resolved: _companySubjectDetails.length,
        total: uniqueSubjects.length,
        failed: _companyDetailFailures.length,
        loading: _loadingCompanyDetails,
        message: _companyDetailMessage,
        onContinue: _companySubjectDetails.length >= uniqueSubjects.length
            ? null
            : () => _loadMoreCompanyDetails(retryFailures: canRetryFailures),
        retrying: canRetryFailures,
      ),
      const SizedBox(height: 22),
      Row(
        children: [
          Expanded(
            child: Text('按职位查看', style: Theme.of(context).textTheme.titleLarge),
          ),
          Text(
            '${roleCounts.length} 类职位',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            FilterChip(
              label: Text('全部 ${allCredits.length}'),
              selected: _selectedCompanyRole == null,
              onSelected: (_) => setState(() => _selectedCompanyRole = null),
            ),
            const SizedBox(width: 8),
            for (final entry in roleCounts.entries) ...[
              FilterChip(
                label: Text('${entry.key} ${entry.value}'),
                selected: _selectedCompanyRole == entry.key,
                onSelected: (_) => setState(() {
                  _selectedCompanyRole = entry.key;
                }),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
      const SizedBox(height: 22),
      Text('历年作品', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 4),
      Text(
        _selectedCompanyRole == null
            ? '按发行日期倒序排列，卡片左下角为该公司的职位。'
            : '当前只显示“$_selectedCompanyRole”的关联条目。',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      if (filteredCredits.isEmpty) ...[
        const SizedBox(height: 12),
        const EmptyState(
          icon: Icons.account_tree_outlined,
          title: '暂无对应作品',
          message: 'Bangumi 暂未收录这个职位下的关联条目。',
        ),
      ] else ...[
        for (final entry in grouped.entries)
          _CompanyWorkSection(
            title: '${entry.key}',
            count: entry.value.length,
            credits: entry.value,
            onOpen: _openCompanyWork,
          ),
        if (undated.isNotEmpty)
          _CompanyWorkSection(
            title: '日期未收录',
            count: undated.length,
            credits: undated,
            onOpen: _openCompanyWork,
          ),
        if (awaiting.isNotEmpty)
          _CompanyWorkSection(
            title: '年份待补全',
            count: awaiting.length,
            credits: awaiting,
            onOpen: _openCompanyWork,
          ),
      ],
      const SizedBox(height: 18),
      const _CompanySourceNote(),
    ];
  }

  List<Widget> _buildPersonContent(PersonDetail? detail) => [
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
          onTap: () => _openCompanyWork(CompanyWorkCredit(link: subject)),
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
              if (character.subjectName.isNotEmpty) character.subjectName,
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
  ];

  void _openCompanyWork(CompanyWorkCredit credit) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SubjectDetailScreen(
          subject: credit.subject ?? credit.link.toSubject(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final title =
        detail?.displayName ??
        (widget.seedName.isEmpty ? '人物' : widget.seedName);
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
                padding: EdgeInsets.fromLTRB(
                  MediaQuery.sizeOf(context).width < 420 ? 12 : 16,
                  12,
                  MediaQuery.sizeOf(context).width < 420 ? 12 : 16,
                  40,
                ),
                children: [
                  _PersonHeader(
                    name: detail?.displayName ?? title,
                    subtitle:
                        detail != null &&
                            detail.name.isNotEmpty &&
                            detail.name != detail.displayName
                        ? detail.name
                        : '',
                    imageUrl: detail?.imageUrl.isNotEmpty == true
                        ? detail!.imageUrl
                        : widget.seedImageUrl,
                    meta: [
                      if (detail?.type == 2) '公司',
                      if (detail?.type == 3) '团体',
                      ...?detail?.career,
                      if (detail?.gender.isNotEmpty == true) detail!.gender,
                      if ((detail?.collectCount ?? 0) > 0)
                        '收藏 ${detail!.collectCount}',
                    ],
                    isCompany: detail?.type == 2,
                  ),
                  if (detail?.type == 2)
                    ..._buildCompanyContent(detail!)
                  else
                    ..._buildPersonContent(detail),
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
    this.isCompany = false,
  });

  final String name;
  final String subtitle;
  final String imageUrl;
  final List<String> meta;
  final bool isCompany;

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
              borderRadius: BorderRadius.circular(isCompany ? 20 : 48),
              child: SizedBox(
                width: 96,
                height: 96,
                child: imageUrl.isEmpty
                    ? ColoredBox(
                        color: scheme.surfaceContainerHighest,
                        child: Icon(
                          isCompany
                              ? Icons.business_rounded
                              : Icons.person_rounded,
                          size: 40,
                        ),
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

class _CompanyMetrics extends StatelessWidget {
  const _CompanyMetrics({required this.items});

  final List<(String, String, IconData)> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 10.0;
        final columns = constraints.maxWidth >= 720 ? 4 : 2;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final item in items)
              SizedBox(
                width: width,
                child: Card(
                  margin: EdgeInsets.zero,
                  color: scheme.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(item.$3, size: 20, color: scheme.primary),
                        const SizedBox(height: 12),
                        Text(
                          item.$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.$1,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CompanySummary extends StatefulWidget {
  const _CompanySummary({required this.text});

  final String text;

  @override
  State<_CompanySummary> createState() => _CompanySummaryState();
}

class _CompanySummaryState extends State<_CompanySummary> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final canExpand = widget.text.runes.length > 180;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Text(
            widget.text,
            maxLines: _expanded || !canExpand ? null : 5,
            overflow: _expanded || !canExpand
                ? TextOverflow.visible
                : TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
        if (canExpand) ...[
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: () => setState(() => _expanded = !_expanded),
            icon: Icon(
              _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
            ),
            label: Text(_expanded ? '收起简介' : '展开全文'),
          ),
        ],
      ],
    );
  }
}

class _CompanyDataProgress extends StatelessWidget {
  const _CompanyDataProgress({
    required this.resolved,
    required this.total,
    required this.failed,
    required this.loading,
    required this.message,
    required this.onContinue,
    required this.retrying,
  });

  final int resolved;
  final int total;
  final int failed;
  final bool loading;
  final String? message;
  final VoidCallback? onContinue;
  final bool retrying;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = total == 0 ? 0.0 : (resolved / total).clamp(0.0, 1.0);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.fact_check_outlined, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '年份资料 $resolved / $total',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (loading)
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 10),
            Text(
              '关联职位会立即显示；年份由作品条目的发行日期分批补全。每批最多 $_companyDetailBatchSize 部。',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(message!, style: TextStyle(color: scheme.error)),
            ],
            if (failed > 0 && message == null) ...[
              const SizedBox(height: 8),
              Text(
                '$failed 部请求失败，完成其余条目后可重试。',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
            if (onContinue != null) ...[
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: loading ? null : onContinue,
                icon: Icon(
                  retrying ? Icons.refresh_rounded : Icons.add_rounded,
                ),
                label: Text(retrying ? '重试失败条目' : '继续补全年份'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CompanyWorkSection extends StatelessWidget {
  const _CompanyWorkSection({
    required this.title,
    required this.count,
    required this.credits,
    required this.onOpen,
  });

  final String title;
  final int count;
  final List<CompanyWorkCredit> credits;
  final ValueChanged<CompanyWorkCredit> onOpen;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 8),
            Text(
              '$count 部',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: subjectPosterItemHeight(166, 1),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: credits.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final credit = credits[index];
              final subject = credit.subject ?? credit.link.toSubject();
              final evidence = [
                if (subject.date.isNotEmpty) subject.date,
                if (credit.eps.isNotEmpty) '集数 ${credit.eps}',
                if (subject.date.isEmpty && credit.eps.isEmpty)
                  subject.type.label,
              ].join(' · ');
              return SizedBox(
                width: 166,
                child: SubjectPosterCard(
                  subject: subject,
                  statusLabel: credit.role,
                  metaLabel: evidence,
                  onTap: () => onOpen(credit),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

class _CompanySourceNote extends StatelessWidget {
  const _CompanySourceNote();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, size: 20, color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '事实口径：公司类型、关联作品、职位与参与集数来自 Bangumi 人物关联；年份来自对应作品的发行日期。未收录的数据会明确标记，不做推测。',
                style: TextStyle(color: scheme.onSurfaceVariant),
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
