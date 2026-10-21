import 'package:mubangumi/navigation/app_destination.dart';
import 'package:mubangumi/navigation/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/widgets/friend_qr_scan_overlay.dart';

void main() {
  testWidgets('scan window stays at the viewport center behind the app bar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(title: const Text('扫一扫')),
          body: const FriendQrScanOverlay(),
        ),
      ),
    );
    expect(
      tester.getCenter(find.byKey(const ValueKey('friend-qr-scan-window'))),
      const Offset(195, 422),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('scan overlay keeps an animated frame on screen', (tester) async {
    await tester.pumpWidget(
      const AppRouteScope(
        resolve: AppRouter.resolve,
        child: MaterialApp(home: Scaffold(body: FriendQrScanOverlay())),
      ),
    );

    expect(find.byType(FriendQrScanOverlay), findsOneWidget);
    expect(find.byKey(const ValueKey('friend-qr-scan-frame')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('friend-qr-scan-line')), findsOneWidget);
  });
}
