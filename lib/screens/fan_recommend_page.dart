import 'package:flutter/material.dart';
import '../widgets/readable_subject_title.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/layout/app_layout.dart';
import '../core/recommend/fan_recommend_engine.dart';
import '../models/bangumi_models.dart';
import '../state/session_controller.dart';
import '../widgets/subject_widgets.dart';
import 'subject_detail_screen.dart';

/// 番会荐 — personal Bangumi recommendations from taste + free-form wishes.
class FanRecommendPage extends ConsumerStatefulWidget {
  const FanRecommendPage({super.key});

  @override
  ConsumerState<FanRecommendPage> createState() => _FanRecommendPageState();
}

class _FanRecommendPageState extends ConsumerState<FanRecommendPage> {
  final _wishController = TextEditingController();
  final _selectedTags = <String>{};
  var _modeTaste = true;
  var _minimumRating = 7;
  var _startYear = 0;
  var _loading = false;
  String? _error;
  String _status = '';
  List<FanRecommendItem> _results = const [];
  FanTasteProfile? _taste;

  @override
  void initState() {
    super.initState();
    Future.microtask(_refreshTaste);
  }

  @override
  void dispose() {
    _wishController.dispose();
    super.dispose();
  }

  void _refreshTaste() {
    final collections = ref.read(sessionProvider).collections;
    setState(() {
      _taste = FanRecommendEngine.buildTaste(collections);
    });
  }

  Future<void> _runRecommend() async {
    final collections = ref.read(sessionProvider).collections;
    final taste = FanRecommendEngine.buildTaste(collections);
    final request = FanRecommendRequest(
      wishText: _wishController.text,
      selectedTags: _selectedTags.toList(),
      minimumRating: _minimumRating,
      startYear: _startYear,
      useTaste: _modeTaste || _selectedTags.isEmpty,
    );

    if (!_modeTaste &&
        request.keyword.isEmpty &&
        request.effectiveTags.isEmpty) {
      setState(() {
        _error = '先写一点想看的方向，或点选几个标签吧';
        _results = const [];
      });
      return;
    }
    if (_modeTaste && !taste.hasTaste && request.effectiveTags.isEmpty) {
      setState(() {
        _error = '收藏里还没有足够的高分动画，先去看几部并评分，或切换到「说出需求」';
        _results = const [];
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _status = '正在翻找 Bangumi…';
      _taste = taste;
    });

    try {
      final api = ref.read(bangumiApiProvider);
      final jobs = FanRecommendEngine.buildSearchJobs(request, taste);
      final merged = <int, Subject>{};

      for (var i = 0; i < jobs.length; i++) {
        final job = jobs[i];
        if (!mounted) return;
        setState(() {
          _status =
              '检索 ${i + 1}/${jobs.length}'
              '${job.tags.isNotEmpty ? ' · ${job.tags.join(' / ')}' : ''}'
              '${job.keyword.isNotEmpty ? ' · ${job.keyword}' : ''}';
        });
        try {
          final keyword = job.keyword.trim().isNotEmpty
              ? job.keyword.trim()
              : (job.tags.isNotEmpty ? job.tags.first : '动画');
          final page = await api.searchSubjects(
            keyword,
            limit: 20,
            offset: 0,
            sort: job.keyword.trim().isEmpty ? 'rank' : 'heat',
            minimumRating: request.minimumRating,
            startYear: request.startYear,
            tags: job.tags,
          );
          for (final s in page) {
            merged.putIfAbsent(s.id, () => s);
          }
        } catch (_) {
          // Keep going with other jobs.
        }
      }

      // If still thin, pull a ranked season/year sample.
      if (merged.length < 8) {
        final now = DateTime.now();
        try {
          final browse = await api.browseSubjects(
            type: SubjectType.anime,
            year: request.startYear > 0 ? request.startYear : now.year,
            sort: 'rank',
            limit: 24,
          );
          for (final s in browse) {
            merged.putIfAbsent(s.id, () => s);
          }
        } catch (_) {}
      }

      final ranked = FanRecommendEngine.rank(
        candidates: merged.values.toList(),
        taste: taste,
        request: request,
        limit: 24,
      );

      if (!mounted) return;
      setState(() {
        _results = ranked;
        _loading = false;
        _status = ranked.isEmpty ? '' : '为你挑了 ${ranked.length} 部';
        _error = ranked.isEmpty
            ? '没有筛到合适的番，试试放宽评分/年份，或换几个标签'
            : null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = '';
        _error = error.toString().replaceFirst(RegExp(r'^.*Exception:\s*'), '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = AppLayout.isPhone(context);
    final scheme = Theme.of(context).colorScheme;
    final taste = _taste;

    return Scaffold(
      appBar: AppBar(
        title: const Text('番会荐'),
        actions: [
          IconButton(
            tooltip: '重新分析喜好',
            onPressed: () {
              _refreshTaste();
              showAppMessage(context, '已根据最新收藏更新口味画像');
            },
            icon: const Icon(Icons.psychology_alt_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: AppLayout.pageInsets(context, top: 12, bottom: 40),
        children: [
          _HeroBanner(taste: taste),
          const SizedBox(height: 16),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: true,
                label: Text('猜你喜欢'),
                icon: Icon(Icons.auto_awesome_rounded, size: 18),
              ),
              ButtonSegment(
                value: false,
                label: Text('说出需求'),
                icon: Icon(Icons.edit_note_rounded, size: 18),
              ),
            ],
            selected: {_modeTaste},
            onSelectionChanged: (value) {
              setState(() => _modeTaste = value.first);
            },
          ),
          const SizedBox(height: 16),
          if (_modeTaste) ...[
            Text(
              '根据你收藏里的高分动画标签来推荐，并自动跳过已在库中的作品。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (taste == null)
              const LinearProgressIndicator(minHeight: 3)
            else if (!taste.hasTaste)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text('口味样本还不够'),
                  subtitle: const Text(
                    '给看过的动画打 7 分以上，或积累一些在看/看过，会更准。也可切换到「说出需求」。',
                  ),
                ),
              )
            else ...[
              Text(
                '你的口味标签',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in taste.topTags.take(10))
                    Chip(
                      label: Text(tag),
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.local_offer_outlined, size: 16),
                    ),
                ],
              ),
              if (taste.avgLikedScore > 0) ...[
                const SizedBox(height: 8),
                Text(
                  '基于 ${taste.likedCount} 部偏好样本'
                  '${taste.avgLikedScore > 0 ? ' · 均分 ${taste.avgLikedScore.toStringAsFixed(1)}' : ''}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ] else ...[
            TextField(
              controller: _wishController,
              minLines: 2,
              maxLines: 4,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                hintText: '例如：想看治愈向日常、少打架、画风干净，最好近两年的',
                prefixIcon: Icon(Icons.chat_bubble_outline_rounded),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '快捷标签',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in FanRecommendEngine.presetTags)
                  FilterChip(
                    label: Text(tag),
                    selected: _selectedTags.contains(tag),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedTags.add(tag);
                        } else {
                          _selectedTags.remove(tag);
                        }
                      });
                    },
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Text(
            '筛选',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text('最低评分', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final rating in [0, 6, 7, 8, 9])
                ChoiceChip(
                  label: Text(rating == 0 ? '不限' : '$rating 分以上'),
                  selected: _minimumRating == rating,
                  onSelected: (_) => setState(() => _minimumRating = rating),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text('开播年份', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final year in [0, DateTime.now().year - 2, DateTime.now().year - 5, 2015, 2010])
                ChoiceChip(
                  label: Text(year == 0 ? '不限' : '$year 起'),
                  selected: _startYear == year,
                  onSelected: (_) => setState(() => _startYear = year),
                ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _loading ? null : _runRecommend,
              icon: _loading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome_rounded),
              label: Text(_loading ? '推荐中…' : '开始推荐'),
            ),
          ),
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              _status,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 14),
            Card(
              color: scheme.errorContainer.withValues(alpha: 0.45),
              child: ListTile(
                leading: Icon(Icons.error_outline_rounded, color: scheme.error),
                title: Text(_error!),
              ),
            ),
          ],
          if (_results.isNotEmpty) ...[
            SizedBox(height: AppLayout.blockGap(context)),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '推荐结果',
                    style: AppLayout.sectionTitleStyle(context),
                  ),
                ),
                Text(
                  '${_results.length} 部',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < _results.length; i++) ...[
              _RecommendTile(
                index: i + 1,
                item: _results[i],
                compact: phone,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          SubjectDetailScreen(subject: _results[i].subject),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
            ],
          ],
        ],
      ),
    );
  }
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({required this.taste});

  final FanTasteProfile? taste;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE95383), Color(0xFF8B6CEF)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE95383).withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.theater_comedy_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  '番会荐',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            taste?.hasTaste == true
                ? '读过你的收藏口味，也可以随时换成自己的一句话需求。'
                : '告诉我想看什么，或先积累一点高分收藏，让推荐更懂你。',
            style: const TextStyle(color: Colors.white70, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _RecommendTile extends StatelessWidget {
  const _RecommendTile({
    required this.index,
    required this.item,
    required this.onTap,
    this.compact = false,
  });

  final int index;
  final FanRecommendItem item;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final subject = item.subject;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(compact ? 10 : 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 28,
                child: Text(
                  '$index',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.primary,
                  ),
                ),
              ),
              SubjectCover(
                subject: subject,
                width: compact ? 58 : 66,
                height: compact ? 82 : 92,
                borderRadius: 10,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ReadableSubjectTitle(
                      subject.displayName,
                      maxLines: 2,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (subject.score > 0)
                          '★ ${subject.score.toStringAsFixed(1)}',
                        if (subject.rank > 0) '#${subject.rank}',
                        if (subject.date.isNotEmpty) subject.date,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final reason in item.reasons.take(3))
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer.withValues(
                                alpha: 0.55,
                              ),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              reason,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
