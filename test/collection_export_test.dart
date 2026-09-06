import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/screens/collection_stats_page.dart';

void main() {
  testWidgets('share passes a readable JSON file and a valid popover origin', (
    tester,
  ) async {
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('mubangumi-share-test-'),
    ))!;
    addTearDown(() => dir.delete(recursive: true));
    final messenger = tester.binding.defaultBinaryMessenger;
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
    Map<Object?, Object?>? shared;
    messenger.setMockMethodCallHandler(pathChannel, (_) async => dir.path);
    messenger.setMockMethodCallHandler(shareChannel, (call) async {
      if (call.method == 'shareFiles') shared = call.arguments as Map;
      return ''; // User dismisses the native sheet.
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(pathChannel, null);
      messenger.setMockMethodCallHandler(shareChannel, null);
    });
    await _openMenu(tester);
    await tester.tap(find.text('分享收藏文件'));
    await _waitForNative(tester, () => shared != null);
    final filename = (shared!['paths'] as List).single as String;
    expect(filename, endsWith('.json'));
    expect(shared!['mimeTypes'], ['application/json']);
    expect(shared!['originWidth'] as num, greaterThan(0));
    expect(shared!['originHeight'] as num, greaterThan(0));
    final payload = await tester.runAsync(
      () async => jsonDecode(await File(filename).readAsString()) as Map,
    );
    expect(payload!['username'], 'alice');
    expect((payload['collections'] as List).single['comment'], '中文短评');
    expect(find.textContaining('导出失败'), findsNothing);
  });
  testWidgets('save dialog receives UTF-8 JSON with full collection metadata', (
    tester,
  ) async {
    final picker = _Picker()..destination = 'chosen.json';
    await _export(tester, picker);
    final json = jsonDecode(utf8.decode(picker.bytes!)) as Map;
    expect(json['username'], 'alice');
    expect(json['count'], 1);
    expect(json['schema_version'], 1);
    final item = (json['collections'] as List).single as Map;
    expect(item['comment'], '中文短评');
    expect(item['tags'], ['治愈']);
    expect(item['private'], isTrue);
    expect(item['episode_status'], 3);
    expect(picker.filename, startsWith('MuBangumi_alice_'));
    expect(picker.filename, endsWith('.json'));
    expect(find.text('收藏数据已保存到所选位置'), findsOneWidget);
  });

  testWidgets(
    'canceling the native save dialog does not report success or failure',
    (tester) async {
      final picker = _Picker();
      await _export(tester, picker);
      expect(find.text('收藏数据已保存到所选位置'), findsNothing);
      expect(find.textContaining('导出失败'), findsNothing);
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.file_download_outlined),
            )
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('save failures remain visible and allow another export', (
    tester,
  ) async {
    final picker = _Picker()..fail = true;
    await _export(tester, picker);
    expect(find.textContaining('导出失败'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.file_download_outlined),
          )
          .onPressed,
      isNotNull,
    );
  });
}

Future<void> _export(WidgetTester tester, _Picker picker) async {
  FilePicker.platform = picker;
  await _openMenu(tester);
  await tester.tap(find.text('另存为 JSON'));
  await _waitForNative(tester, () => picker.called.isCompleted);
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: CollectionStatsPage(
        username: 'alice',
        collections: [
          UserCollection.fromJson({
            'subject_id': 1,
            'subject_type': 2,
            'type': 3,
            'rate': 8,
            'ep_status': 3,
            'comment': '中文短评',
            'tags': ['治愈'],
            'private': true,
            'subject': {'id': 1, 'type': 2, 'name': '测试', 'eps': 12},
          }),
        ],
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('导出收藏数据'));
  await tester.pumpAndSettle();
  expect(find.text('分享收藏文件'), findsOneWidget);
}

Future<void> _waitForNative(
  WidgetTester tester,
  bool Function() completed,
) async {
  await tester.runAsync(() async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!completed()) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('native export was not called');
      }
      await tester.pump(const Duration(milliseconds: 20));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await tester.pump();
  });
  await tester.pumpAndSettle();
}

class _Picker extends FilePicker {
  final called = Completer<void>();
  Uint8List? bytes;
  String? filename;
  String? destination;
  bool fail = false;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    this.bytes = bytes;
    filename = fileName;
    called.complete();
    if (fail) throw StateError('write failed');
    return destination;
  }
}
