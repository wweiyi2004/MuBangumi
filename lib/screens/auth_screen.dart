import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app.dart';
import '../core/auth/bangumi_oauth.dart';
import '../core/auth/oauth_builtin.dart';
import '../state/session_controller.dart';
import '../widgets/network_route_picker.dart';
import '../widgets/oauth_authorization_dialog.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _tokenController = TextEditingController();
  bool _hidden = true;
  bool? _hasSavedOAuthConfig;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshOAuthConfigurationState());
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _openTokenPage() async {
    final uri = Uri.parse('https://next.bgm.tv/demo/access-token');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开浏览器')));
    }
  }

  Future<void> _startOAuth({bool editConfiguration = false}) async {
    final session = ref.read(sessionProvider);
    if (session.isRefreshing && session.phase == SessionPhase.signedOut) {
      return;
    }
    ref.read(sessionProvider.notifier).clearMessage();
    // Prefer built-in app (one-tap), then saved custom app, then setup dialog.
    OAuthConfig? config = OAuthBuiltin.config;
    final savedConfig = await ref.read(tokenStoreProvider).readOAuthConfig();
    config ??= savedConfig;
    if (config == null || editConfiguration) {
      if (!mounted) return;
      config = await _showOAuthSetup(
        editConfiguration ? savedConfig ?? OAuthBuiltin.config : config,
      );
    }
    if (config == null || !mounted) return;
    final signedIn = await ref
        .read(sessionProvider.notifier)
        .signInWithOAuth(
          config,
          launchAuthorization: _launchOAuthAuthorization,
        );
    if (!signedIn && mounted) await _refreshOAuthConfigurationState();
  }

  Future<void> _cancelOAuth() async {
    await ref.read(sessionProvider.notifier).cancelOAuthAuthorization();
  }

  String get _oauthHelperText {
    if (!OAuthBuiltin.isConfigured && _hasSavedOAuthConfig == false) {
      return '首次需要创建 Bangumi 开发者应用，配置后即可在软件内授权';
    }
    if (Platform.isWindows) {
      return '将在 MuBangumi 内打开官方授权页，成功后自动关闭';
    }
    if (Platform.isAndroid) {
      return '将在应用内安全标签页打开官方授权页，成功后自动返回';
    }
    // iOS / desktop fallbacks: in-app browser does not auto-deep-link back.
    return '将在应用内安全标签页打开官方授权页，完成后请关闭标签页返回';
  }

  Future<void> _refreshOAuthConfigurationState() async {
    final config = await ref.read(tokenStoreProvider).readOAuthConfig();
    if (!mounted) return;
    setState(() => _hasSavedOAuthConfig = config?.isValid == true);
  }

  Future<bool> _launchOAuthAuthorization(
    Uri authorizationUri,
    Future<Uri> callback,
  ) async {
    if (Platform.isWindows) {
      if (!mounted) return false;
      return showOAuthAuthorizationDialog(
        context,
        authorizationUri: authorizationUri,
        callback: callback,
      );
    }
    final opened = await launchUrl(
      authorizationUri,
      mode: LaunchMode.inAppBrowserView,
      browserConfiguration: const BrowserConfiguration(showTitle: true),
    );
    if (opened) return true;
    return launchUrl(authorizationUri, mode: LaunchMode.externalApplication);
  }

  Future<OAuthConfig?> _showOAuthSetup(OAuthConfig? current) async {
    final clientId = TextEditingController(text: current?.clientId ?? '');
    final clientSecret = TextEditingController(
      text: current?.clientSecret ?? '',
    );
    var hideSecret = true;
    String? error;
    final result = await showDialog<OAuthConfig>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            OAuthBuiltin.isConfigured ? '自定义 OAuth（高级）' : '首次配置 Bangumi OAuth',
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    OAuthBuiltin.isConfigured
                        ? '应用已内置默认 OAuth。仅在需要使用自己的开发者应用时填写下方字段。'
                        : 'Bangumi 官方目前要求每个第三方客户端提供 App ID 和 App Secret。请先在开发者平台创建应用，再把下面的地址原样填写为回调地址。这项配置只需完成一次。',
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                          child: SelectableText(
                            OAuthConfig.redirectUri,
                            style: TextStyle(fontFamily: 'monospace'),
                          ),
                        ),
                        IconButton(
                          tooltip: '复制回调地址',
                          onPressed: () {
                            Clipboard.setData(
                              const ClipboardData(
                                text: OAuthConfig.redirectUri,
                              ),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已复制回调地址')),
                            );
                          },
                          icon: const Icon(Icons.copy_rounded),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => launchUrl(
                      Uri.parse('https://bgm.tv/dev/app'),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('打开 Bangumi 开发者平台'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: clientId,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'App ID',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: clientSecret,
                    obscureText: hideSecret,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'App Secret',
                      prefixIcon: const Icon(Icons.password_rounded),
                      suffixIcon: IconButton(
                        onPressed: () =>
                            setDialogState(() => hideSecret = !hideSecret),
                        icon: Icon(
                          hideSecret
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    'App Secret 仅保存在当前设备的系统安全存储中，不会发送给 MuBangumi 以外的服务。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final config = OAuthConfig(
                  clientId: clientId.text.trim(),
                  clientSecret: clientSecret.text.trim(),
                );
                if (!config.isValid) {
                  setDialogState(() => error = '请填写 App ID 和 App Secret');
                  return;
                }
                Navigator.pop(context, config);
              },
              child: const Text('保存并登录'),
            ),
          ],
        ),
      ),
    );
    clientId.dispose();
    clientSecret.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 850;
    final phone = width < 600;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(phone ? 14 : 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      if (wide) const Expanded(child: _AuthArtwork()),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: wide
                                ? 56
                                : phone
                                ? 18
                                : 24,
                            vertical: wide
                                ? 58
                                : phone
                                ? 28
                                : 38,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const BrandMark(),
                                const SizedBox(height: 28),
                                Text(
                                  '欢迎回来',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineLarge,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  '连接你的 Bangumi 账号，同步收藏与追番进度。',
                                  style: Theme.of(context).textTheme.bodyLarge
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                                const SizedBox(height: 32),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton.icon(
                                    onPressed:
                                        session.isRefreshing &&
                                            session.phase ==
                                                SessionPhase.signedOut
                                        ? null
                                        : _startOAuth,
                                    icon: session.isRefreshing &&
                                            session.phase ==
                                                SessionPhase.signedOut
                                        ? const SizedBox.square(
                                            dimension: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.account_circle_rounded,
                                          ),
                                    label: Text(
                                      session.isRefreshing &&
                                              session.phase ==
                                                  SessionPhase.signedOut
                                          ? '正在等待 Bangumi 授权…'
                                          : OAuthBuiltin.isConfigured
                                          ? '使用 Bangumi 一键登录'
                                          : _hasSavedOAuthConfig == true
                                          ? '使用已保存配置登录'
                                          : _hasSavedOAuthConfig == false
                                          ? '配置 Bangumi 登录'
                                          : '正在检查登录配置…',
                                    ),
                                  ),
                                ),
                                if (session.isRefreshing &&
                                    session.phase == SessionPhase.signedOut) ...[
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      onPressed: _cancelOAuth,
                                      icon: const Icon(Icons.close_rounded),
                                      label: const Text('取消授权'),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 8),
                                Center(
                                  child: Text(
                                    _oauthHelperText,
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.center,
                                  child: TextButton.icon(
                                    onPressed:
                                        session.isRefreshing &&
                                            session.phase ==
                                                SessionPhase.signedOut
                                        ? null
                                        : () => _startOAuth(
                                            editConfiguration: true,
                                          ),
                                    icon: const Icon(
                                      Icons.settings_outlined,
                                      size: 17,
                                    ),
                                    label: Text(
                                      OAuthBuiltin.isConfigured
                                          ? '高级：自定义 OAuth'
                                          : _hasSavedOAuthConfig == true
                                          ? '更换 OAuth 配置'
                                          : '查看 OAuth 配置',
                                    ),
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.center,
                                  child: TextButton.icon(
                                    onPressed: () =>
                                        showNetworkRoutePicker(context, ref),
                                    icon: const Icon(
                                      Icons.alt_route_rounded,
                                      size: 17,
                                    ),
                                    label: Text(
                                      '网络线路：${session.networkRoute.label}',
                                    ),
                                  ),
                                ),
                                if (session.message != null) ...[
                                  const SizedBox(height: 12),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.error_outline_rounded,
                                        size: 19,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.error,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          session.message!,
                                          style: TextStyle(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.error,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    const Expanded(child: Divider()),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      child: Text(
                                        '或使用个人令牌',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelMedium,
                                      ),
                                    ),
                                    const Expanded(child: Divider()),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                ExpansionTile(
                                  tilePadding: EdgeInsets.zero,
                                  childrenPadding: EdgeInsets.zero,
                                  title: const Text('Access Token 备用登录'),
                                  leading: const Icon(Icons.key_rounded),
                                  children: [
                                    TextField(
                                      controller: _tokenController,
                                      obscureText: _hidden,
                                      autocorrect: false,
                                      enableSuggestions: false,
                                      decoration: InputDecoration(
                                        labelText: 'Access Token',
                                        suffixIcon: IconButton(
                                          tooltip: _hidden ? '显示令牌' : '隐藏令牌',
                                          onPressed: () => setState(
                                            () => _hidden = !_hidden,
                                          ),
                                          icon: Icon(
                                            _hidden
                                                ? Icons.visibility_outlined
                                                : Icons.visibility_off_outlined,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: FilledButton.tonal(
                                            onPressed: () => ref
                                                .read(sessionProvider.notifier)
                                                .signIn(_tokenController.text),
                                            child: const Text('使用令牌登录'),
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: '获取个人令牌',
                                          onPressed: _openTokenPage,
                                          icon: const Icon(
                                            Icons.open_in_new_rounded,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 18),
                                Text(
                                  '登录凭据只保存在当前设备的系统安全存储中，不会上传到其他服务器。',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                        height: 1.5,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthArtwork extends StatelessWidget {
  const _AuthArtwork();

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 640),
    padding: const EdgeInsets.all(48),
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF252B42), Color(0xFF323A57)],
      ),
    ),
    child: Stack(
      children: [
        Positioned(
          right: -90,
          top: -90,
          child: Container(
            width: 280,
            height: 280,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [Color(0x99FF6F9D), Color(0x00FF6F9D)],
              ),
            ),
          ),
        ),
        Positioned(
          left: -80,
          bottom: -80,
          child: Container(
            width: 250,
            height: 250,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [Color(0x9938A89D), Color(0x0038A89D)],
              ),
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const _MiniPosterStack(),
            const Spacer(),
            Text(
              '把每一次\n期待都记下来。',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: Colors.white,
                height: 1.18,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '收藏同步 · 章节进度 · 条目发现',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: Colors.white70),
            ),
          ],
        ),
      ],
    ),
  );
}

class _MiniPosterStack extends StatelessWidget {
  const _MiniPosterStack();

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 230,
    child: Stack(
      children: [
        _poster(
          const Color(0xFF38A89D),
          26,
          40,
          -.10,
          Icons.water_drop_outlined,
        ),
        _poster(const Color(0xFFF3A646), 142, 26, .08, Icons.sunny_snowing),
        _poster(const Color(0xFFE95383), 82, 70, 0, Icons.auto_awesome_rounded),
      ],
    ),
  );

  Widget _poster(
    Color color,
    double left,
    double top,
    double turns,
    IconData icon,
  ) => Positioned(
    left: left,
    top: top,
    child: Transform.rotate(
      angle: turns,
      child: Container(
        width: 122,
        height: 178,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white24, width: 2),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 18,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white70, size: 52),
      ),
    ),
  );
}
