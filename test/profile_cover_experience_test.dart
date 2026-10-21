import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mubangumi/core/sharing/cover_image_exporter.dart';
import 'package:mubangumi/features/subject_detail/presentation/subject_detail_header.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/widgets/profile_home_layout.dart';
import 'package:mubangumi/widgets/subject_cover_viewer.dart';
import 'package:mubangumi/widgets/subject_widgets.dart';
import 'support/ux_visuals.dart';

final _subject = Subject.fromJson({
  'id': 42,
  'name': 'Original',
  'name_cn': '喜欢的作品',
  'images': {'large': 'https://example.test/cover.png'},
  'type': 2,
});

void main() {
  FilePicker.platform = _Picker();
  testWidgets(
    'personal space places a compact biography above collection statistics',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileHomeLayout(
              nickname: '小沐',
              username: 'fixture',
              sign: '',
              avatarUrl: '',
              total: 80,
              doing: 12,
              friends: 8,
              biography: const Text('第一行自我介绍'),
              selectedTab: 0,
              onSelectTab: (_) {},
              onSettings: () {},
              onCollections: () {},
              onDoing: () {},
              onFriends: () {},
              content: ListView(children: const [Text('动态')]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('第一行自我介绍')).dy,
        lessThan(tester.getTopLeft(find.text('收藏')).dy),
      );
    },
  );
  testWidgets(
    'entry cover opens an interactive gallery and original title is available on demand',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SubjectDetailHeader(
              subject: _subject,
              collection: null,
              busy: false,
              onCollectionChanged: (_) {},
              onManageCollection: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Original'), findsNothing);
      expect(find.text('查看原名'), findsOneWidget);
      await tester.tap(find.byType(SubjectCover));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('封面小画廊'), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      await tester.tap(find.byTooltip('关闭封面'));
      await tester.pumpAndSettle();
      expect(find.byType(SubjectCoverViewer), findsNothing);
    },
  );
  for (final scale in [1.0, 1.8]) {
    testWidgets(
      'gallery long press saves original bytes on a small phone at scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final canvas = img.Image(width: 300, height: 420);
        img.fill(canvas, color: img.ColorRgb8(250, 214, 226));
        final bytes = Uint8List.fromList(img.encodePng(canvas));
        final original = FilePicker.platform;
        final picker = _Picker();
        FilePicker.platform = picker;
        addTearDown(() => FilePicker.platform = original);
        final dio = Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) {
                handler.resolve(
                  Response(
                    requestOptions: options,
                    statusCode: 200,
                    data: bytes,
                  ),
                );
              },
            ),
          );
        final key = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: await uxTheme(tester, dark: false),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: RepaintBoundary(key: key, child: child!),
            ),
            home: Scaffold(
              body: SubjectCoverViewer(
                subject: _subject,
                image: MemoryImage(bytes),
                exporter: CoverImageExporter(dio: dio),
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => precacheImage(
            MemoryImage(bytes),
            tester.element(find.byType(SubjectCoverViewer)),
          ),
        );
        await tester.pumpAndSettle();
        await tester.longPress(find.byType(InteractiveViewer));
        await tester.runAsync(() async {
          final deadline = DateTime.now().add(const Duration(seconds: 5));
          while (picker.bytes == null) {
            if (DateTime.now().isAfter(deadline)) {
              throw StateError('long press did not save the image');
            }
            await tester.pump(const Duration(milliseconds: 20));
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        await tester.pumpAndSettle();
        expect(picker.bytes, bytes);
        expect(picker.filename, 'MuBangumi-cover-42.png');
        expect(find.text('封面已保存到所选位置'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await captureUx(tester, key, 'cover-gallery-$scale');
      },
    );
    testWidgets(
      'friend space uses the shared cover and fits long names at scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final key = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: await uxTheme(tester, dark: scale > 1),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: RepaintBoundary(key: key, child: child!),
            ),
            home: const Scaffold(
              body: SingleChildScrollView(
                child: PublicSpaceHeader(
                  nickname: '喜欢故事的小春',
                  username: 'friend-one',
                  avatarUrl: '',
                  sign: '今天也想遇见一部好作品。',
                  biography: Text('在故事里寻找小小的心动'),
                  footer: Text('TA 的番剧单'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await captureUx(tester, key, 'friend-space-$scale');
      },
    );
  }
}

class _Picker extends FilePicker {
  Uint8List? bytes;
  String? filename;
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
    return 'chosen.png';
  }
}
