import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/application/first_login_check.dart';
import '../models/community_models.dart';
import '../state/account_access_controller.dart';
import '../state/service_providers.dart';
import '../state/session_controller.dart';
import '../state/website_session_controller.dart';
import '../widgets/brand_mark.dart';
import 'website_login_screen.dart';

/// After a new login, confirm the API and website credentials before entering
/// home. It looks like home preparation and only stops for a missing website
/// login; feature checks run alongside to warm caches but never block entry.
class FirstLoginCheckScreen extends ConsumerStatefulWidget {
  const FirstLoginCheckScreen({
    super.key,
    this.checks,
    this.openWebsiteLogin,
    this.featureGrace = const Duration(seconds: 3),
  });

  /// Injected by tests; otherwise built from the signed-in services.
  final FirstLoginChecks? checks;
  final Future<bool?> Function(BuildContext context)? openWebsiteLogin;

  /// How long feature checks may keep warming caches once entry is allowed.
  final Duration featureGrace;

  @override
  ConsumerState<FirstLoginCheckScreen> createState() =>
      _FirstLoginCheckScreenState();
}

class _FirstLoginCheckScreenState extends ConsumerState<FirstLoginCheckScreen> {
  late final FirstLoginChecks _checks = widget.checks ?? _buildChecks();
  bool _openingWebsite = false;
  bool _entered = false;
  Timer? _grace;

  @override
  void initState() {
    super.initState();
    _checks.addListener(_changed);
    unawaited(_checks.runAll());
  }

  @override
  void dispose() {
    _grace?.cancel();
    _checks.removeListener(_changed);
    if (widget.checks == null) _checks.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (!_checks.canEnter) return;
    if (!_checks.running) {
      _enter();
    } else {
      _grace ??= Timer(widget.featureGrace, _enter);
    }
  }

  void _enter() {
    if (_entered || !mounted) return;
    _entered = true;
    _grace?.cancel();
    unawaited(ref.read(sessionProvider.notifier).completeAccessCheck());
  }

  FirstLoginChecks _buildChecks() {
    final user = ref.read(sessionProvider).user!;
    final api = ref.read(bangumiApiProvider);
    final community = ref.read(communityServiceProvider);
    final pm = ref.read(pmServiceProvider);
    final access = ref.read(accountAccessProvider);
    return FirstLoginChecks({
      LoginCheckId.api: () async {
        final me = await api.getMe();
        return me.id == user.id ? null : '接口返回了另一个账号（@${me.username}），请重新登录';
      },
      LoginCheckId.website: () async {
        if (await access.verify(force: true)) return null;
        final website = ref.read(websiteSessionProvider);
        return website.message ?? website.statusLabel;
      },
      LoginCheckId.collections: () async {
        await api.getUserCollectionCounts(user.username);
        return null;
      },
      LoginCheckId.community: () async {
        await community.loadNotices(limit: 1, refresh: true);
        return null;
      },
      LoginCheckId.friendsTimeline: () async =>
          (await community.loadFreshTimelinePage(
            CommunityTimelineMode.friends,
            refresh: true,
          )).notice,
      LoginCheckId.messages: () async {
        await pm.loadInbox();
        return null;
      },
    });
  }

  Future<void> _loginWebsite() async {
    if (_openingWebsite) return;
    setState(() => _openingWebsite = true);
    try {
      final open = widget.openWebsiteLogin ?? openWebsiteLoginScreen;
      await open(context);
    } finally {
      if (mounted) setState(() => _openingWebsite = false);
    }
    // Re-verify regardless: the login page may have saved a session even
    // when it was closed without reporting success.
    if (mounted) await _checks.run(LoginCheckId.website);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = ref.watch(sessionProvider).user?.displayName ?? '';
    final api = _checks[LoginCheckId.api];
    final website = _checks[LoginCheckId.website];
    final String? problem;
    Widget? action;
    if (api.status == LoginCheckStatus.failed) {
      problem = api.detail ?? '暂时无法确认账号，请重试';
      action = FilledButton(
        onPressed: () => unawaited(_checks.run(LoginCheckId.api)),
        child: const Text('重试'),
      );
    } else if (website.status == LoginCheckStatus.failed) {
      problem = '还差一步：登录 Bangumi 网页版，好友动态和私信需要用到。';
      action = FilledButton(
        onPressed: _openingWebsite ? null : _loginWebsite,
        child: const Text('登录网页版'),
      );
    } else {
      problem = null;
    }
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: BrandMark(size: 72)),
                  const SizedBox(height: 28),
                  Text(
                    name.isEmpty ? '登录成功' : '欢迎，$name',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    problem ?? '正在准备你的首页',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 32),
                  if (action == null)
                    const LinearProgressIndicator(minHeight: 4)
                  else ...[
                    action,
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () =>
                          ref.read(sessionProvider.notifier).signOut(),
                      child: const Text('换个账号'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
