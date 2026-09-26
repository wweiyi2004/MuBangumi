import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;
import 'package:webview_flutter/webview_flutter.dart';

/// A separate test entry point: no main.dart, real account or network writes.
/// Only its unique secure-storage key and an in-memory database are modified.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux) {
    ffi.sqfliteFfiInit();
    databaseFactory = ffi.databaseFactoryFfi;
  }
  testWidgets('native secure storage and SQLite write/read cycle', (
    tester,
  ) async {
    const storage = FlutterSecureStorage();
    final key =
        'mubangumi_integration_${DateTime.now().microsecondsSinceEpoch}';
    try {
      await storage.write(key: key, value: 'fixture');
      expect(await storage.read(key: key), 'fixture');
    } finally {
      await storage.delete(key: key);
    }
    final db = await openDatabase(inMemoryDatabasePath);
    try {
      await db.execute('CREATE TABLE fixture (value TEXT)');
      await db.insert('fixture', {'value': 'persisted'});
      expect((await db.query('fixture')).single['value'], 'persisted');
    } finally {
      await db.close();
    }
  });
  testWidgets(
    'mobile WebView JavaScript bridge reads a local fixture',
    (tester) async {
      final controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: WebViewWidget(controller: controller)),
        ),
      );
      await controller.loadHtmlString(
        '<html><body><div id="fixture">bridge-ready</div></body></html>',
      );
      Object? result;
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        try {
          result = await controller.runJavaScriptReturningResult(
            'JSON.stringify({text: document.getElementById("fixture")?.textContent, agent: navigator.userAgent})',
          );
          for (var n = 0; n < 2 && result is String; n++) {
            result = jsonDecode(result);
          }
          if (result is Map && result['text'] == 'bridge-ready') break;
        } catch (_) {}
      }
      expect(result, isA<Map>());
      expect((result as Map)['text'], 'bridge-ready');
      expect(result['agent'], isNotEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !Platform.isAndroid && !Platform.isIOS,
  );
}
