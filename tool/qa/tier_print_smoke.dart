// Read-only manual visual QA. No application login or user storage is opened.
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:mubangumi/features/tier_print/tier_print_catalog.dart';
import 'package:mubangumi/features/tier_print/tier_print_covers.dart';
import 'package:mubangumi/features/tier_print/tier_print_models.dart';
import 'package:mubangumi/features/tier_print/tier_print_pdf.dart';

Future<void> main(List<String> args) async {
  final output = Directory('.dart_tool/tier-print-qa');
  await output.create(recursive: true);
  final catalog = TierPrintCatalog();
  final loader = TierPrintCovers(cache: Directory('${output.path}/covers'));
  try {
    final period = TierPrintPeriod(
      year: 2025,
      quarter: args.contains('--annual') ? null : 1,
    );
    final TierCatalogResult result;
    if (args.contains('--cached')) {
      final saved =
          jsonDecode(
                await File(
                  '${output.path}/catalog-${period.fileKey}.json',
                ).readAsString(),
              )
              as Map;
      result = TierCatalogResult(
        sourceCount: saved['total'] as int,
        fetchedAt: DateTime.parse(saved['fetchedAt'] as String),
        entries: [
          for (final raw in saved['entries'] as List)
            TierPrintEntry(
              id: raw['id'] as int,
              title: raw['title'] as String,
              date: raw['date'] as String,
              coverUrl: raw['cover'] as String,
              platform: raw['platform'] as String? ?? '',
            ),
        ],
      );
    } else {
      result = await catalog.load(period, progress: stdout.writeln);
    }
    if (!args.contains('--cached')) {
      await File('${output.path}/catalog-${period.fileKey}.json').writeAsString(
        jsonEncode({
          'total': result.sourceCount,
          'fetchedAt': result.fetchedAt.toIso8601String(),
          'entries': result.entries
              .map(
                (e) => {
                  'id': e.id,
                  'title': e.title,
                  'date': e.date,
                  'cover': e.coverUrl,
                  'platform': e.platform,
                },
              )
              .toList(),
        }),
      );
    }
    if (args.contains('--catalog-only')) {
      stdout.writeln('Complete catalogue: ${result.entries.length}');
      return;
    }
    final entries = args.contains('--all')
        ? result.entries
        : result.entries.take(31).toList();
    final images = await loader.load(
      entries,
      cancel: CancelToken(),
      progress: (done, failed) {
        if (done % 10 == 0 || done == entries.length) {
          stdout.writeln('Covers $done/${entries.length}; missing $failed');
        }
      },
    );
    final font = await File(
      'assets/fonts/TierPrintSans-Regular.ttf',
    ).readAsBytes();
    final layout = args.contains('--mixed')
        ? const TierPrintLayout(
            paper: TierPrintPaper.a4,
            boardPaper: TierPrintPaper.a1,
            card: TierPrintCard.dense,
          )
        : args.contains('--board-a3')
        ? const TierPrintLayout(boardPaper: TierPrintPaper.a3)
        : args.contains('--a3')
        ? const TierPrintLayout(
            paper: TierPrintPaper.a3,
            card: TierPrintCard.large,
          )
        : const TierPrintLayout();
    final slotArgument = args
        .where((value) => value.startsWith('--slots='))
        .firstOrNull;
    final options = TierPrintOptions(
      period: period,
      layout: layout,
      slotsPerTier: slotArgument == null
          ? layout.firstBoardCapacity
          : int.parse(slotArgument.substring('--slots='.length)),
    );
    final pdf = await buildTierPrintPdf(
      options: options,
      entries: entries,
      covers: images,
      fontBytes: font,
      fallbackFontBytes: await File(
        'assets/fonts/TierPrintHangul-Regular.ttf',
      ).readAsBytes(),
    );
    final file = File(
      '${output.path}/tier-print-real-${entries.length}-${options.layout.paper.name}${args.contains('--mixed')
          ? '-board-a1'
          : args.contains('--board-a3')
          ? '-board-a3'
          : ''}${slotArgument == null ? '' : '-slots${options.slotsPerTier}'}.pdf',
    );
    await file.writeAsBytes(pdf);
    stdout.writeln(
      'Complete catalogue: ${result.entries.length}. Sample: ${entries.length}. Missing: ${entries.length - images.length}. PDF: ${file.path}',
    );
  } finally {
    catalog.close();
    loader.close();
  }
}
