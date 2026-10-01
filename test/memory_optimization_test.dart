import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mubangumi/core/network/netaba_api.dart';
import 'package:mubangumi/state/service_providers.dart';
import 'package:mubangumi/widgets/app_memory_host.dart';
import 'package:mubangumi/widgets/bounded_image.dart';
import 'package:mubangumi/widgets/retained_tab_stack.dart';
import 'package:mubangumi/widgets/schedule_export_poster.dart';

void main() {
  testWidgets(
    'large portrait decodes within bounds without changing proportions',
    (tester) async {
      final bytes = img.encodePng(img.Image(width: 1024, height: 2048));
      final provider = boundedImageProvider(
        MemoryImage(bytes),
        width: 64,
        height: 64,
        pixelRatio: 2,
      );
      final dimensions = await tester.runAsync(() async {
        final done = Completer<Size>();
        final stream = provider.resolve(ImageConfiguration.empty);
        final listener = ImageStreamListener((info, _) {
          if (!done.isCompleted) {
            done.complete(
              Size(info.image.width.toDouble(), info.image.height.toDouble()),
            );
          }
          info.dispose();
        }, onError: (error, stack) => done.completeError(error, stack));
        stream.addListener(listener);
        try {
          return await done.future;
        } finally {
          stream.removeListener(listener);
        }
      });
      expect(dimensions, const Size(64, 128));
      // Actual decoded RGBA pixels: 32 KiB instead of the source's 8 MiB.
      expect(dimensions!.width * dimensions.height * 4, 32 * 1024);
    },
  );

  test('resize dimensions have a ceiling and reuse nearby layout sizes', () {
    expect(imageDecodeExtent(48, 2), imageDecodeExtent(47, 2));
    expect(imageDecodeExtent(10000, 3), 2048);
    expect(imageDecodeExtent(double.infinity, 2), 1024);
    final first =
        schedulePosterCoverProvider('https://example.test/cover.jpg')
            as ResizeImage;
    final second =
        schedulePosterCoverProvider('https://example.test/cover.jpg')
            as ResizeImage;
    expect(first.width, 512);
    expect(first.height, 768);
    expect(first.policy, ResizeImagePolicy.fit);
    expect(first.imageProvider, second.imageProvider);
  });

  testWidgets('hidden tabs pause animation and keep their state on return', (
    tester,
  ) async {
    final first = GlobalKey<_AnimatedTabState>();
    final second = GlobalKey<_AnimatedTabState>();
    Widget tabs(int index) => MaterialApp(
      home: RetainedTabStack(
        index: index,
        children: [
          _AnimatedTab(key: first),
          _AnimatedTab(key: second),
        ],
      ),
    );
    await tester.pumpWidget(tabs(0));
    await tester.pump(const Duration(milliseconds: 100));
    final retained = first.currentState!;
    expect(retained.ticks, greaterThan(0));
    expect(second.currentState!.ticks, 0);
    await tester.pumpWidget(tabs(1));
    final pausedTicks = retained.ticks;
    await tester.pump(const Duration(milliseconds: 100));
    expect(retained.ticks, pausedTicks);
    expect(second.currentState!.ticks, greaterThan(0));
    await tester.pumpWidget(tabs(0));
    expect(first.currentState, same(retained));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'memory pressure trims cached reads without creating unused services',
    (tester) async {
      var requests = 0;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              requests++;
              handler.resolve(
                Response(requestOptions: options, data: <String, dynamic>{}),
              );
            },
          ),
        );
      final api = NetabaApi(dio: dio);
      final container = ProviderContainer(
        overrides: [netabaApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      addTearDown(() => dio.close(force: true));
      container.read(netabaApiProvider);
      await tester.runAsync(() async {
        await api.getSubjectHistory(7);
        await api.getSubjectHistory(7);
      });
      expect(requests, 1);
      final cache = PaintingBinding.instance.imageCache;
      final oldBytes = cache.maximumSizeBytes, oldEntries = cache.maximumSize;
      addTearDown(() {
        cache.maximumSizeBytes = oldBytes;
        cache.maximumSize = oldEntries;
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const AppMemoryHost(child: SizedBox()),
        ),
      );
      expect(cache.maximumSizeBytes, 64 * 1024 * 1024);
      expect(cache.maximumSize, 512);
      tester.binding.handleMemoryPressure();
      await tester.runAsync(() => api.getSubjectHistory(7));
      expect(requests, 2);
      expect(container.exists(communityServiceProvider), isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

class _AnimatedTab extends StatefulWidget {
  const _AnimatedTab({super.key});
  @override
  State<_AnimatedTab> createState() => _AnimatedTabState();
}

class _AnimatedTabState extends State<_AnimatedTab>
    with SingleTickerProviderStateMixin {
  late final controller =
      AnimationController(vsync: this, duration: const Duration(seconds: 1))
        ..addListener(() => ticks++)
        ..repeat();
  int ticks = 0;
  @override
  Widget build(BuildContext context) {
    controller;
    return const SizedBox();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}
