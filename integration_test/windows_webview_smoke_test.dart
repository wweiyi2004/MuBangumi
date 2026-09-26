import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

/// Separate entry point, private disposable browser profile, local HTML only.
/// Never reads the application's accounts, cookies, or secure storage.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Windows WebView starts, renders and reads local HTML', (
    tester,
  ) async {
    if (!Platform.isWindows) return;
    final profile = Directory(
      '${Directory.current.path}/.dart_tool/webview-smoke/'
      '${DateTime.now().microsecondsSinceEpoch}',
    );
    await profile.create(recursive: true);
    await WebviewController.initializeEnvironment(
      userDataPath: profile.path,
    ).timeout(const Duration(seconds: 20));
    final controller = WebviewController();
    try {
      await controller.initialize().timeout(const Duration(seconds: 20));
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: Webview(controller))),
      );
      await controller
          .loadStringContent(
            '<html><body><div id="fixture">bridge-ready</div></body></html>',
          )
          .timeout(const Duration(seconds: 10));
      Object? result;
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        result = await controller
            .executeScript(
              'JSON.stringify({text: document.getElementById("fixture")?.textContent})',
            )
            .timeout(const Duration(seconds: 5));
        for (var n = 0; n < 2 && result is String; n++) {
          result = jsonDecode(result);
        }
        if (result is Map && result['text'] == 'bridge-ready') break;
      }
      expect(result, isA<Map>());
      expect((result as Map)['text'], 'bridge-ready');
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      // Disposal joins unfinished native creation; do not hide a timeout with
      // an unbounded finally block. The isolated profile stays for diagnosis.
      unawaited(controller.dispose().catchError((Object _) {}));
    }
  });
}
