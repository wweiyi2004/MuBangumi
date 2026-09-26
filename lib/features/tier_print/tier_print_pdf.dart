import 'dart:math' as math;
import 'dart:isolate';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'tier_print_models.dart';

Future<Uint8List> renderTierPrintOffThread(
  TierPrintOptions options,
  List<TierPrintEntry> entries,
  Map<int, Uint8List> covers,
  Uint8List fontBytes, {
  Uint8List? fallbackFontBytes,
}) => Isolate.run(
  () => buildTierPrintPdf(
    options: options,
    entries: entries,
    covers: covers,
    fontBytes: fontBytes,
    fallbackFontBytes: fallbackFontBytes,
  ),
);

/// Fixed physical geometry. Covers and board slots share TierPrintLayout.
Future<Uint8List> buildTierPrintPdf({
  required TierPrintOptions options,
  required List<TierPrintEntry> entries,
  required Map<int, Uint8List> covers,
  required Uint8List fontBytes,
  Uint8List? fallbackFontBytes,
}) async {
  options.validate(entries.length);
  final layout = options.layout;
  final fontData = ByteData.sublistView(fontBytes);
  final font = pw.Font.ttf(fontData);
  final fallback = fallbackFontBytes == null
      ? null
      : pw.Font.ttf(ByteData.sublistView(fallbackFontBytes));
  final supported = {
    ...TtfParser(fontData).charToGlyphIndexMap.keys,
    if (fallbackFontBytes != null)
      ...TtfParser(
        ByteData.sublistView(fallbackFontBytes),
      ).charToGlyphIndexMap.keys,
  };
  String clean(String value) => String.fromCharCodes(
    value.runes.map(
      (rune) => rune == 10 || supported.contains(rune) ? rune : 0x25a1,
    ),
  );
  pw.Widget text(
    String value,
    double size, {
    int? lines,
    PdfColor color = PdfColors.black,
    pw.TextAlign? align,
  }) => pw.Text(
    clean(value),
    style: pw.TextStyle(
      font: font,
      fontSize: size,
      color: color,
      fontFallback: [?fallback],
    ),
    maxLines: lines,
    overflow: pw.TextOverflow.clip,
    textAlign: align,
    lineSplitter: lines == null
        ? null
        : (line) => RegExp(
            r'[\u2E80-\u9FFF\uF900-\uFAFF]|[^\u2E80-\u9FFF\uF900-\uFAFF\s]+',
          ).allMatches(line).map((match) => match.group(0)!).toList(),
  );
  double mm(double value) => value * PdfPageFormat.mm;
  pw.Widget at(double x, double y, double w, double h, pw.Widget child) =>
      pw.Positioned(
        left: mm(x),
        top: mm(y),
        child: pw.SizedBox(width: mm(w), height: mm(h), child: child),
      );
  final doc = pw.Document(
    title: '${options.period.label} 从夯到拉打印套件',
    author: 'MuBangumi',
    theme: pw.ThemeData.withFont(
      base: font,
      bold: font,
      italic: font,
      boldItalic: font,
      fontFallback: [?fallback],
    ),
  );
  final missing = entries
      .where((entry) => !covers.containsKey(entry.id))
      .length;

  void page(
    String title,
    String subtitle,
    List<pw.Widget> children, {
    String? instruction,
    TierPrintPaper? paper,
  }) {
    final sheet = paper ?? layout.paper;
    final w = sheet.widthMm, h = sheet.heightMm;
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(mm(w), mm(h)),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Stack(
          children: [
            at(10, 7, w - 20, 8, text(title, 16)),
            at(10, 16, w - 20, 6, text(subtitle, 8)),
            ...children,
            at(
              10,
              h - 22,
              w - 20,
              6,
              text(instruction ?? '按实际大小 / 100% 打印，关闭适应纸张；先量取下方 50 mm 标尺。', 7),
            ),
            at(
              10,
              h - 14,
              50,
              5,
              pw.CustomPaint(
                size: PdfPoint(mm(50), mm(5)),
                painter: (canvas, size) {
                  canvas
                    ..setStrokeColor(PdfColors.black)
                    ..setLineWidth(.5);
                  canvas.drawLine(0, mm(2), mm(50), mm(2));
                  for (var i = 0; i <= 5; i++) {
                    canvas.drawLine(mm(i * 10.0), 0, mm(i * 10.0), mm(4));
                  }
                  canvas.strokePath();
                },
              ),
            ),
            at(63, h - 14, 35, 5, text('50 mm 校准尺', 7)),
            at(
              w - 79,
              h - 14,
              69,
              5,
              text(
                'MuBangumi · ${sheet.label} · 100%',
                7,
                align: pw.TextAlign.right,
              ),
            ),
          ],
        ),
      ),
    );
  }

  if (options.part != TierPrintPart.board) {
    final pages = layout.coverPages(entries.length);
    for (var pageIndex = 0; pageIndex < pages; pageIndex++) {
      final children = <pw.Widget>[];
      for (var position = 0; position < layout.coversPerPage; position++) {
        final index = pageIndex * layout.coversPerPage + position;
        if (index >= entries.length) break;
        final entry = entries[index];
        final x =
            10 +
            (position % layout.coverColumns) *
                (layout.card.widthMm + TierPrintLayout.gapMm);
        final y =
            24 +
            (position ~/ layout.coverColumns) *
                (layout.card.heightMm + TierPrintLayout.gapMm);
        final w = layout.card.widthMm, h = layout.card.heightMm;
        final bytes = covers[entry.id];
        children.add(
          at(
            x,
            y,
            w,
            h,
            pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400, width: .3),
              ),
            ),
          ),
        );
        // Position the image and caption independently. A Column whose exact
        // child heights equal the card height can drop the caption after the
        // border consumes part of its layout constraint on small cards.
        children.add(
          at(
            x + .7,
            y + .7,
            w - 1.4,
            h - 8.4,
            pw.Center(
              child: bytes == null
                  ? text('封面缺失\n保留编号', 8, align: pw.TextAlign.center)
                  : pw.Image(
                      pw.MemoryImage(bytes, dpi: 300),
                      fit: pw.BoxFit.contain,
                    ),
            ),
          ),
        );
        children.add(
          at(
            x + .7,
            y + h - 6.9,
            w - 1.4,
            6.7,
            text(
              '#${(index + 1).toString().padLeft(3, '0')}  ${entry.title}',
              w < 26 ? 5.8 : 6.2,
              lines: 2,
            ),
          ),
        );
        children.add(
          at(
            x - 1.5,
            y - 1.5,
            w + 3,
            h + 3,
            pw.CustomPaint(
              size: PdfPoint(mm(w + 3), mm(h + 3)),
              painter: (canvas, size) {
                canvas
                  ..setStrokeColor(PdfColors.grey600)
                  ..setLineWidth(.4);
                for (final cx in [mm(1.5), mm(w + 1.5)]) {
                  for (final cy in [mm(1.5), mm(h + 1.5)]) {
                    final dx = cx < size.x / 2 ? -1 : 1;
                    final dy = cy < size.y / 2 ? -1 : 1;
                    canvas.drawLine(
                      cx + dx * mm(.4),
                      cy,
                      cx + dx * mm(1.5),
                      cy,
                    );
                    canvas.drawLine(
                      cx,
                      cy + dy * mm(.4),
                      cx,
                      cy + dy * mm(1.5),
                    );
                  }
                }
                canvas.strokePath();
              },
            ),
          ),
        );
      }
      page(
        '${options.period.label} · 封面裁剪页',
        '所选 ${entries.length} 部 · 第 ${pageIndex + 1}/$pages 页 · 卡片 ${layout.card.widthMm.toInt()} × ${layout.card.heightMm.toInt()} mm · 缺图 $missing 张',
        children,
      );
    }
  }

  if (options.part != TierPrintPart.covers) {
    const colors = [
      PdfColor.fromInt(0xffef7770),
      PdfColor.fromInt(0xffffbc79),
      PdfColor.fromInt(0xffffdf88),
      PdfColor.fromInt(0xffa7d7aa),
      PdfColor.fromInt(0xff9dc7e8),
    ];
    final pages = layout.boardPages(options.slotsPerTier);
    for (var pageIndex = 0; pageIndex < pages; pageIndex++) {
      final children = <pw.Widget>[];
      final columns = layout.boardColumns(pageIndex, options.slotsPerTier);
      final count = layout.boardSlotCount(pageIndex, options.slotsPerTier);
      final start = layout.boardSlotStart(pageIndex);
      final boardWidth = layout.boardContentWidth;
      for (var tier = 0; tier < 5; tier++) {
        final y = 24 + tier * layout.bandHeight;
        children.add(
          at(
            10,
            y,
            boardWidth,
            layout.bandHeight,
            pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(width: .45, color: PdfColors.grey600),
              ),
            ),
          ),
        );
        if (pageIndex == 0) {
          children.add(
            at(
              10,
              y,
              layout.boardLabelMm - 2,
              layout.bandHeight,
              pw.Container(
                color: colors[tier],
                alignment: pw.Alignment.center,
                padding: pw.EdgeInsets.all(mm(1.2)),
                child: pw.FittedBox(
                  fit: pw.BoxFit.scaleDown,
                  child: text(
                    options.tierLabels[tier],
                    switch (layout.boardSheet) {
                      TierPrintPaper.a4 => 16,
                      TierPrintPaper.a3 => 18,
                      TierPrintPaper.a2 => 22,
                      TierPrintPaper.a1 => 28,
                    },
                  ),
                ),
              ),
            ),
          );
        }
        for (var slot = 0; slot < count; slot++) {
          final col = slot % columns;
          final row = slot ~/ columns;
          final slotY = y + 1 + row * (layout.slotHeight + 2);
          final x =
              10 +
              (pageIndex == 0 ? layout.boardLabelMm : 1) +
              col * (layout.slotWidth + 2);
          children.add(
            at(
              x,
              slotY,
              layout.slotWidth,
              layout.slotHeight,
              pw.CustomPaint(
                size: PdfPoint(mm(layout.slotWidth), mm(layout.slotHeight)),
                painter: (canvas, size) {
                  canvas
                    ..setStrokeColor(PdfColors.grey400)
                    ..setLineWidth(.3)
                    ..setLineDashPattern([2, 2]);
                  canvas.drawRect(0, 0, size.x, size.y);
                  canvas.strokePath();
                },
              ),
            ),
          );
          children.add(
            at(
              x + 1,
              slotY + 1,
              layout.slotWidth - 2,
              4,
              text(
                '${options.tierLabels[tier]}  ${start + slot + 1}',
                5.5,
                color: PdfColors.grey500,
              ),
            ),
          );
        }
      }
      page(
        '${options.period.label} · 从夯到拉',
        '${layout.boardSheet.label} 底板 ${pageIndex + 1}/$pages · 每档 ${options.slotsPerTier} 格 · 格子比封面各留 1 mm 余量',
        children,
        paper: layout.boardSheet,
        instruction: '100% 打印。沿底板外框剪去白边，按页码从左向右拼接；五个档位上下对齐。',
      );
    }
  }

  if (options.part != TierPrintPart.board) {
    final rows = (layout.contentHeight / 12).floor();
    final pages = (entries.length / rows).ceil();
    for (var pageIndex = 0; pageIndex < pages; pageIndex++) {
      final children = <pw.Widget>[];
      for (var row = 0; row < rows; row++) {
        final index = pageIndex * rows + row;
        if (index >= entries.length) break;
        final entry = entries[index];
        final y = 24 + row * 12.0;
        children.add(
          at(10, y, 14, 10, text((index + 1).toString().padLeft(3, '0'), 9)),
        );
        children.add(
          at(
            25,
            y,
            layout.contentWidth - 66,
            11,
            pw.UrlLink(
              destination: 'https://bgm.tv/subject/${entry.id}',
              child: text(entry.title, 8, lines: 3),
            ),
          ),
        );
        children.add(
          at(
            layout.paper.widthMm - 60,
            y,
            50,
            11,
            text(
              '${entry.dateLabel}  ${entry.platform}\nID ${entry.id}${covers.containsKey(entry.id) ? '' : ' · 缺图'}',
              6.5,
              lines: 3,
            ),
          ),
        );
      }
      page(
        '${options.period.label} · 编号目录',
        '第 ${pageIndex + 1}/$pages 页 · 编号与封面一致 · 数据来源 Bangumi 当前公开可见目录',
        children,
      );
    }
  }
  return doc.save();
}

int tierPrintIndexPages(TierPrintLayout layout, int count) =>
    (count / math.max(1, (layout.contentHeight / 12).floor())).ceil();
