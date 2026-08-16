import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/external_link.dart';
import 'package:mubangumi/screens/community_page.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _RecordingLauncher extends UrlLauncherPlatform {
  final launched = <(String, PreferredLaunchMode)>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add((url, options.mode));
    return true;
  }
}

void main() {
  final originalLauncher = UrlLauncherPlatform.instance;
  late _RecordingLauncher launcher;

  setUp(() {
    launcher = _RecordingLauncher();
    UrlLauncherPlatform.instance = launcher;
  });

  tearDown(() {
    UrlLauncherPlatform.instance = originalLauncher;
  });

  group('launchExternalLink', () {
    test('dispatches http and https URLs to external applications', () async {
      expect(
        await launchExternalLink(Uri.parse('https://bgm.tv/subject/8')),
        isTrue,
      );
      expect(
        await launchExternalLink(Uri.parse('http://example.com/a')),
        isTrue,
      );
      expect(launcher.launched, [
        ('https://bgm.tv/subject/8', PreferredLaunchMode.externalApplication),
        ('http://example.com/a', PreferredLaunchMode.externalApplication),
      ]);
    });

    test('drops content-controlled non-http schemes', () async {
      expect(
        await launchExternalLink(Uri.parse('intent://x/#Intent;end')),
        isFalse,
      );
      expect(await launchExternalLink(Uri.parse('file:///C:/x')), isFalse);
      expect(
        await launchExternalLink(Uri.parse('javascript:alert(1)')),
        isFalse,
      );
      expect(
        await launchExternalLink(Uri.parse('mubangumi://oauth/complete')),
        isFalse,
      );
      expect(await launchExternalLink(Uri.parse('/relative/path')), isFalse);
      expect(await launchExternalLink(null), isFalse);
      expect(launcher.launched, isEmpty);
    });

    test('scheme matching is case-insensitive', () async {
      expect(
        await launchExternalLink(Uri.parse('HTTPS://Example.com')),
        isTrue,
      );
      // Uri.parse lowercases the scheme and host of hierarchical URIs.
      expect(launcher.launched.single.$1, 'https://example.com');
    });
  });

  group('isBangumiCommunityHost', () {
    test('allows Bangumi domains and their subdomains', () {
      expect(
        isBangumiCommunityHost(Uri.parse('https://bgm.tv/rakuen')),
        isTrue,
      );
      expect(isBangumiCommunityHost(Uri.parse('https://ui.bgm.tv/x')), isTrue);
      expect(isBangumiCommunityHost(Uri.parse('https://bangumi.tv/a')), isTrue);
      expect(
        isBangumiCommunityHost(Uri.parse('https://api.bangumi.tv')),
        isTrue,
      );
      expect(isBangumiCommunityHost(Uri.parse('https://chii.in/group')), isTrue);
    });

    test('rejects lookalikes and unrelated hosts', () {
      expect(isBangumiCommunityHost(Uri.parse('https://notbgm.tv')), isFalse);
      expect(
        isBangumiCommunityHost(Uri.parse('https://bgm.tv.evil.com')),
        isFalse,
      );
      expect(isBangumiCommunityHost(Uri.parse('https://evil.com')), isFalse);
      expect(
        isBangumiCommunityHost(Uri.parse('https://bgm.tv.example')),
        isFalse,
      );
    });

    test('rejects Bangumi hosts on non-http schemes', () {
      expect(isBangumiCommunityHost(Uri.parse('javascript://bgm.tv/x')), isFalse);
      expect(
        isBangumiCommunityHost(Uri.parse('intent://bgm.tv/#Intent;end')),
        isFalse,
      );
      expect(isBangumiCommunityHost(Uri.parse('file://bgm.tv/x')), isFalse);
    });
  });

  group('isBenignEmbeddedWebViewUrl', () {
    test('allows about:blank and about:srcdoc only', () {
      expect(isBenignEmbeddedWebViewUrl(Uri.parse('about:blank')), isTrue);
      expect(isBenignEmbeddedWebViewUrl(Uri.parse('about:srcdoc')), isTrue);
      expect(isBenignEmbeddedWebViewUrl(Uri.parse('about:config')), isFalse);
      expect(
        isBenignEmbeddedWebViewUrl(Uri.parse('javascript://bgm.tv/x')),
        isFalse,
      );
      expect(
        isBenignEmbeddedWebViewUrl(Uri.parse('https://bgm.tv/rakuen')),
        isFalse,
      );
    });
  });
}
