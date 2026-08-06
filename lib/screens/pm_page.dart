import 'package:flutter/material.dart';

import 'community_page.dart';

/// Standalone 站内短信 surface.
///
/// P1 has no PM inbox API; this reuses the in-app Bangumi WebView so users can
/// reach inbox / compose without fully leaving the app (website login required).
class PmPage extends StatelessWidget {
  const PmPage({super.key, this.composeTo});

  /// When set, opens the official compose URL for that username.
  final String? composeTo;

  static const inboxUrl = 'https://bgm.tv/pm';

  static String composeUrl(String username) =>
      'https://bgm.tv/pm/compose/${Uri.encodeComponent(username.trim())}.chii';

  @override
  Widget build(BuildContext context) {
    final target = composeTo?.trim();
    final url = (target != null && target.isNotEmpty)
        ? composeUrl(target)
        : inboxUrl;
    final title = (target != null && target.isNotEmpty)
        ? '发短信 · $target'
        : '站内短信';
    return CommunityWebScreen(
      initialUrl: url,
      title: title,
      showSectionSwitcher: false,
      loginHint: '站内短信使用 Bangumi 官方网页。OAuth 与网站登录独立，首次请在此登录一次。',
    );
  }
}

/// Opens inbox or compose inside the app.
void openPmPage(BuildContext context, {String? composeTo}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PmPage(composeTo: composeTo),
    ),
  );
}
