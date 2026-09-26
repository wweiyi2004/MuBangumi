import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mubangumi/features/tier_print/tier_print_models.dart';
import 'package:mubangumi/features/tier_print/tier_print_pdf.dart';

void main() {
  test('a blank board can be printed without selected covers', () async {
    final bytes = await buildTierPrintPdf(
      options: const TierPrintOptions(
        period: TierPrintPeriod(year: 2025),
        layout: TierPrintLayout(),
        slotsPerTier: 2,
        part: TierPrintPart.board,
      ),
      entries: [],
      covers: {},
      fontBytes: await File(
        'assets/fonts/TierPrintSans-Regular.ttf',
      ).readAsBytes(),
    );
    expect(
      RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(bytes)),
      hasLength(1),
    );
  });
  test(
    'mixed kit allows fewer board slots than covers and preserves both paper sizes',
    () async {
      final entries = [
        for (var i = 0; i < 57; i++)
          TierPrintEntry(
            id: i + 1,
            title: '打印条目 $i',
            date: '2025-01-01',
            coverUrl: '',
          ),
      ];
      final bytes = await buildTierPrintPdf(
        options: const TierPrintOptions(
          period: TierPrintPeriod(year: 2025, quarter: 1),
          layout: TierPrintLayout(
            paper: TierPrintPaper.a4,
            boardPaper: TierPrintPaper.a1,
            card: TierPrintCard.dense,
          ),
          slotsPerTier: 2,
        ),
        entries: entries,
        covers: {},
        fontBytes: await File(
          'assets/fonts/TierPrintSans-Regular.ttf',
        ).readAsBytes(),
      );
      final boxes = RegExp(r'/MediaBox\s*\[([^\]]+)\]')
          .allMatches(latin1.decode(bytes))
          .map(
            (match) => match
                .group(1)!
                .trim()
                .split(RegExp(r'\s+'))
                .map(double.parse)
                .toList(),
          )
          .toList();
      expect(boxes, hasLength(6));
      for (var i = 0; i < boxes.length; i++) {
        expect(
          boxes[i][2],
          closeTo((i == 2 ? 594 : 210) * PdfPageFormat.mm, .01),
        );
        expect(
          boxes[i][3],
          closeTo((i == 2 ? 841 : 297) * PdfPageFormat.mm, .01),
        );
      }
    },
  );
  test('print font covers Chinese, Japanese and Korean titles', () async {
    final bytes = await File(
      'assets/fonts/TierPrintSans-Regular.ttf',
    ).readAsBytes();
    final parser = TtfParser(ByteData.sublistView(bytes));
    final hangul = TtfParser(
      ByteData.sublistView(
        await File('assets/fonts/TierPrintHangul-Regular.ttf').readAsBytes(),
      ),
    );
    expect({
      ...parser.charToGlyphIndexMap.keys,
      ...hangul.charToGlyphIndexMap.keys,
    }, containsAll('夯顶级人上人カタカナ우렁강도'.runes.toSet()));
  });
  test(
    'Chinese print kit generates cover sheets, fitted board and stable index',
    () async {
      final image = img.Image(width: 200, height: 300);
      img.fill(image, color: img.ColorRgb8(215, 85, 116));
      final cover = img.encodeJpg(image);
      final entries = [
        for (var i = 1; i <= 26; i++)
          TierPrintEntry(
            id: i,
            title: i == 1 ? '测试长标题：春季动画与日本語カタカナ ABC' : '封面样张 $i',
            date: '2025-01-01',
            coverUrl: '',
            platform: 'TV',
          ),
      ];
      final options = TierPrintOptions(
        period: const TierPrintPeriod(year: 2025, quarter: 1),
        layout: const TierPrintLayout(),
        slotsPerTier: 6,
      );
      final bytes = await buildTierPrintPdf(
        options: options,
        entries: entries,
        covers: {for (var i = 1; i <= 25; i++) i: cover},
        fontBytes: await File(
          'assets/fonts/TierPrintSans-Regular.ttf',
        ).readAsBytes(),
        fallbackFontBytes: await File(
          'assets/fonts/TierPrintHangul-Regular.ttf',
        ).readAsBytes(),
      );
      expect(latin1.decode(bytes.take(8).toList()), startsWith('%PDF-'));
      expect(
        RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(bytes)),
        hasLength(6),
      );
      const directory = String.fromEnvironment('TIER_PRINT_QA_DIR');
      if (directory.isNotEmpty) {
        await Directory(directory).create(recursive: true);
        await File('$directory/tier-print-fixture.pdf').writeAsBytes(bytes);
      }
    },
  );
}
