import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/app.dart';

void main() {
  testWidgets('brand mark renders', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: BrandMark())),
    );

    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });
}
