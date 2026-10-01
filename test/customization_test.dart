import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/social/friend_groups.dart';
import 'package:mubangumi/core/theme/anime_icon.dart';
import 'package:mubangumi/core/theme/app_theme.dart';
import 'package:mubangumi/core/theme/custom_colors.dart';
import 'package:mubangumi/core/theme/font_repository.dart';
import 'package:mubangumi/state/custom_colors_controller.dart';
import 'package:mubangumi/state/friend_groups_controller.dart';
import 'package:mubangumi/widgets/biography_dialog.dart';
import 'package:mubangumi/widgets/color_settings_sheet.dart';
import 'package:mubangumi/widgets/community_rich_content.dart';
import 'package:mubangumi/screens/config_transfer_page.dart';
import 'package:mubangumi/state/session_controller.dart';
import 'support/pm_fixtures.dart';
import 'support/ux_visuals.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'search SVG art stays 24px in a 48px field slot like discovery buttons',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    prefixIcon: AnimeIcon(Icons.search_rounded),
                  ),
                ),
                IconButton(
                  onPressed: null,
                  icon: AnimeIcon(Icons.search_rounded),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final art in find.byType(SvgPicture).evaluate()) {
        expect(tester.getSize(find.byWidget(art.widget)), const Size(24, 24));
      }
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'friend groups rename, move, delete and merge without changing local assignments',
    () {
      var local = FriendGroups().rename(null, '一起追番');
      final id = local.names.keys.single;
      local = local.assign('Alice', id).rename(id, '追番伙伴');
      expect(local.members['alice'], id);
      var incoming = FriendGroups().rename(null, '追番伙伴');
      incoming = incoming
          .assign('Bob', incoming.names.keys.single)
          .assign('Alice', incoming.names.keys.single);
      final merged = local.merge(incoming);
      expect(merged.names.length, 1);
      expect(merged.members['bob'], id);
      expect(merged.members['alice'], id);
      expect(merged.merge(incoming).toJson(), merged.toJson());
      expect(merged.remove(id).members, isEmpty);
      expect(() => local.rename(null, '追番伙伴'), throwsFormatException);
    },
  );
  test(
    'friend groups persist per owner and serialize concurrent edits',
    () async {
      const storage = FlutterSecureStorage();
      final alice = FriendGroupsController(1, storage),
          bob = FriendGroupsController(2, storage);
      addTearDown(alice.dispose);
      addTearDown(bob.dispose);
      await Future.wait([alice.ready, bob.ready]);
      await Future.wait([
        alice.edit((g) => g.rename(null, '同好')),
        alice.edit((g) => g.rename(null, '现实好友')),
      ]);
      expect(alice.state.groups.names.length, 2);
      expect(bob.state.groups.names, isEmpty);
      final reopened = FriendGroupsController(1, storage);
      addTearDown(reopened.dispose);
      await reopened.ready;
      expect(reopened.state.groups.toJson(), alice.state.groups.toJson());
    },
  );
  test(
    'a failed group read never overwrites saved data with defaults',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'friend_groups_v1:1': 'broken',
      });
      final controller = FriendGroupsController(
        1,
        const FlutterSecureStorage(),
      );
      addTearDown(controller.dispose);
      await controller.ready;
      await expectLater(
        controller.edit((g) => g.rename(null, '新分组')),
        throwsStateError,
      );
      expect(
        await const FlutterSecureStorage().read(key: 'friend_groups_v1:1'),
        'broken',
      );
    },
  );
  test(
    'failed reloading preserves the last group view and blocks destructive edits',
    () async {
      const storage = FlutterSecureStorage();
      final controller = FriendGroupsController(1, storage);
      addTearDown(controller.dispose);
      await controller.ready;
      await controller.edit((g) => g.rename(null, '已有分组'));
      await storage.write(key: controller.key, value: 'broken');
      await controller.retry();
      expect(controller.state.groups.names.values.single, '已有分组');
      await expectLater(
        controller.edit((g) => g.rename(null, '新分组')),
        throwsStateError,
      );
      expect(await storage.read(key: controller.key), 'broken');
    },
  );
  test(
    'default colors remain exact and custom selections restore and reset',
    () async {
      expect(
        identical(applyCustomColors(AppTheme.light, null), AppTheme.light),
        false,
      ); // getters create themes
      final theme = AppTheme.light;
      expect(identical(applyCustomColors(theme, null), theme), true);
      final controller = CustomColorsController(const FlutterSecureStorage());
      addTearDown(controller.dispose);
      await controller.ready;
      await controller.choose(const CustomColors(primary: Colors.blue));
      final reopened = CustomColorsController(const FlutterSecureStorage());
      addTearDown(reopened.dispose);
      await reopened.ready;
      expect(reopened.state!.primary.toARGB32(), Colors.blue.toARGB32());
      await reopened.choose(null);
      expect(reopened.state, isNull);
      expect(
        await const FlutterSecureStorage().read(
          key: CustomColorsController.key,
        ),
        isNull,
      );
    },
  );
  test(
    'custom backgrounds and buttons retain text contrast for arbitrary colors',
    () {
      for (final canvas in [
        Colors.white,
        Colors.black,
        const Color(0xFF777777),
        const Color(0xFF00AA99),
      ]) {
        for (final theme in [AppTheme.light, AppTheme.dark]) {
          final custom = applyCustomColors(
            theme,
            CustomColors(
              primary: const Color(0xFF9386C8),
              lightCanvas: canvas,
              darkCanvas: canvas,
            ),
          );
          final s = custom.colorScheme;
          double contrast(Color a, Color b) {
            final x = a.computeLuminance(), y = b.computeLuminance();
            return ((x > y ? x : y) + .05) / ((x < y ? x : y) + .05);
          }

          expect(contrast(s.onSurface, s.surface), greaterThanOrEqualTo(4.5));
          expect(contrast(s.primary, canvas), greaterThanOrEqualTo(4.5));
          final b = custom.filledButtonTheme.style!;
          expect(
            contrast(
              b.foregroundColor!.resolve({})!,
              b.backgroundColor!.resolve({})!,
            ),
            greaterThanOrEqualTo(4.5),
          );
        }
      }
    },
  );
  test(
    'font imports validate SFNT, deduplicate by content and restore their registry',
    () async {
      final bytes = await File(
        'assets/fonts/TierPrintSans-Regular.ttf',
      ).readAsBytes();
      expect(validImportedFont(bytes), true);
      expect(
        validImportedFont(
          Uint8List.fromList([0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        ),
        false,
      );
      final malformed = Uint8List.fromList(bytes);
      ByteData.sublistView(malformed).setUint32(20, bytes.length + 1);
      expect(validImportedFont(malformed), false);
      final root = await Directory.systemTemp.createTemp(
        'mubangumi-font-test-',
      );
      addTearDown(() => root.delete(recursive: true));
      final repository = LocalFontRepository(directory: () async => root);
      final first = await repository.importFont('我的字库', bytes),
          duplicate = await repository.importFont('重命名', bytes);
      expect(first.id, duplicate.id);
      expect((await repository.importedFonts()).length, 1);
      final reopened = LocalFontRepository(directory: () async => root);
      expect(await reopened.installed(), contains(first.id));
      expect((await reopened.importedFonts()).single.name, '我的字库');
      await reopened.remove(first);
      expect(await reopened.importedFonts(), isEmpty);
    },
  );
  testWidgets(
    'color editor fits narrow screens with large text and only applies on save',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      final theme = await uxTheme(tester, dark: false);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: Scaffold(
              body: RepaintBoundary(
                key: key,
                child: Material(
                  color: theme.scaffoldBackgroundColor,
                  child: const ColorSettingsSheet(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await captureUx(tester, key, 'custom-colors-320');
      expect(tester.takeException(), isNull);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ColorSettingsSheet)),
      );
      expect(container.read(customColorsProvider), isNull);
      await tester.ensureVisible(find.text('主色'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'biography supports Markdown code, images and folded BBCode at 320px',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      final theme = await uxTheme(tester, dark: false);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: RepaintBoundary(
              key: key,
              child: const BiographyDialog(
                username: 'alice',
                source:
                    '# 喜欢的故事\n\n**一起追番**\n\n```dart\nfinal episode = 1;\n```\n\n![封面](https://example.com/cover.png)\n\n[mask]隐藏的剧透[/mask]',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MarkdownBody), findsWidgets);
      expect(find.byType(Image), findsOneWidget);
      expect(
        ((tester.widget<Image>(find.byType(Image)).image as ResizeImage)
                    .imageProvider
                as NetworkImage)
            .url,
        'https://example.com/cover.png',
      );
      expect(find.byType(CommunityRichContent), findsOneWidget);
      expect(find.textContaining('隐藏的剧透'), findsNothing);
      expect(tester.takeException(), isNull);
      await captureUx(tester, key, 'biography-markdown-320');
      expect(biographyUri('file:///private'), isNull);
      expect(biographyUri('javascript:alert(1)'), isNull);
      expect(biographyUri('https://user:pass@example.com/x'), isNull);
    },
  );
  testWidgets(
    'configuration receiver fits narrow screens and invalidates on account switch',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = PmTestSession();
      final key = GlobalKey();
      final theme = await uxTheme(tester, dark: false);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sessionProvider.overrideWith((ref) => session)],
          child: MaterialApp(
            theme: theme,
            home: RepaintBoundary(
              key: key,
              child: const ConfigTransferPage(
                invitation: 'mubangumi-config://receive',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('接收并解密'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await captureUx(tester, key, 'config-receiver-320');
      session.switchUser(2);
      await tester.pumpAndSettle();
      expect(find.text('账号已变化，请返回重新打开'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
