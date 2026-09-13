import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mubangumi/state/background_controller.dart';
import 'package:mubangumi/state/system_appearance_controller.dart';
import 'support/background_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late File image;
  setUpAll(() async {
    root = await Directory(
      '.dart_tool/background-test-data',
    ).create(recursive: true);
    image = await backgroundTestImage(root);
  });

  test('late restore cannot overwrite a newer adjustment', () async {
    final read = Completer<String?>();
    final store = BackgroundTestStorage()..pendingRead = read.future;
    final controller = BackgroundController(store);
    await controller.setBlur(9);
    read.complete(jsonEncode({'blur': 35}));
    await controller.ready;
    expect(controller.state.blur, 9);
    await controller.flush();
    expect(jsonDecode(store.value!)['blur'], 9);
    controller.dispose();
  });

  test(
    'theme ignores wallpaper adjustments and save status; glass applies once',
    () async {
      final store = BackgroundTestStorage();
      final controller = BackgroundTestController(
        AppBackgroundSettings(enabled: true, imagePath: image.path),
        storage: store,
      );
      await controller.ready;
      final container = ProviderContainer(
        overrides: [
          backgroundSettingsProvider.overrideWith((ref) => controller),
          systemAppearanceProvider.overrideWith(
            (ref) => AppearanceTestController(),
          ),
        ],
      );
      addTearDown(container.dispose);
      var themes = 0;
      final subscription = container.listen(
        backgroundThemeSettingsProvider,
        (_, _) => themes++,
      );
      addTearDown(subscription.close);
      await controller.setBlur(40);
      await controller.setDim(.7);
      await controller.flush();
      expect(themes, 0);
      controller.beginAdjustments();
      await controller.setGlass(.8);
      expect(container.read(backgroundThemeSettingsProvider).glass, .42);
      store.failWrite = true;
      expect(await controller.flush(), isFalse);
      expect(container.read(backgroundThemeSettingsProvider).glass, .8);
      expect(themes, 1);
      store.failWrite = false;
      await controller.flush();
      expect(themes, 1);
      expect(jsonDecode(store.value!).containsKey('appliedSettings'), isFalse);
    },
  );

  test('preset and reduction end an unfinished adjustment', () async {
    final controller = BackgroundTestController(
      AppBackgroundSettings(enabled: true, imagePath: image.path),
    );
    await controller.ready;
    controller.beginAdjustments();
    await controller.setBlur(40);
    await controller.applyPreset(BackgroundPreset.soft);
    expect(controller.state.appliedSettings, isNull);
    expect(controller.state.blur, 10);
    controller.beginAdjustments();
    await controller.setGlass(.8);
    await controller.setReduceTransparency(true);
    expect(controller.state.appliedSettings, isNull);
    expect(controller.state.isActive, isFalse);
    controller.dispose();
  });

  testWidgets('deactivation commits a pending preview', (tester) async {
    final store = BackgroundTestStorage();
    final controller = BackgroundTestController(
      AppBackgroundSettings(enabled: true, imagePath: image.path),
      storage: store,
    );
    await controller.ready;
    tester.binding.handleAppLifecycleStateChanged(ui.AppLifecycleState.resumed);
    controller.beginAdjustments();
    await controller.setBlur(37);
    tester.binding.handleAppLifecycleStateChanged(
      ui.AppLifecycleState.inactive,
    );
    await tester.pump();
    expect(controller.state.appliedSettings, isNull);
    expect(jsonDecode(store.value!)['blur'], 37);
    controller.dispose();
    tester.binding.handleAppLifecycleStateChanged(ui.AppLifecycleState.resumed);
  });

  test('continuous adjustment is debounced and writes are ordered', () async {
    final gate = Completer<void>();
    final store = BackgroundTestStorage()..writeGate = gate.future;
    final controller = BackgroundController(store);
    await controller.ready;
    for (var i = 1; i <= 20; i++) {
      await controller.setBlur(i.toDouble());
    }
    expect(store.writes, isEmpty);
    final first = controller.flush();
    await Future<void>.delayed(Duration.zero);
    await controller.setBlur(40);
    final second = controller.flush();
    expect(store.writes, hasLength(1));
    gate.complete();
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(jsonDecode(store.value!)['blur'], 40);
    controller.dispose();
  });

  test(
    'save failure is visible and retry persists the latest settings',
    () async {
      final store = BackgroundTestStorage()..failWrite = true;
      final controller = BackgroundController(store);
      await controller.ready;
      await controller.setBlur(31);
      expect(await controller.flush(), isFalse);
      expect(controller.state.saveError, contains('未能保存'));
      store.failWrite = false;
      expect(await controller.flush(), isTrue);
      expect(controller.state.saveError, isNull);
      expect(jsonDecode(store.value!)['blur'], 31);
      controller.dispose();
    },
  );

  test(
    'missing restored image disables wallpaper with a visible explanation',
    () async {
      final store = BackgroundTestStorage()
        ..value = jsonEncode({
          'enabled': true,
          'imagePath': '${root.path}/missing.png',
        });
      final controller = BackgroundController(store);
      await controller.ready;
      expect(controller.state.isActive, isFalse);
      expect(controller.state.hasImage, isFalse);
      expect(controller.state.saveError, contains('失效'));
      controller.dispose();
    },
  );

  test('invalid import keeps previous wallpaper and original files', () async {
    final store = BackgroundTestStorage()
      ..value = jsonEncode({'enabled': true, 'imagePath': image.path});
    final controller = BackgroundController(
      store,
      directory: () async => Directory('${root.path}/managed'),
    );
    await controller.ready;
    final invalid = await File(
      '${root.path}/invalid.jpg',
    ).writeAsString('not an image');
    await expectLater(
      controller.setImageFromPath(invalid.path),
      throwsA(anything),
    );
    expect(controller.state.imagePath, image.path);
    expect(controller.state.busy, isFalse);
    expect(await image.exists(), isTrue);
    controller.dispose();
  });

  test('imports a bounded PNG and clears only its managed copy', () async {
    final large = await backgroundTestImage(
      root,
      name: 'large.png',
      width: 3000,
      height: 600,
    );
    final store = BackgroundTestStorage();
    final controller = BackgroundController(
      store,
      directory: () async => Directory('${root.path}/managed'),
    );
    await controller.ready;
    final path = await controller.setImageFromPath(large.path);
    expect(path, endsWith('.png'));
    expect(path, isNot(large.path));
    final buffer = await ui.ImmutableBuffer.fromUint8List(
      await File(path!).readAsBytes(),
    );
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    expect(descriptor.width, 2560);
    expect(descriptor.height, 512);
    descriptor.dispose();
    buffer.dispose();
    final restarted = BackgroundController(store);
    await restarted.ready;
    expect(restarted.state.isActive, isTrue);
    restarted.dispose();
    await controller.clearImage();
    expect(await File(path).exists(), isFalse);
    expect(await large.exists(), isTrue);
    controller.dispose();
  });

  test(
    'clear does not delete a wallpaper outside the exact managed directory',
    () async {
      final store = BackgroundTestStorage()
        ..value = jsonEncode({'enabled': true, 'imagePath': image.path});
      final controller = BackgroundController(
        store,
        directory: () async => Directory('${root.path}/managed'),
      );
      await controller.ready;
      await controller.clearImage();
      expect(await image.exists(), isTrue);
      controller.dispose();
    },
  );

  test('presets and reduce effects keep the selected wallpaper', () async {
    final controller = BackgroundTestController(
      AppBackgroundSettings(enabled: true, imagePath: image.path),
    );
    await controller.ready;
    await controller.applyPreset(BackgroundPreset.soft);
    expect(controller.state.blur, 10);
    await controller.setReduceTransparency(true);
    expect(controller.state.isActive, isFalse);
    expect(controller.state.imagePath, image.path);
    await controller.setReduceTransparency(false);
    expect(controller.state.isActive, isTrue);
    await controller.resetAdjustments();
    expect(controller.state.blur, 22);
    expect(controller.state.dim, .32);
    expect(controller.state.glass, .42);
    controller.dispose();
  });
}
