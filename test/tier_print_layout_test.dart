import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mubangumi/features/tier_print/tier_print_models.dart';
import 'package:mubangumi/features/tier_print/tier_print_covers.dart';

void main() {
  test('dense A4 covers stay small when the board changes to A1', () {
    const small = TierPrintLayout(
      card: TierPrintCard.dense,
      boardPaper: TierPrintPaper.a3,
    );
    const large = TierPrintLayout(
      card: TierPrintCard.dense,
      boardPaper: TierPrintPaper.a1,
    );
    expect(small.coversPerPage, 56);
    expect(large.coversPerPage, 56);
    expect(large.paper, TierPrintPaper.a4);
    expect(large.slotWidth, 22);
    expect(large.slotHeight, 32);
    expect(large.boardPages(48), 1);
    expect(large.boardRowsPerTier, greaterThan(small.boardRowsPerTier));
  });
  test(
    'A4 standard cutting cards and assembly slots have physical clearance',
    () {
      const layout = TierPrintLayout();
      expect(layout.coversPerPage, 25);
      expect(layout.coverPages(26), 2);
      expect(layout.slotWidth - layout.card.widthMm, 2);
      expect(layout.slotHeight - layout.card.heightMm, 2);
      expect(layout.firstBoardColumns, 5);
      expect(layout.nextBoardColumns, 5);
      expect(layout.boardPages(6), 2);
      expect(layout.boardColumns(1, 6), 1);
    },
  );
  for (final paper in TierPrintPaper.values) {
    for (final card in TierPrintCard.values) {
      final layout = TierPrintLayout(
        paper: TierPrintPaper.a4,
        boardPaper: paper,
        card: card,
      );
      if (!layout.valid) continue;
      test(
        '${paper.name}/${card.name} stays inside printable margins for every sheet',
        () {
          expect(
            layout.coverColumns * card.widthMm +
                (layout.coverColumns - 1) * TierPrintLayout.gapMm,
            lessThanOrEqualTo(layout.contentWidth),
          );
          expect(
            layout.coverRows * card.heightMm +
                (layout.coverRows - 1) * TierPrintLayout.gapMm,
            lessThanOrEqualTo(layout.contentHeight),
          );
          expect(
            layout.bandHeight * 5,
            lessThanOrEqualTo(layout.boardContentHeight + 1e-8),
          );
          for (final slots in [1, 5, 6, 30, 500]) {
            var count = 0;
            for (var page = 0; page < layout.boardPages(slots); page++) {
              final columns = layout.boardColumns(page, slots);
              final pageSlots = layout.boardSlotCount(page, slots);
              expect(columns, greaterThan(0));
              final width =
                  (page == 0 ? layout.boardLabelMm : 2) +
                  columns * layout.slotWidth +
                  (columns - 1) * 2;
              expect(width, lessThanOrEqualTo(layout.boardContentWidth));
              final rows = (pageSlots / columns).ceil();
              expect(rows, lessThanOrEqualTo(layout.boardRowsPerTier));
              expect(
                rows * (layout.slotHeight + 2),
                lessThanOrEqualTo(layout.bandHeight),
              );
              expect(layout.boardSlotStart(page), count);
              count += pageSlots;
            }
            expect(count, slots);
          }
        },
      );
    }
  }
  test(
    'board capacity is independent from cover count while invalid sizes remain rejected',
    () {
      expect(const TierPrintLayout(card: TierPrintCard.large).valid, false);
      expect(
        () => const TierPrintOptions(
          period: TierPrintPeriod(year: 2025),
          layout: TierPrintLayout(),
          slotsPerTier: 0,
        ).validate(6),
        throwsFormatException,
      );
      for (final part in TierPrintPart.values) {
        expect(
          () => TierPrintOptions(
            period: const TierPrintPeriod(year: 2025),
            layout: const TierPrintLayout(),
            slotsPerTier: 2,
            part: part,
          ).validate(1000),
          returnsNormally,
        );
      }
    },
  );
  test(
    'cover normalization preserves the complete aspect ratio and bounds output pixels',
    () {
      final original = img.Image(width: 800, height: 1200);
      img.fill(original, color: img.ColorRgb8(230, 60, 80));
      final bytes = normalizeTierCover(img.encodePng(original));
      final decoded = img.decodeJpg(bytes)!;
      expect(decoded.height, 560);
      expect(decoded.width / decoded.height, closeTo(2 / 3, .003));
    },
  );
}
