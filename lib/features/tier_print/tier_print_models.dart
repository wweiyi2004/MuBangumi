import 'dart:math' as math;

class TierPrintPeriod {
  const TierPrintPeriod({required this.year, this.quarter});
  final int year;

  /// 1..4, or null for the whole year.
  final int? quarter;
  bool get valid =>
      year >= 1900 &&
      year <= 2100 &&
      (quarter == null || quarter! >= 1 && quarter! <= 4);
  List<int> get months => quarter == null
      ? List.generate(12, (index) => index + 1)
      : List.generate(3, (index) => (quarter! - 1) * 3 + index + 1);
  String get label => quarter == null ? '$year 全年' : '$year 年第 $quarter 季度';
  String get fileKey => '$year-${quarter == null ? 'year' : 'Q$quarter'}';
}

class TierPrintEntry {
  const TierPrintEntry({
    required this.id,
    required this.title,
    required this.date,
    required this.coverUrl,
    this.platform = '',
    this.score = 0,
    this.catalogYear,
    this.catalogMonth,
  });
  final int id;
  final String title, date, coverUrl, platform;
  final double score;
  final int? catalogYear, catalogMonth;
  String get dateLabel => date.isEmpty ? '日期未提供' : date;
  String get chronologicalKey => date.isEmpty
      ? '${catalogYear ?? 9999}-${(catalogMonth ?? 12).toString().padLeft(2, '0')}-99'
      : date;
}

enum TierPrintSort {
  date('首播日期'),
  title('标题'),
  score('Bangumi 评分');

  const TierPrintSort(this.label);
  final String label;
}

List<TierPrintEntry> sortTierPrintEntries(
  Iterable<TierPrintEntry> entries,
  TierPrintSort order,
) {
  final result = entries.toList();
  result.sort((a, b) {
    final primary = switch (order) {
      TierPrintSort.date => a.chronologicalKey.compareTo(b.chronologicalKey),
      TierPrintSort.title => a.title.compareTo(b.title),
      TierPrintSort.score => b.score.compareTo(a.score),
    };
    return primary != 0 ? primary : a.id.compareTo(b.id);
  });
  return result;
}

enum TierPrintPaper {
  a4('A4', 210, 297),
  a3('A3', 297, 420),
  a2('A2', 420, 594),
  a1('A1', 594, 841);

  const TierPrintPaper(this.label, this.widthMm, this.heightMm);
  final String label;
  final double widthMm, heightMm;
}

enum TierPrintCard {
  dense('密集 20 × 30 mm', 20, 30),
  compact('小号 26 × 40 mm', 26, 40),
  standard('标准 30 × 45 mm', 30, 45),
  large('大号 36 × 54 mm', 36, 54);

  const TierPrintCard(this.label, this.widthMm, this.heightMm);
  final String label;
  final double widthMm, heightMm;
}

enum TierPrintPart {
  kit('整套：封面＋底板＋目录'),
  covers('封面裁剪页＋目录'),
  board('排行榜底板');

  const TierPrintPart(this.label);
  final String label;
}

class TierPrintLayout {
  const TierPrintLayout({
    this.paper = TierPrintPaper.a4,
    this.boardPaper,
    this.card = TierPrintCard.standard,
  });
  final TierPrintPaper paper;

  /// When omitted, legacy callers keep the same paper for both outputs.
  final TierPrintPaper? boardPaper;
  TierPrintPaper get boardSheet => boardPaper ?? paper;
  final TierPrintCard card;
  static const marginMm = 10.0, headerMm = 14.0, footerMm = 13.0, gapMm = 4.0;
  static const labelMm = 22.0;
  double get contentWidth => paper.widthMm - marginMm * 2;
  double get contentHeight =>
      paper.heightMm - marginMm * 2 - headerMm - footerMm;
  double get slotWidth => card.widthMm + 2;
  double get slotHeight => card.heightMm + 2;
  double get boardContentWidth => boardSheet.widthMm - marginMm * 2;
  double get boardContentHeight =>
      boardSheet.heightMm - marginMm * 2 - headerMm - footerMm;
  double get boardLabelMm => math.max(labelMm, boardSheet.widthMm * .075);
  double get bandHeight => boardContentHeight / 5;
  int get boardRowsPerTier => (bandHeight / (slotHeight + 2)).floor();
  bool get valid =>
      boardRowsPerTier > 0 &&
      coverColumns > 0 &&
      coverRows > 0 &&
      firstBoardColumns > 0;
  int get coverColumns =>
      ((contentWidth + gapMm) / (card.widthMm + gapMm)).floor();
  int get coverRows =>
      ((contentHeight + gapMm) / (card.heightMm + gapMm)).floor();
  int get coversPerPage => coverColumns * coverRows;
  int get firstBoardColumns =>
      ((boardContentWidth - boardLabelMm + 2) / (slotWidth + 2)).floor();
  int get nextBoardColumns => (boardContentWidth / (slotWidth + 2)).floor();
  int coverPages(int count) => count == 0 ? 0 : (count / coversPerPage).ceil();
  int get firstBoardCapacity => firstBoardColumns * boardRowsPerTier;
  int get nextBoardCapacity => nextBoardColumns * boardRowsPerTier;
  int boardPages(int slotsPerTier) => slotsPerTier <= firstBoardCapacity
      ? 1
      : 1 + ((slotsPerTier - firstBoardCapacity) / nextBoardCapacity).ceil();
  int boardColumns(int page, int slotsPerTier) => math.min(
    page == 0 ? firstBoardColumns : nextBoardColumns,
    boardSlotCount(page, slotsPerTier),
  );
  int boardSlotCount(int page, int slotsPerTier) => math.min(
    page == 0 ? firstBoardCapacity : nextBoardCapacity,
    slotsPerTier - boardSlotStart(page),
  );
  int boardSlotStart(int page) =>
      page == 0 ? 0 : firstBoardCapacity + (page - 1) * nextBoardCapacity;
}

class TierPrintOptions {
  const TierPrintOptions({
    required this.period,
    required this.layout,
    required this.slotsPerTier,
    this.part = TierPrintPart.kit,
    this.tierLabels = const ['夯', '顶级', '人上人', 'NPC', '拉'],
  });
  final TierPrintPeriod period;
  final TierPrintLayout layout;
  final int slotsPerTier;
  final TierPrintPart part;
  final List<String> tierLabels;
  void validate(int count) {
    if (!period.valid ||
        !layout.valid ||
        slotsPerTier < 1 ||
        slotsPerTier > 2000 ||
        tierLabels.length != 5 ||
        tierLabels.any(
          (label) => label.trim().isEmpty || label.runes.length > 6,
        ) ||
        count < 0 ||
        (count == 0 && part != TierPrintPart.board) ||
        count > 10000) {
      throw const FormatException('请检查纸张、卡片尺寸和底板设置；每档预留格数需为 1–2000');
    }
  }
}

class TierCatalogResult {
  const TierCatalogResult({
    required this.entries,
    required this.sourceCount,
    required this.fetchedAt,
  });
  final List<TierPrintEntry> entries;
  final int sourceCount;
  final DateTime fetchedAt;
}
