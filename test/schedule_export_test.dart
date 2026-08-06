import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/models/schedule_models.dart';
import 'package:mubangumi/widgets/schedule_export_poster.dart';

SeasonSchedule _sampleSchedule() => SeasonSchedule(
  season: const SeasonKey(year: 2026, quarter: 2),
  items: [
    const ScheduleItem(
      subjectId: 1,
      name: 'A',
      nameCn: '甲番',
      imageUrl: '',
      weekday: DateTime.monday,
    ),
    const ScheduleItem(
      subjectId: 2,
      name: 'B',
      nameCn: '乙番',
      imageUrl: '',
      weekday: DateTime.friday,
    ),
    const ScheduleItem(
      subjectId: 3,
      name: 'C',
      nameCn: '待定',
      imageUrl: '',
    ),
  ],
);

void main() {
  testWidgets('schedule export poster builds week grid for season items', (
    tester,
  ) async {
    final schedule = _sampleSchedule();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ScheduleExportPoster(schedule: schedule, width: 540),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('2026 夏季新番'), findsOneWidget);
    expect(find.textContaining('共 3 部'), findsOneWidget);
    expect(find.text('甲番'), findsOneWidget);
    expect(find.text('乙番'), findsOneWidget);
    expect(find.textContaining('待安排'), findsOneWidget);
    expect(find.text('MuBangumi'), findsOneWidget);
  });

  testWidgets('captures mounted repaint boundary to png bytes', (tester) async {
    final key = GlobalKey();
    final schedule = _sampleSchedule();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RepaintBoundary(
              key: key,
              child: ScheduleExportPoster(schedule: schedule, width: 540),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // toImage uses real async GPU work; run outside fake-async.
    final bytes = await tester.runAsync(
      () => ScheduleImageExporter.captureBoundary(key, pixelRatio: 1.0),
    );
    expect(bytes, isNotNull);
    expect(bytes!.length, greaterThan(100));
    // PNG signature
    expect(bytes[0], 0x89);
    expect(bytes[1], 0x50);
    expect(bytes[2], 0x4E);
    expect(bytes[3], 0x47);
  });
}
