import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/features/anime_appreciation/room_storage.dart';
import 'package:mubangumi/features/anime_appreciation/room_wifi_share.dart';
import 'package:qr_flutter/qr_flutter.dart';

class MemoryVault implements RoomSecretVault {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  test('Wi-Fi payload escapes reserved characters', () {
    expect(
      const RoomWifiNetwork(r'番键会;5G', r'pa:ss,wo"rd\1').payload,
      r'WIFI:T:WPA;S:番键会\;5G;P:pa\:ss\,wo\"rd\\1;;',
    );
    expect(const RoomWifiNetwork('Open', '').payload, 'WIFI:T:nopass;S:Open;;');
  });

  test(
    'Wi-Fi network round-trips through the vault and tolerates junk',
    () async {
      final vault = MemoryVault();
      expect(await RoomWifiNetwork.load(vault), isNull);
      await const RoomWifiNetwork('Home', 'password1').save(vault);
      final loaded = await RoomWifiNetwork.load(vault);
      expect(loaded!.ssid, 'Home');
      expect(loaded.password, 'password1');
      vault.values.updateAll((_, _) => 'not json');
      expect(await RoomWifiNetwork.load(vault), isNull);
      await RoomWifiNetwork.clear(vault);
      expect(vault.values, isEmpty);
    },
  );

  testWidgets('host adds, shows and clears the Wi-Fi QR code', (tester) async {
    final vault = MemoryVault();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [roomWifiVaultProvider.overrideWithValue(vault)],
        child: const MaterialApp(
          home: Scaffold(body: Center(child: RoomWifiJoinCard())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsNothing);

    await tester.tap(find.text('添加 Wi-Fi 二维码'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Hotspot');
    await tester.enterText(find.byType(TextField).last, 'short');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.textContaining('至少 8 位'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'longenough');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('WIFI:T:WPA;S:Hotspot;P:longenough;;')),
      findsOneWidget,
    );
    expect(find.text('Hotspot'), findsOneWidget);
    expect(vault.values, hasLength(1));

    await tester.tap(find.text('修改'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清除'));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsNothing);
    expect(vault.values, isEmpty);
  });
}
