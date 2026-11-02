import 'dart:async';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mubangumi/widgets/font_settings_sheet.dart';
import 'support/ux_visuals.dart';
import 'package:mubangumi/core/theme/font_repository.dart';
import 'package:mubangumi/models/app_font.dart';
import 'package:mubangumi/state/font_controller.dart';

void main() {
  testWidgets(
    'font settings fit a 320px screen at large text without automatic downloads',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repository = _Fonts();
      final theme = await uxTheme(tester, dark: false);
      final key = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [fontRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            theme: theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.8)),
              child: RepaintBoundary(key: key, child: child!),
            ),
            home: const Scaffold(body: FontSettingsSheet()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(repository.downloads, 0);
      expect(find.text('默认字体'), findsOneWidget);
      await tester.ensureVisible(find.text('Noto Sans SC'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await captureUx(tester, key, 'font-settings-large');
    },
  );

  test('startup and restore never download an optional font', () async {
    final repository = _Fonts()..selection = downloadableFonts.first.id;
    final controller = FontController(repository);
    addTearDown(controller.dispose);
    await Future<void>.delayed(Duration.zero);
    expect(repository.downloads, 0);
    expect(controller.state.selected, isNull);
    expect(repository.activations, isEmpty);
  });
  test(
    'a downloaded selection restores offline and can return to default',
    () async {
      final repository = _Fonts()
        ..selection = downloadableFonts.first.id
        ..files.add(downloadableFonts.first.id);
      final controller = FontController(repository);
      addTearDown(controller.dispose);
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.selected, downloadableFonts.first);
      expect(repository.downloads, 0);
      await controller.choose(null);
      expect(repository.selection, isNull);
      expect(controller.state.selected, isNull);
    },
  );
  test(
    'choosing default during a download prevents late automatic selection',
    () async {
      final repository = _Fonts()..pending = Completer<void>();
      final controller = FontController(repository);
      addTearDown(controller.dispose);
      await Future<void>.delayed(Duration.zero);
      final download = controller.download(downloadableFonts.first);
      await controller.choose(null);
      repository.pending!.complete();
      await download;
      expect(controller.state.installed, contains(downloadableFonts.first.id));
      expect(controller.state.selected, isNull);
    },
  );
  test(
    'download cancel preserves active font and leaves no installed file',
    () async {
      final repository = _Fonts()
        ..pending = Completer<void>()
        ..selection = downloadableFonts.last.id
        ..files.add(downloadableFonts.last.id);
      final controller = FontController(repository);
      addTearDown(controller.dispose);
      await Future<void>.delayed(Duration.zero);
      final download = controller.download(downloadableFonts.first);
      controller.cancelDownload();
      repository.pending!.complete();
      await download;
      expect(controller.state.downloading, isNull);
      expect(controller.state.installed, {downloadableFonts.last.id});
      expect(controller.state.selected, downloadableFonts.last);
      expect(controller.state.error, '已取消下载');
    },
  );
  test('font validation rejects HTML, partial and altered bytes', () {
    final bytes = Uint8List.fromList([0, 1, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8]);
    final font = AppFont(
      id: 'fixture',
      name: 'fixture',
      family: 'Fixture',
      description: '',
      url: '',
      bytes: bytes.length,
      digest: sha256.convert(bytes).toString(),
      licenseAsset: '',
    );
    expect(validFontDownload((font, bytes)), isTrue);
    expect(
      validFontDownload((font, Uint8List.sublistView(bytes, 0, 9))),
      isFalse,
    );
    bytes[10] = 100;
    expect(validFontDownload((font, bytes)), isFalse);
    expect(
      validFontDownload((font, Uint8List.fromList(List.filled(12, 60)))),
      isFalse,
    );
  });
  test('default theme is identical and optional font reaches controls', () {
    final theme = ThemeData();
    expect(identical(applyAppFont(theme, null), theme), isTrue);
    expect(
      applyAppFont(
        theme,
        downloadableFonts.first,
      ).textTheme.bodyMedium?.fontFamily,
      downloadableFonts.first.family,
    );
  });
}

class _Fonts implements FontRepository {
  String? selection;
  int downloads = 0;
  final files = <String>{};
  final activations = <String>[];
  Completer<void>? pending;
  @override
  Future<String?> readSelection() async => selection;
  @override
  Future<void> saveSelection(String? id) async {
    selection = id;
  }

  @override
  Future<Set<String>> installed() async => {...files};
  @override
  Future<void> activate(AppFont font) async {
    if (!files.contains(font.id)) throw StateError('not downloaded');
    activations.add(font.id);
  }

  @override
  Future<void> remove(AppFont font) async {
    files.remove(font.id);
  }

  @override
  Future<void> download(
    AppFont font,
    CancelToken cancel,
    void Function(double) progress,
  ) async {
    downloads++;
    progress(.5);
    if (pending != null) await pending!.future;
    if (cancel.isCancelled) throw cancel.cancelError!;
    files.add(font.id);
    progress(1);
  }
}
