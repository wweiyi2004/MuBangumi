import 'package:mubangumi/navigation/app_destination.dart';
import 'package:mubangumi/navigation/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/app.dart';

void main() {
  testWidgets('brand mark renders', (tester) async {
    await tester.pumpWidget(
      const AppRouteScope(
        resolve: AppRouter.resolve,
        child: MaterialApp(home: Scaffold(body: BrandMark())),
      ),
    );

    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });
}
