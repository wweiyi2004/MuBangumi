import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/social/friend_qr.dart';
import 'package:mubangumi/core/social/friend_qr_export.dart';
import 'package:mubangumi/widgets/brand_qr.dart';
import 'support/ux_visuals.dart';

void main() {
  testWidgets('encrypted migration invitation scans at its 280px display size', (
    tester,
  ) async {
    final payload =
        'mubangumi-config://receive?v=1&host=192.168.1.3&port=34567&id=${'a' * 64}&hash=${'b' * 64}&expires=1790799999999';
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: BrandQr(data: payload, size: 280),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final bytes = await FriendQrExporter.captureBoundary(key, pixelRatio: 3);
      expect(FriendQr.decodePayloadFromImageBytes(bytes), payload);
    });
    await captureUx(tester, key, 'config-transfer-qr');
  });
  for (final size in [112.0, 220.0, 300.0]) {
    for (final payload in [
      'https://bgm.tv/subject/42',
      'https://bgm.tv/index/42',
      'mubangumi:friend:v1:synthetic_user',
      'https://room.example.test/join?token=${'a' * 140}',
    ]) {
      testWidgets(
        'brand QR remains readable at $size: ${payload.substring(0, 20)}',
        (tester) async {
          tester.view.physicalSize = const Size(600, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final key = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(
                  child: RepaintBoundary(
                    key: key,
                    child: BrandQr(data: payload, size: size),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            final bytes = await FriendQrExporter.captureBoundary(
              key,
              pixelRatio: 3,
            );
            expect(FriendQr.decodePayloadFromImageBytes(bytes), payload);
          });
          expect(tester.takeException(), isNull);
          if (size == 220 && payload.endsWith('/subject/42')) {
            await captureUx(tester, key, 'bangumi-brand-qr');
          }
        },
      );
    }
  }
}
