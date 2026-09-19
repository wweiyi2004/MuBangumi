import 'package:mubangumi/navigation/app_destination.dart';
import 'package:mubangumi/navigation/app_router.dart';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/widgets/app_slider.dart';

void main() {
  testWidgets('Windows exposes one fixed slider node while its thumb moves', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var value = 20.0;
    late StateSetter update;
    await tester.pumpWidget(
      AppRouteScope(
        resolve: AppRouter.resolve,
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.windows),
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 400,
                    child: AppSlider(
                      label: '背景模糊',
                      value: value,
                      min: 0,
                      max: 40,
                      formatValue: (value) => value.toStringAsFixed(0),
                      onChanged: (next) => setState(() => value = next),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    final finder = find.byType(AppSlider);
    final original = tester.getSemantics(finder);
    final id = original.id;
    final bounds = original.rect;
    for (final next in [0.0, 10.0, 40.0, 22.0]) {
      update(() => value = next);
      await tester.pumpAndSettle();
      final node = tester.getSemantics(finder);
      expect(node.id, id);
      expect(node.rect, bounds);
      expect(node.childrenCount, 0);
      expect(node.getSemanticsData().label, '背景模糊');
      expect(node.getSemanticsData().value, next.toStringAsFixed(0));
      expect(find.bySemanticsLabel('背景模糊'), findsOneWidget);
      // A disabled indicator must not become an anonymous full-window hit
      // target. ExcludeSemantics alone cannot contain a navigator-level portal.
      final root = tester
          .renderObject<RenderBox>(finder)
          .owner!
          .semanticsOwner!
          .rootSemanticsNode!;
      final viewport = tester.view.physicalSize / tester.view.devicePixelRatio;
      final escaped = <int>[];
      void visit(SemanticsNode node) {
        if (node.childrenCount == 0 &&
            node.rect.size == viewport &&
            node.getSemanticsData().label.isEmpty) {
          escaped.add(node.id);
        }
        node.visitChildren((child) {
          visit(child);
          return true;
        });
      }

      visit(root);
      expect(escaped, isEmpty);
    }
    handle.dispose();
  });

  testWidgets(
    'Windows accessibility and keyboard changes retain commit callbacks',
    (tester) async {
      final handle = tester.ensureSemantics();
      var value = 20.0;
      final events = <String>[];
      await tester.pumpWidget(
        AppRouteScope(
          resolve: AppRouter.resolve,
          child: MaterialApp(
            theme: ThemeData(platform: TargetPlatform.windows),
            home: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                body: AppSlider(
                  label: '背景模糊',
                  value: value,
                  min: 0,
                  max: 40,
                  formatValue: (value) => value.toStringAsFixed(0),
                  onChangeStart: (_) => events.add('start'),
                  onChanged: (next) {
                    events.add('change');
                    setState(() => value = next);
                  },
                  onChangeEnd: (_) => events.add('end'),
                ),
              ),
            ),
          ),
        ),
      );
      final finder = find.byType(AppSlider);
      final owner = tester
          .renderObject<RenderBox>(finder)
          .owner!
          .semanticsOwner!;
      var node = tester.getSemantics(finder);
      expect(node.getSemanticsData().increasedValue, '22');
      expect(node.getSemanticsData().decreasedValue, '18');
      owner.performAction(node.id, ui.SemanticsAction.increase);
      await tester.pumpAndSettle();
      expect(value, 22);
      expect(events, ['start', 'change', 'end']);
      node = tester.getSemantics(finder);
      owner.performAction(node.id, ui.SemanticsAction.decrease);
      await tester.pumpAndSettle();
      expect(value, 20);
      tester.widget<Slider>(find.byType(Slider)).focusNode!.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(value, greaterThan(20));
      expect(tester.takeException(), isNull);
      handle.dispose();
    },
  );

  testWidgets('disabled slider retains its label without adjustable actions', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      AppRouteScope(
        resolve: AppRouter.resolve,
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.windows),
          home: Scaffold(
            body: AppSlider(
              label: '背景模糊',
              value: 22,
              min: 0,
              max: 40,
              formatValue: (value) => value.toStringAsFixed(0),
              onChanged: null,
            ),
          ),
        ),
      ),
    );
    final data = tester.getSemantics(find.byType(AppSlider)).getSemanticsData();
    expect(data.label, '背景模糊');
    expect(data.hasAction(ui.SemanticsAction.increase), isFalse);
    expect(data.hasAction(ui.SemanticsAction.decrease), isFalse);
    handle.dispose();
  });
}
