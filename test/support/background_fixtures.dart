import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mubangumi/state/background_controller.dart';
import 'package:mubangumi/state/system_appearance_controller.dart';

class BackgroundTestStorage extends FlutterSecureStorage {
  String? value;
  Future<String?>? pendingRead;
  Future<void>? writeGate;
  bool failWrite = false;
  final writes = <String?>[];
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => pendingRead ?? value;
  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    writes.add(value);
    await writeGate;
    if (failWrite) throw StateError('test write failed');
    this.value = value;
  }
}

class BackgroundTestController extends BackgroundController {
  BackgroundTestController(
    AppBackgroundSettings settings, {
    BackgroundTestStorage? storage,
  }) : super(storage ?? BackgroundTestStorage()) {
    state = settings;
  }
}

class AppearanceTestController extends SystemAppearanceController {
  AppearanceTestController([
    SystemAppearance appearance = const SystemAppearance(),
  ]) : super(supported: false) {
    state = appearance;
  }
  void update(SystemAppearance value) => state = value;
}

Future<File> backgroundTestImage(
  Directory dir, {
  String name = 'wall.png',
  int width = 64,
  int height = 64,
  bool patterned = false,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = Colors.black,
  );
  if (patterned) {
    for (var x = 0; x < width; x += 12) {
      canvas.drawRect(
        Rect.fromLTWH(x.toDouble(), 0, 6, height.toDouble()),
        Paint()..color = x % 24 == 0 ? Colors.white : Colors.pink,
      );
    }
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  image.dispose();
  picture.dispose();
  return file;
}
