import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/network/bangumi_endpoints.dart';
import '../core/network/network_route_probe.dart';
import '../state/session_controller.dart';

const _proxyGuideUrl = 'https://catcat.blog/2026/05/bangumi-reverse-proxy';

Future<void> showNetworkRoutePicker(
  BuildContext context,
  WidgetRef ref, {
  BangumiRouteProbe? probe,
}) async {
  final current = ref.read(sessionProvider).networkRoute;
  final selected = await showDialog<BangumiNetworkRoute>(
    context: context,
    builder: (context) => _NetworkRouteDialog(
      current: current,
      probe: probe ?? BangumiRouteProbe.shared,
    ),
  );
  if (selected == null || selected == current || !context.mounted) return;
  if (selected.isThirdParty) {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.security_rounded),
        title: const Text('启用第三方 Bangumi 反代？'),
        content: const Text(
          'API 请求和图片将通过 bgmapi.anibt.net 与 bgmimg.anibt.net。'
          '同步收藏、点格子等鉴权请求的 Access Token 也会经过该第三方服务器。\n\n'
          '反代不能解决 OAuth、超展开和官网页面的连接问题。请确认你信任该服务后再继续。',
        ),
        actions: [
          TextButton.icon(
            onPressed: () => launchUrl(
              Uri.parse(_proxyGuideUrl),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.open_in_new_rounded, size: 17),
            label: const Text('查看说明'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('信任并启用'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
  }
  String? error;
  try {
    error = await ref.read(sessionProvider.notifier).setNetworkRoute(selected);
  } catch (_) {
    // The controller degrades storage failures internally, but an unexpected
    // error must still reach the user instead of the zone handler.
    error = '切换线路时发生了意外错误，请稍后重试';
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(error ?? '已切换到「${selected.label}」')));
}

class _NetworkRouteDialog extends StatefulWidget {
  const _NetworkRouteDialog({required this.current, required this.probe});

  final BangumiNetworkRoute current;
  final BangumiRouteProbe probe;

  @override
  State<_NetworkRouteDialog> createState() => _NetworkRouteDialogState();
}

class _NetworkRouteDialogState extends State<_NetworkRouteDialog> {
  Map<BangumiNetworkRoute, NetworkRouteProbeResult> _results = const {};
  bool _probing = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_probeAll);
  }

  Future<void> _probeAll({bool force = false}) async {
    setState(() => _probing = true);
    final entries = await Future.wait([
      for (final route in BangumiNetworkRoute.values)
        widget.probe
            .probe(route, force: force)
            .then((result) => MapEntry(route, result)),
    ]);
    if (!mounted) return;
    setState(() {
      _results = Map.fromEntries(entries);
      _probing = false;
    });
  }

  @override
  Widget build(BuildContext context) => SimpleDialog(
    title: const Text('选择 Bangumi 网络线路'),
    children: [
      for (final route in BangumiNetworkRoute.values)
        ListTile(
          leading: Icon(
            route == BangumiNetworkRoute.official
                ? Icons.public_rounded
                : Icons.alt_route_rounded,
          ),
          title: Text(route.label),
          subtitle: Text(
            '${route.description}\n${_results[route]?.summary ?? '正在测速…'}',
          ),
          isThreeLine: true,
          trailing: route == widget.current
              ? Icon(
                  Icons.check_circle_rounded,
                  color: Theme.of(context).colorScheme.primary,
                )
              : null,
          onTap: () => Navigator.pop(context, route),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _probing ? null : () => _probeAll(force: true),
            icon: _probing
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.speed_rounded),
            label: Text(_probing ? '正在测速' : '重新测速'),
          ),
        ),
      ),
      const Padding(
        padding: EdgeInsets.fromLTRB(24, 8, 24, 4),
        child: Text(
          '测速仅检查 v0 API。反代 GET 请求遇到瞬时超时或网关错误会自动重试一次；'
          '收藏和章节修改会先保存在本机，联网后自动补传；'
          'OAuth 登录、社区 P1 和官网页面仍使用官方线路。',
          style: TextStyle(fontSize: 12),
        ),
      ),
    ],
  );
}
