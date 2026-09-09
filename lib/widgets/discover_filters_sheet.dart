import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/network/bangumi_meta_tags.dart';
import '../models/bangumi_models.dart';

class DiscoverFilters {
  const DiscoverFilters({
    required this.browseYear,
    required this.browseQuarter,
    this.browseSort = 'rank',
    this.searchMode = false,
    this.searchSort = 'match',
    this.minimumRating = 0,
    this.ratingExclusive = false,
    this.startYear = 0,
    this.endYear = 0,
    this.hideCollected = false,
    this.metaTags = const [],
    this.tag = '',
  });

  final int browseYear, browseQuarter, startYear, endYear;
  final String browseSort, searchSort, tag;
  final bool searchMode, ratingExclusive, hideCollected;
  final double minimumRating;
  final List<String> metaTags;
}

class DiscoverFiltersSheet extends StatefulWidget {
  const DiscoverFiltersSheet({
    super.key,
    required this.initial,
    required this.subjectType,
    required this.earliestYear,
    required this.hasKeyword,
  });

  final DiscoverFilters initial;
  final SubjectType subjectType;
  final int earliestYear;
  final bool hasKeyword;

  @override
  State<DiscoverFiltersSheet> createState() => _DiscoverFiltersSheetState();
}

class _DiscoverFiltersSheetState extends State<DiscoverFiltersSheet> {
  late final TextEditingController _browseYear,
      _startYear,
      _endYear,
      _rating,
      _tag;
  late bool _searchMode, _exclusive, _hideCollected;
  late String _browseSort, _searchSort;
  late int _quarter;
  late List<String> _metaTags;
  final _currentYear = DateTime.now().year;

  bool get _supportsSeason =>
      widget.subjectType == SubjectType.anime ||
      widget.subjectType == SubjectType.real;
  String get _yearLabel => switch (widget.subjectType) {
    SubjectType.book => '出版年份',
    SubjectType.music || SubjectType.game => '发售年份',
    _ => '播出年份',
  };

  List<String> get _suggestedTags => switch (widget.subjectType) {
    SubjectType.anime => const ['科幻', '日常', '治愈', '战斗', '恋爱'],
    SubjectType.book => const ['轻小说', '科幻'],
    SubjectType.music => const ['OP', 'ED', 'OST', '角色歌'],
    SubjectType.game => const ['Galgame', 'RPG', 'ACT'],
    SubjectType.real => const ['推理', '爱情'],
  };

  @override
  void initState() {
    super.initState();
    final value = widget.initial;
    _browseYear = TextEditingController(text: '${value.browseYear}');
    _startYear = TextEditingController(
      text: value.startYear == 0 ? '' : '${value.startYear}',
    );
    _endYear = TextEditingController(
      text: value.endYear == 0 ? '' : '${value.endYear}',
    );
    _rating = TextEditingController(
      text: value.minimumRating == 0 && !value.ratingExclusive
          ? ''
          : value.minimumRating.toStringAsFixed(1),
    );
    _tag = TextEditingController(text: value.tag);
    _searchMode = value.searchMode || widget.hasKeyword;
    _exclusive = value.ratingExclusive;
    _hideCollected = value.hideCollected;
    _browseSort = value.browseSort;
    _searchSort = value.searchSort;
    _quarter = value.browseQuarter;
    _metaTags = [...value.metaTags];
  }

  @override
  void dispose() {
    for (final controller in [
      _browseYear,
      _startYear,
      _endYear,
      _rating,
      _tag,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _yearError(String text, {bool optional = true}) {
    if (text.trim().isEmpty) return optional ? null : '请输入年份';
    final year = int.tryParse(text);
    if (year == null || year < widget.earliestYear || year > _currentYear + 1) {
      return '请输入 ${widget.earliestYear}—${_currentYear + 1} 年';
    }
    return null;
  }

  String? get _endError {
    final error = _yearError(_endYear.text);
    if (error != null) return error;
    final start = int.tryParse(_startYear.text),
        end = int.tryParse(_endYear.text);
    if (start != null && end != null && start > end) return '截止年份不能早于起始年份';
    return null;
  }

  String? get _ratingError {
    final text = _rating.text.trim();
    if (text.isEmpty) return null;
    final value = double.tryParse(text);
    if (!RegExp(r'^\d{1,2}(?:\.\d)?$').hasMatch(text) ||
        value == null ||
        value > 10) {
      return '请输入 0–10，最多一位小数';
    }
    return null;
  }

  bool get _valid => _searchMode
      ? _yearError(_startYear.text) == null &&
            _endError == null &&
            _ratingError == null
      : _yearError(_browseYear.text, optional: false) == null;

  void _reset() => setState(() {
    _browseYear.text = '$_currentYear';
    _quarter = (DateTime.now().month - 1) ~/ 3;
    _browseSort = 'rank';
    _searchSort = 'match';
    _startYear.clear();
    _endYear.clear();
    _rating.clear();
    _tag.clear();
    _exclusive = false;
    _hideCollected = false;
    _metaTags = [];
  });

  void _apply() {
    if (!_valid) return;
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(
      DiscoverFilters(
        browseYear: int.tryParse(_browseYear.text) ?? _currentYear,
        browseQuarter: _quarter,
        browseSort: _browseSort,
        searchMode: _searchMode,
        searchSort: _searchMode ? _searchSort : 'match',
        minimumRating: _searchMode ? double.tryParse(_rating.text) ?? 0 : 0,
        ratingExclusive: _searchMode && _rating.text.isNotEmpty && _exclusive,
        startYear: _searchMode ? int.tryParse(_startYear.text) ?? 0 : 0,
        endYear: _searchMode ? int.tryParse(_endYear.text) ?? 0 : 0,
        hideCollected: _searchMode && _hideCollected,
        metaTags: _searchMode ? [..._metaTags] : const [],
        tag: _searchMode ? _tag.text.trim() : '',
      ),
    );
  }

  Widget _yearInput(
    TextEditingController controller,
    String key,
    String label, {
    String? error,
    bool optional = true,
  }) => TextField(
    key: ValueKey(key),
    controller: controller,
    keyboardType: TextInputType.number,
    textInputAction: TextInputAction.next,
    inputFormatters: [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(4),
    ],
    onChanged: (_) => setState(() {}),
    decoration: InputDecoration(
      labelText: label,
      hintText: optional ? '留空不限' : '$_currentYear',
      suffixText: '年',
      errorText: error,
    ),
  );

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(
      20,
      4,
      20,
      24 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${widget.subjectType.label}筛选',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        if (!widget.hasKeyword) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: Text(_supportsSeason ? '季度浏览' : '年度浏览'),
                selected: !_searchMode,
                onSelected: (_) => setState(() => _searchMode = false),
              ),
              ChoiceChip(
                label: const Text('条件搜索'),
                selected: _searchMode,
                onSelected: (_) => setState(() => _searchMode = true),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        Text(
          _searchMode ? '条件可以组合使用，也可以留空关键词直接找作品。' : '选择年份查看排行，或切换到条件搜索。',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 22),
        if (_searchMode) ...[
          Text('Bangumi 评分', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('discover-minimum-rating-input'),
            controller: _rating,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {
              if (_rating.text.isEmpty) _exclusive = false;
            }),
            decoration: InputDecoration(
              labelText: '最低评分',
              hintText: '例如 8.1，留空不限',
              suffixText: '分',
              errorText: _ratingError,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('不低于 ≥'),
                selected: !_exclusive,
                onSelected: (_) => setState(() => _exclusive = false),
              ),
              ChoiceChip(
                label: const Text('大于 >'),
                selected: _exclusive,
                onSelected: _rating.text.isEmpty
                    ? null
                    : (_) => setState(() => _exclusive = true),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                label: const Text('评分不限'),
                onPressed: () => setState(() {
                  _rating.clear();
                  _exclusive = false;
                }),
              ),
              for (final value in [6, 7, 8, 9])
                ActionChip(
                  label: Text('$value.0'),
                  onPressed: () => setState(() => _rating.text = '$value.0'),
                ),
            ],
          ),
          const SizedBox(height: 22),
          Text('$_yearLabel区间', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          _yearInput(
            _startYear,
            'discover-start-year-input',
            '起始年份（含）',
            error: _yearError(_startYear.text),
          ),
          const SizedBox(height: 14),
          _yearInput(
            _endYear,
            'discover-end-year-input',
            '截止年份（含）',
            error: _endError,
          ),
          const SizedBox(height: 8),
          Text(
            '可输入 ${widget.earliestYear}—${_currentYear + 1}；任意一端可留空。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          SwitchListTile.adaptive(
            key: const ValueKey('discover-hide-collected'),
            contentPadding: EdgeInsets.zero,
            title: const Text('隐藏已收藏'),
            subtitle: const Text('依据当前账号已加载的收藏，包含想看、在看、看过等状态；同步后自动更新。'),
            value: _hideCollected,
            onChanged: (value) => setState(() => _hideCollected = value),
          ),
          const SizedBox(height: 14),
          Text('搜索排序', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in const {
                'match': '匹配度',
                'heat': '热度',
                'rank': '排名',
                'score': '评分',
              }.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: _searchSort == entry.key,
                  onSelected: (_) => setState(() => _searchSort = entry.key),
                ),
            ],
          ),
          const SizedBox(height: 22),
          TextField(
            key: const ValueKey('discover-tag-input'),
            controller: _tag,
            decoration: const InputDecoration(
              labelText: '标签',
              hintText: '例如：科幻，日常',
              helperText: '多个标签用逗号分隔，同时满足所选标签。',
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in _suggestedTags)
                ActionChip(
                  label: Text(tag),
                  onPressed: () => setState(() {
                    final tags =
                        _tag.text
                            .trim()
                            .split(RegExp(r'[,，\s]+'))
                            .where((value) => value.isNotEmpty)
                            .toSet()
                          ..add(tag);
                    _tag.text = tags.join('，');
                  }),
                ),
            ],
          ),
        ] else ...[
          _yearInput(
            _browseYear,
            'discover-browse-year-input',
            '年份',
            optional: false,
            error: _yearError(_browseYear.text, optional: false),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (
                var year = _currentYear + 1;
                year >= _currentYear - 8;
                year--
              )
                ChoiceChip(
                  label: Text('$year'),
                  selected: _browseYear.text == '$year',
                  onSelected: (_) => setState(() => _browseYear.text = '$year'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (_supportsSeason)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in const [
                  '冬季（1月）',
                  '春季（4月）',
                  '夏季（7月）',
                  '秋季（10月）',
                ].asMap().entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: _quarter == entry.key,
                    onSelected: (_) => setState(() => _quarter = entry.key),
                  ),
              ],
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in const {'rank': '排名', 'date': '最新'}.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: _browseSort == entry.key,
                    onSelected: (_) => setState(() => _browseSort = entry.key),
                  ),
              ],
            ),
        ],
        const SizedBox(height: 14),
        ExpansionTile(
          key: const ValueKey('discover-official-tags'),
          tilePadding: EdgeInsets.zero,
          title: const Text('官方标签'),
          subtitle: Text(
            _metaTags.isEmpty ? '形式、来源等条件' : _metaTags.join(' · '),
          ),
          children: [
            for (final group in BangumiMetaTags.groupsFor(widget.subjectType))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(group.label),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final tag in group.tags)
                          ChoiceChip(
                            label: Text(tag),
                            selected: _metaTags.contains(tag),
                            onSelected: (selected) => setState(() {
                              _metaTags.removeWhere(group.tags.contains);
                              if (selected) {
                                _metaTags.add(tag);
                                _searchMode = true;
                              }
                            }),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 16,
          runSpacing: 12,
          children: [
            TextButton(onPressed: _reset, child: const Text('重置')),
            FilledButton.icon(
              onPressed: _valid ? _apply : null,
              icon: const Icon(Icons.check_rounded),
              label: const Text('应用筛选'),
            ),
          ],
        ),
      ],
    ),
  );
}
