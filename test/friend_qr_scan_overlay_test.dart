import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/widgets/friend_qr_scan_overlay.dart';

void main() {
  testWidgets('scan overlay keeps an animated frame on screen', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: FriendQrScanOverlay())),
    );

    expect(find.byType(FriendQrScanOverlay), findsOneWidget);
    expect(find.byKey(const ValueKey('friend-qr-scan-frame')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('friend-qr-scan-line')), findsOneWidget);
  });
}
