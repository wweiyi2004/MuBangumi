import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';
import '../storage/sqlite_support.dart';

/// Opt-in installed-package check. Runs before account providers, uses only an
/// in-memory database and a new disposable WebView profile, and makes no HTTP
/// requests. Output contains versions/check results, never local paths or data.
Future<int> runPackageProbe() async {
  var stage = 'metadata';
  WebviewController? browser;
  try {
    final info = await PackageInfo.fromPlatform();
    stage = 'sqlite';
    final db = await sqliteFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    try {
      await db.execute('CREATE TABLE fixture (value INTEGER)');
      await db.insert('fixture', {'value': 7});
      if ((await db.query('fixture')).single['value'] != 7) {
        throw StateError('SQLite check failed');
      }
    } finally {
      await db.close();
    }
    if (Platform.isWindows) {
      stage = 'webview';
      final profile = await Directory.systemTemp.createTemp(
        'mubangumi-package-probe-',
      );
      await WebviewController.initializeEnvironment(
        userDataPath: profile.path,
      ).timeout(const Duration(seconds: 20));
      browser = WebviewController();
      await browser.initialize().timeout(const Duration(seconds: 20));
      runApp(MaterialApp(home: Scaffold(body: Webview(browser))));
      await browser.loadStringContent(
        '<html><body><div id="fixture">package-ready</div></body></html>',
      );
      var ready = false;
      for (var attempt = 0; attempt < 40; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        try {
          Object? value = await browser
              .executeScript(
                'JSON.stringify(document.getElementById("fixture")?.textContent)',
              )
              .timeout(const Duration(seconds: 2));
          for (var count = 0; count < 2 && value is String; count++) {
            if (value == 'package-ready') break;
            value = jsonDecode(value);
          }
          if (value == 'package-ready') {
            ready = true;
            break;
          }
        } catch (_) {
          /* A newly created document can precede its first script context. */
        }
      }
      if (!ready) throw StateError('WebView check failed');
    }
    await _emit({
      'packageProbe': true,
      'version': info.version,
      'build': info.buildNumber,
      'sqlite': true,
      'webview': Platform.isWindows,
    });
    return 0;
  } catch (error) {
    await _emit({
      'packageProbe': false,
      'stage': stage,
      'errorType': error.runtimeType.toString(),
    });
    return 1;
  } finally {
    if (browser != null) {
      runApp(const SizedBox.shrink());
      try {
        await WidgetsBinding.instance.endOfFrame.timeout(
          const Duration(seconds: 2),
        );
      } catch (_) {}
    }
    try {
      await browser?.dispose().timeout(const Duration(seconds: 5));
    } catch (_) {}
  }
}

Future<void> _emit(Map<String, Object> value) async {
  try {
    stdout.writeln(jsonEncode(value));
    await stdout.flush();
  } catch (_) {}
}
