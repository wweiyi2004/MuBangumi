import 'dart:io';
import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'tier_print_catalog.dart';
import 'tier_print_covers.dart';
import 'tier_print_models.dart';
import 'tier_print_pdf.dart';
import 'tier_print_cancel.dart';

class TierPrintPage extends StatefulWidget {
  const TierPrintPage({super.key, this.catalog});
  final TierPrintCatalog? catalog;
  @override
  State<TierPrintPage> createState() => _TierPrintPageState();
}

class _TierPrintPageState extends State<TierPrintPage> {
  late final _catalog = widget.catalog ?? TierPrintCatalog();
  final _year = TextEditingController(text: '${DateTime.now().year}');
  final _slots = TextEditingController();
  final _labels = [
    for (final label in ['夯', '顶级', '人上人', 'NPC', '拉'])
      TextEditingController(text: label),
  ];
  int? _quarter = (DateTime.now().month - 1) ~/ 3 + 1;
  TierPrintPaper _paper = TierPrintPaper.a4;
  TierPrintPaper _boardPaper = TierPrintPaper.a3;
  TierPrintCard _card = TierPrintCard.standard;
  TierPrintSort _sort = TierPrintSort.date;
  TierPrintPart _part = TierPrintPart.kit;
  bool _tvOnly = false, _busy = false;
  String? _status, _error;
  TierCatalogResult? _result;
  TierPrintPeriod? _loadedPeriod;
  final _selected = <int>{};
  final _covers = <int, Uint8List>{};
  CancelToken? _cancel;
  TierPrintCovers? _coverLoader;

  TierPrintLayout get _layout =>
      TierPrintLayout(paper: _paper, boardPaper: _boardPaper, card: _card);
  List<TierPrintEntry> get _visible => sortTierPrintEntries(
    (_result?.entries ?? const []).where(
      (entry) => !_tvOnly || entry.platform.toUpperCase() == 'TV',
    ),
    _sort,
  );
  List<TierPrintEntry> get _chosen =>
      _visible.where((entry) => _selected.contains(entry.id)).toList();
  int get _slotCount => int.tryParse(_slots.text) ?? _layout.firstBoardCapacity;
  bool get _periodMatches =>
      _loadedPeriod?.year == int.tryParse(_year.text) &&
      _loadedPeriod?.quarter == _quarter;
  void _notify(String message) {
    if (mounted) setState(() => _status = message);
  }

  @override
  void dispose() {
    _cancel?.cancel();
    if (widget.catalog == null) _catalog.close();
    _coverLoader?.close();
    _year.dispose();
    _slots.dispose();
    for (final label in _labels) {
      label.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy) return;
    final period = TierPrintPeriod(
      year: int.tryParse(_year.text) ?? 0,
      quarter: _quarter,
    );
    if (!period.valid) {
      setState(() => _error = '请输入 1900–2100 年之间的年份');
      return;
    }
    final cancel = _cancel = CancelToken();
    setState(() {
      _busy = true;
      _error = null;
      _status = '准备读取目录…';
      _result = null;
      _loadedPeriod = null;
      _selected.clear();
      _covers.clear();
    });
    try {
      final result = await _catalog.load(
        period,
        cancel: cancel,
        progress: _notify,
      );
      if (!mounted) return;
      if (cancel.isCancelled) {
        setState(() => _status = '已取消读取');
        return;
      }
      setState(() {
        _result = result;
        _loadedPeriod = period;
        _selected.addAll(result.entries.map((e) => e.id));
        _status =
            '目录读取完成，共 ${result.entries.length} 部（${result.entries.where((e) => e.date.isEmpty).length} 部未提供具体日期）；封面将在导出时下载';
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _status = null;
          _error = cancel.isCancelled ? '已取消读取' : _message(error);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _message(Object error) => error is FormatException
      ? error.message
      : error is DioException
      ? '网络读取失败，请检查连接后重试；不会导出未读完的目录'
      : '生成或保存失败，请重试';

  Future<void> _export() async {
    if (_busy ||
        _loadedPeriod == null ||
        !_periodMatches ||
        (_chosen.isEmpty && _part != TierPrintPart.board)) {
      return;
    }
    final entries = _chosen;
    final options = TierPrintOptions(
      period: _loadedPeriod!,
      layout: _layout,
      slotsPerTier: _slotCount,
      part: _part,
      tierLabels: _labels.map((c) => c.text.trim()).toList(),
    );
    try {
      options.validate(entries.length);
    } catch (error) {
      setState(() => _error = _message(error));
      return;
    }
    final cancel = _cancel = CancelToken();
    setState(() {
      _busy = true;
      _error = null;
      _status = '准备打印文件…';
    });
    try {
      var images = <int, Uint8List>{};
      if (options.part != TierPrintPart.board) {
        final root = await getApplicationSupportDirectory();
        cancel.throwIfCancellationRequested();
        if (!mounted) return;
        _coverLoader ??= TierPrintCovers(
          cache: Directory(path.join(root.path, 'tier_print_covers_v1')),
        );
        images = await _coverLoader!.load(
          entries,
          cancel: cancel,
          existing: _covers,
          progress: (done, failed) =>
              _notify('下载封面 $done/${entries.length} · 缺失 $failed 张（将保留占位卡）'),
        );
        _covers.addAll(images);
      }
      cancel.throwIfCancellationRequested();
      _notify('正在生成 PDF…');
      final font = (await rootBundle.load(
        'assets/fonts/TierPrintSans-Regular.ttf',
      )).buffer.asUint8List();
      final bytes = await renderTierPrintOffThread(
        options,
        entries,
        images,
        font,
        fallbackFontBytes: (await rootBundle.load(
          'assets/fonts/TierPrintHangul-Regular.ttf',
        )).buffer.asUint8List(),
      );
      cancel.throwIfCancellationRequested();
      if (!mounted) return;
      final paperTag = options.part == TierPrintPart.kit
          ? '${options.layout.paper.name}-covers-${options.layout.boardSheet.name}-board'
          : options.part == TierPrintPart.board
          ? options.layout.boardSheet.name
          : options.layout.paper.name;
      final filename =
          'MuBangumi-tier-${options.period.fileKey}-${options.part.name}-$paperTag.pdf';
      final destination = await FilePicker.platform.saveFile(
        dialogTitle: '保存从夯到拉打印稿',
        fileName: filename,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        bytes: bytes,
        lockParentWindow: true,
      );
      if (mounted) {
        setState(
          () => _status = destination == null
              ? '已取消保存，清单与已下载封面仍保留'
              : 'PDF 已保存${options.part == TierPrintPart.board ? '' : '；缺失封面 ${entries.length - images.length} 张，已标记占位卡'}。打印请选择实际大小 / 100%。',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _status = null;
          _error = cancel.isCancelled ? '已取消导出，未保存文件' : _message(error);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(Widget child, {double width = 200}) =>
      SizedBox(width: width, child: child);
  @override
  Widget build(BuildContext context) {
    final visible = _visible, chosen = _chosen;
    final numbers = {
      for (var i = 0; i < chosen.length; i++) chosen[i].id: i + 1,
    };
    final layout = _layout;
    final slots = _slotCount;
    return Scaffold(
      appBar: AppBar(title: const Text('从夯到拉 · 打印工坊')),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('实验性功能：选一个季度或全年，把封面剪下来，贴到自己的排行榜上。'),
                  const SizedBox(height: 8),
                  const Text(
                    '按 Bangumi 公开目录的年份、月份筛选；季度覆盖三个月。个别条目没有具体日期时会标记保留，续播作品不重复计入后续季度。',
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _field(
                        TextField(
                          controller: _year,
                          enabled: !_busy,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(4),
                          ],
                          decoration: const InputDecoration(
                            labelText: '年份',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        width: 116,
                      ),
                      _field(
                        DropdownButtonFormField<int>(
                          initialValue: _quarter ?? 0,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: '时间范围',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: 0, child: Text('全年')),
                            DropdownMenuItem(
                              value: 1,
                              child: Text('第一季度 · 1–3 月'),
                            ),
                            DropdownMenuItem(
                              value: 2,
                              child: Text('第二季度 · 4–6 月'),
                            ),
                            DropdownMenuItem(
                              value: 3,
                              child: Text('第三季度 · 7–9 月'),
                            ),
                            DropdownMenuItem(
                              value: 4,
                              child: Text('第四季度 · 10–12 月'),
                            ),
                          ],
                          onChanged: _busy
                              ? null
                              : (value) => setState(
                                  () => _quarter = value == 0 ? null : value,
                                ),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: _busy ? null : _load,
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('读取全部条目'),
                      ),
                    ],
                  ),
                  if (_status != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_status!),
                    ),
                  if (_busy) ...[
                    const SizedBox(height: 8),
                    const LinearProgressIndicator(),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () {
                          _cancel?.cancel();
                          _notify('正在停止，请稍候…');
                        },
                        child: const Text('取消'),
                      ),
                    ),
                  ],
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (_result != null) ...[
                    if (!_periodMatches)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text('时间范围已修改，请重新读取目录后导出。'),
                      ),
                    const Divider(height: 32),
                    Text(
                      '${_loadedPeriod!.label} · 已读取 ${_result!.entries.length} 部',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Wrap(
                      spacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilterChip(
                          label: const Text('仅 TV 动画'),
                          selected: _tvOnly,
                          onSelected: _busy
                              ? null
                              : (value) => setState(() => _tvOnly = value),
                        ),
                        DropdownButton<TierPrintSort>(
                          value: _sort,
                          items: [
                            for (final order in TierPrintSort.values)
                              DropdownMenuItem(
                                value: order,
                                child: Text(order.label),
                              ),
                          ],
                          onChanged: _busy
                              ? null
                              : (value) => setState(() => _sort = value!),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(
                                  () => _selected.addAll(
                                    visible.map((e) => e.id),
                                  ),
                                ),
                          child: const Text('全选'),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(
                                  () => _selected.removeAll(
                                    visible.map((e) => e.id),
                                  ),
                                ),
                          child: const Text('清空选择'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _field(
                          DropdownButtonFormField<TierPrintPaper>(
                            key: const ValueKey('tier-cover-paper'),
                            initialValue: _paper,
                            decoration: const InputDecoration(
                              labelText: '封面纸张',
                            ),
                            items: [
                              for (final paper in [
                                TierPrintPaper.a4,
                                TierPrintPaper.a3,
                              ])
                                DropdownMenuItem(
                                  value: paper,
                                  child: Text(paper.label),
                                ),
                            ],
                            onChanged: _busy
                                ? null
                                : (value) => setState(() {
                                    _paper = value!;
                                  }),
                          ),
                          width: 120,
                        ),
                        _field(
                          DropdownButtonFormField<TierPrintPaper>(
                            key: const ValueKey('tier-board-paper'),
                            initialValue: _boardPaper,
                            decoration: const InputDecoration(
                              labelText: '排行榜纸张',
                            ),
                            items: [
                              for (final paper in TierPrintPaper.values)
                                DropdownMenuItem(
                                  value: paper,
                                  enabled: TierPrintLayout(
                                    paper: _paper,
                                    boardPaper: paper,
                                    card: _card,
                                  ).valid,
                                  child: Text(paper.label),
                                ),
                            ],
                            onChanged: _busy
                                ? null
                                : (value) {
                                    if (value != null &&
                                        TierPrintLayout(
                                          paper: _paper,
                                          boardPaper: value,
                                          card: _card,
                                        ).valid) {
                                      setState(() => _boardPaper = value);
                                    }
                                  },
                          ),
                          width: 150,
                        ),
                        _field(
                          DropdownButtonFormField<TierPrintCard>(
                            key: ValueKey(
                              '${_paper.name}-${_boardPaper.name}-${_card.name}',
                            ),
                            initialValue: _card,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: '封面卡片实际尺寸',
                            ),
                            items: [
                              for (final card in TierPrintCard.values.where(
                                (card) => TierPrintLayout(
                                  paper: _paper,
                                  boardPaper: _boardPaper,
                                  card: card,
                                ).valid,
                              ))
                                DropdownMenuItem(
                                  value: card,
                                  child: Text(card.label),
                                ),
                            ],
                            onChanged: _busy
                                ? null
                                : (value) => setState(() => _card = value!),
                          ),
                          width: 245,
                        ),
                        _field(
                          TextField(
                            controller: _slots,
                            enabled: !_busy,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(4),
                            ],
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: '每档预留格数',
                              hintText: '自动：${layout.firstBoardCapacity}',
                            ),
                          ),
                          width: 150,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text('底板格数独立设置，不要求贴完全部封面。留空时默认一张底板，手动增加格数才会续页。'),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        for (var i = 0; i < _labels.length; i++)
                          _field(
                            TextField(
                              controller: _labels[i],
                              enabled: !_busy,
                              maxLength: 6,
                              decoration: InputDecoration(
                                labelText: '第 ${i + 1} 档',
                                counterText: '',
                              ),
                            ),
                            width: 104,
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '选中 ${chosen.length} 部 · 封面 ${layout.coverPages(chosen.length)} 页 · 底板 ${layout.boardPages(math.max(1, slots))} 页 · 目录 ${tierPrintIndexPages(layout, chosen.length)} 页',
                    ),
                    Text(
                      '裁剪间距 4 mm；卡片 ${_card.widthMm.toInt()} × ${_card.heightMm.toInt()} mm；底板格 ${layout.slotWidth.toInt()} × ${layout.slotHeight.toInt()} mm。',
                    ),
                    Text(
                      '封面每张 ${_paper.label} 可排 ${layout.coversPerPage} 张；排行榜使用 ${_boardPaper.label}，每档最多 ${layout.boardRowsPerTier} 排。',
                    ),
                    Text(
                      _paper == _boardPaper
                          ? '按 100% 实际大小打印，关闭“适应纸张”；先检查 50 mm 校准线。'
                          : '封面和底板纸张不同，建议分别导出、分别打印；两者都选 100% 实际大小，勿把大底板缩到 A4。',
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _field(
                          DropdownButtonFormField<TierPrintPart>(
                            initialValue: _part,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: '导出内容',
                            ),
                            items: [
                              for (final part in TierPrintPart.values)
                                DropdownMenuItem(
                                  value: part,
                                  child: Text(part.label),
                                ),
                            ],
                            onChanged: _busy
                                ? null
                                : (value) => setState(() => _part = value!),
                          ),
                          width: 258,
                        ),
                        FilledButton.icon(
                          onPressed:
                              _busy ||
                                  (chosen.isEmpty &&
                                      _part != TierPrintPart.board) ||
                                  !_periodMatches
                              ? null
                              : _export,
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('导出打印 PDF'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '封面顺序预览 · 导出时按当前排序重新编号',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (visible.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('该范围没有符合条件的动画'),
                      ),
                  ],
                ],
              ),
            ),
          ),
          if (_result != null)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 165,
                  mainAxisExtent: 218,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final entry = visible[index];
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: _busy
                          ? null
                          : () => setState(() {
                              if (!_selected.add(entry.id)) {
                                _selected.remove(entry.id);
                              }
                            }),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: entry.coverUrl.isEmpty
                                ? const Icon(Icons.image_not_supported_outlined)
                                : CachedNetworkImage(
                                    imageUrl: entry.coverUrl,
                                    fit: BoxFit.contain,
                                    memCacheWidth: 200,
                                    errorWidget: (_, _, _) => const Icon(
                                      Icons.image_not_supported_outlined,
                                    ),
                                  ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 7),
                            child: Text(
                              '${numbers[entry.id]?.toString().padLeft(3, '0') ?? '-'}  ${entry.title}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Row(
                            children: [
                              Checkbox(
                                value: _selected.contains(entry.id),
                                onChanged: _busy
                                    ? null
                                    : (value) => setState(() {
                                        if (value == true) {
                                          _selected.add(entry.id);
                                        } else {
                                          _selected.remove(entry.id);
                                        }
                                      }),
                              ),
                              Expanded(
                                child: Text(
                                  entry.dateLabel,
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
