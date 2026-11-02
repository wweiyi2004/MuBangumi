import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme/anime_icon.dart';
import '../core/theme/app_tokens.dart';
import '../models/bangumi_models.dart';
import 'readable_subject_title.dart';
import 'subject_widgets.dart';

Future<void> showWatchedIntakeSearchSheet({
  required BuildContext context,
  required Future<List<Subject>> Function(String keyword) search,
  required bool Function(int subjectId) isCollected,
  required bool Function(int subjectId) isSelected,
  required void Function(Subject subject, {int? through}) onAdd,
  required void Function(BuildContext context) onOverlay,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  constraints: const BoxConstraints(maxWidth: AppWidth.reading),
  builder: (sheetContext) {
    onOverlay(sheetContext);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: WatchedIntakeSearchSheet(
        search: search,
        isCollected: isCollected,
        isSelected: isSelected,
        onAdd: onAdd,
        onOverlay: onOverlay,
      ),
    );
  },
);

class WatchedIntakeSearchSheet extends StatefulWidget {
  const WatchedIntakeSearchSheet({
    super.key,
    required this.search,
    required this.isCollected,
    required this.isSelected,
    required this.onAdd,
    required this.onOverlay,
  });

  final Future<List<Subject>> Function(String keyword) search;
  final bool Function(int subjectId) isCollected;
  final bool Function(int subjectId) isSelected;
  final void Function(Subject subject, {int? through}) onAdd;
  final void Function(BuildContext context) onOverlay;

  @override
  State<WatchedIntakeSearchSheet> createState() =>
      _WatchedIntakeSearchSheetState();
}

class _WatchedIntakeSearchSheetState extends State<WatchedIntakeSearchSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;
  var _request = 0;
  var _loading = false;
  List<Subject> _results = const [];
  String? _error;

  @override
  void dispose() {
    _request++;
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _changeQuery(String value) {
    _debounce?.cancel();
    final keyword = value.trim();
    setState(() {
      _request++;
      _results = const [];
      _error = null;
      _loading = keyword.isNotEmpty;
    });
    if (keyword.isNotEmpty) {
      _debounce = Timer(const Duration(milliseconds: 350), _submit);
    }
  }

  Future<void> _submit() async {
    _debounce?.cancel();
    final keyword = _controller.text.trim();
    final request = ++_request;
    setState(() {
      _results = const [];
      _error = null;
      _loading = keyword.isNotEmpty;
    });
    if (keyword.isEmpty) return;
    try {
      final results = await widget.search(keyword);
      if (!mounted || request != _request) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = '搜索暂时失败，请检查网络后重试';
        _loading = false;
      });
    }
  }

  Future<void> _editProgress(Subject subject) async {
    final max = subject.episodeCount > 0 ? subject.episodeCount : 9999;
    var value = '1';
    String? error;
    final selected = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        widget.onOverlay(dialogContext);
        return StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text('记到看到的那一集'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(subject.displayName),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: value,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: '已看话数',
                    errorText: error,
                  ),
                  onChanged: (text) => value = text,
                  onFieldSubmitted: (_) => _applyProgress(
                    context,
                    update,
                    max,
                    value,
                    (message) => error = message,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => _applyProgress(
                  context,
                  update,
                  max,
                  value,
                  (message) => error = message,
                ),
                child: const Text('应用话数'),
              ),
            ],
          ),
        );
      },
    );
    if (mounted) widget.onOverlay(context);
    if (selected != null && mounted) {
      widget.onAdd(subject, through: selected);
      setState(() {});
    }
  }

  void _applyProgress(
    BuildContext context,
    void Function(void Function()) update,
    int max,
    String value,
    void Function(String) setError,
  ) {
    final episode = int.tryParse(value.trim());
    if (episode == null || episode < 1 || episode > max) {
      update(() => setError('请输入 1–$max 之间的整数'));
      return;
    }
    Navigator.pop(context, episode);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .85,
      minChildSize: .5,
      maxChildSize: .95,
      builder: (context, scrollController) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('按片名搜索', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  '可以连续加入多部，核对清单后再一起同步。',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              key: const ValueKey('watched-search-field'),
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _changeQuery,
              onSubmitted: (_) => unawaited(_submit()),
              decoration: InputDecoration(
                hintText: '输入动画名，例如：命运石之门',
                prefixIcon: const AnimeIcon(Icons.search_rounded),
                suffixIcon: IconButton(
                  tooltip: '清空搜索',
                  onPressed: _controller.text.isEmpty
                      ? null
                      : () {
                          _controller.clear();
                          _changeQuery('');
                        },
                  icon: const AnimeIcon(Icons.close_rounded),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(child: _resultsView(scrollController)),
        ],
      ),
    );
  }

  Widget _resultsView(ScrollController scrollController) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return SingleChildScrollView(
        controller: scrollController,
        child: EmptyState(
          icon: Icons.cloud_off_outlined,
          title: '没有搜到结果',
          message: _error!,
          action: FilledButton.tonal(
            onPressed: _submit,
            child: const Text('重试'),
          ),
        ),
      );
    }
    if (_controller.text.trim().isEmpty) {
      return SingleChildScrollView(
        controller: scrollController,
        child: const EmptyState(
          icon: Icons.search_rounded,
          title: '知道片名，就不用一张张猜',
          message: '搜索后可标记整部看过，也可以记录看到第几集。',
        ),
      );
    }
    if (_results.isEmpty) {
      return SingleChildScrollView(
        controller: scrollController,
        child: const EmptyState(
          icon: Icons.search_off_rounded,
          title: '没有匹配的动画',
          message: '试试更短的片名，或使用 Bangumi 上的原名。',
        ),
      );
    }
    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: _results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _result(_results[index]),
    );
  }

  Widget _result(Subject subject) {
    final scheme = Theme.of(context).colorScheme;
    final collected = widget.isCollected(subject.id);
    final selected = widget.isSelected(subject.id);
    final unavailable = collected || selected;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: AppRadius.medium,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SubjectCover(
                  subject: subject,
                  width: 44,
                  height: 62,
                  borderRadius: 8,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ReadableSubjectTitle(subject.displayName, maxLines: 2),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (subject.date.isNotEmpty) subject.date,
                          if (subject.episodeCount > 0)
                            '${subject.episodeCount} 话',
                        ].join(' · '),
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (unavailable)
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  collected ? '已在收藏中' : '已加入本次清单',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton(
                    key: ValueKey('watched-search-progress-${subject.id}'),
                    onPressed: () => unawaited(_editProgress(subject)),
                    child: const Text('看到第几集'),
                  ),
                  FilledButton.tonal(
                    key: ValueKey('watched-search-add-${subject.id}'),
                    onPressed: () {
                      widget.onAdd(subject);
                      setState(() {});
                    },
                    child: const Text('看过'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
