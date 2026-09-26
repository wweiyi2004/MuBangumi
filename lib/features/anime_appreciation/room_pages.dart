import 'dart:async';
import 'dart:io';
import 'package:banjian_server/banjian_server.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/bangumi_models.dart';
import '../../state/session_controller.dart';
import 'room_connection.dart';
import 'participant_workspace.dart';
import 'room_host.dart';
import 'room_admin_page.dart';
import 'room_danmaku.dart';
import 'room_wifi_share.dart';
import '../../widgets/ascii_refresh.dart';
import '../tier_print/tier_print_page.dart';

void roomMessage(BuildContext context, Object text) {
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(text.toString())));
  }
}

Future<void> openRoomInvite(BuildContext context, RoomInvite invite) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => RoomParticipationPage(invite: invite)),
    );

class ExperimentalFeaturesPage extends StatelessWidget {
  const ExperimentalFeaturesPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('实验性功能')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('提前体验正在完善的新功能。', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(18),
            leading: const Icon(Icons.content_cut),
            title: const Text('从夯到拉 · 打印工坊'),
            subtitle: const Text('季度 / 全年封面裁剪页与同尺寸排行榜底板'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const TierPrintPage()),
            ),
          ),
        ),
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(18),
            leading: const Icon(Icons.movie_filter_outlined),
            title: const Text('番剧鉴赏 · 番键会'),
            subtitle: const Text('选番、扫码入场、匿名评分和短评'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const RoomHostPage()),
            ),
          ),
        ),
      ],
    ),
  );
}

class RoomHostPage extends ConsumerStatefulWidget {
  const RoomHostPage({super.key});
  @override
  ConsumerState<RoomHostPage> createState() => _RoomHostPageState();
}

class _RoomHostPageState extends ConsumerState<RoomHostPage> {
  final _hostLoading = GlobalKey<AsciiRefreshState>();
  bool _remote = false, _working = false;
  String? _address;
  final _server = TextEditingController(), _password = TextEditingController();
  @override
  void dispose() {
    _server.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(
    Future<void> Function() action, {
    bool animate = false,
  }) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      if (animate && _hostLoading.currentState != null) {
        await _hostLoading.currentState!.refresh(
          initial: !ref.read(roomHostProvider).running,
          task: () async {
            try {
              await action();
            } catch (error) {
              if (mounted) roomMessage(context, error);
              rethrow;
            }
          },
        );
      } else {
        await action();
      }
    } catch (e) {
      if (mounted) roomMessage(context, e);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<String?> _input(
    String title, {
    String initial = '',
    int maxLength = 80,
  }) async {
    final c = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: maxLength,
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    // The dialog route may still animate out after its result completes.
    Future<void>.delayed(const Duration(seconds: 1), c.dispose);
    return result;
  }

  Future<void> _invite(RoomHost host) async {
    if (_working) return;
    // A freshly started service has no activity yet; create one on the way.
    String? title;
    if (!host.history.any((v) => v['ended'] != true)) {
      title = await _input('先创建番键会', initial: '今晚的番键会');
      if (title == null || title.isEmpty || !mounted) return;
    }
    setState(() => _working = true);
    late RoomInvite invite;
    try {
      if (title != null) await host.command('create', {'title': title});
      invite = await host.prepareInvite(preferred: _address);
    } catch (e) {
      if (mounted) roomMessage(context, e);
      return;
    } finally {
      if (mounted) setState(() => _working = false);
    }
    if (!mounted) return;
    final e = host.event;
    if (e == null) return;
    final lan = !host.remote && isPrivateLanHost(invite.base.host);
    Widget joinCode(double size) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (lan) ...[
          Text('② 连上后扫码参与', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 12),
        ],
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(12),
          child: QrImageView(data: invite.url, size: size),
        ),
      ],
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final current = ref.watch(roomHostProvider).event;
          if (current?['id'] != invite.eventId || current?['ended'] == true) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('这张二维码对应的活动已结束或已切换'),
                    const SizedBox(height: 12),
                    const Text('请关闭后重新点击「邀请参与」，获取当前活动的二维码。'),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('关闭'),
                    ),
                  ],
                ),
              ),
            );
          }
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    e['title'],
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text('扫码加入 · 有名入场，匿名评分'),
                  const SizedBox(height: 20),
                  if (!lan)
                    joinCode(230)
                  else
                    LayoutBuilder(
                      builder: (context, box) => box.maxWidth >= 520
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Expanded(
                                  child: RoomWifiJoinCard(qrSize: 200),
                                ),
                                const SizedBox(width: 24),
                                Expanded(child: joinCode(200)),
                              ],
                            )
                          : Column(
                              children: [
                                const RoomWifiJoinCard(),
                                const SizedBox(height: 24),
                                joinCode(230),
                              ],
                            ),
                    ),
                  const SizedBox(height: 16),
                  SelectableText(invite.url, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: invite.url),
                          );
                          if (context.mounted) roomMessage(context, '已复制参与链接');
                        },
                        icon: const Icon(Icons.copy),
                        label: const Text('复制链接'),
                      ),
                      OutlinedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          openRoomInvite(this.context, invite);
                        },
                        child: const Text('本机参与'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    host.remote
                        ? '此链接可通过网络参与，不包含管理密码。'
                        : !isPrivateLanHost(invite.base.host)
                        ? '当前仅支持本机参与。请连接 Wi-Fi / 开启热点后重新分享二维码。'
                        : '对方先用系统相机扫 ① 加入网络，再扫 ② 参与：MuBangumi 自动寻找可用地址，其他扫码工具直接进入网页。参与二维码只包含参与权限。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openWeb(RoomHost host) async {
    await launchUrl(
      (_address == null ? host.base! : Uri.parse(_address!))
          .resolve('/admin')
          .replace(
            queryParameters: {
              'theme': Theme.of(context).brightness == Brightness.dark
                  ? 'dark'
                  : 'light',
            },
          ),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _openAdmin(RoomHost host) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => RoomAdminPage(
        subjectPicker: (_) => const RoomSubjectPicker(),
        onInvite: () => _invite(host),
        onOpenWeb: () => _openWeb(host),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final host = ref.watch(roomHostProvider);
    final e = host.event;
    final disabled = host.busy || _working;
    final hasActive = host.history.any((v) => v['ended'] != true);
    if (_address != null && !host.addresses.contains(_address)) {
      _address = null;
    }
    final shareAddress = _address ?? host.addresses.firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: const Text('番剧鉴赏'),
        actions: [
          IconButton(
            onPressed: host.running
                ? () => _run(() async {
                    await host.refreshAddresses();
                    await host.refresh();
                  }, animate: true)
                : null,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新地址和活动',
          ),
        ],
      ),
      body: AsciiRefresh(
        key: _hostLoading,
        initialRefresh: host.running,
        onRefresh: () async {
          if (host.running) {
            await host.refreshAddresses();
            await host.refresh(wait: true);
            if (host.error != null) throw StateError(host.error!);
          }
        },
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.science_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    const Text('实验性功能 · 番键会'),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '把喜欢的番剧，放到一起聊',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text('服务设备保存活动。管理端可以是这台设备，也可以是另一台电脑。'),
                const SizedBox(height: 24),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: Text('本机局域网'),
                      icon: Icon(Icons.wifi),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('连接服务器'),
                      icon: Icon(Icons.cloud_outlined),
                    ),
                  ],
                  selected: {host.running ? host.remote : _remote},
                  onSelectionChanged: host.running || disabled
                      ? null
                      : (v) => setState(() => _remote = v.first),
                ),
                const SizedBox(height: 16),
                if (!host.running && _remote) ...[
                  TextField(
                    controller: _server,
                    decoration: const InputDecoration(
                      labelText: '服务器地址',
                      hintText: 'https://banjian.example.com',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: '服务器管理密码'),
                  ),
                  const SizedBox(height: 8),
                  const Text('连接部署好的番键会服务。手机关闭后，在线活动仍由服务器承载。'),
                ],
                if (!host.running) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: disabled
                        ? null
                        : () => _run(() async {
                            if (_remote) {
                              await host.connectRemote(
                                Uri.parse(_server.text.trim()),
                                _password.text,
                              );
                            } else {
                              await host.start();
                            }
                          }, animate: true),
                    icon: disabled
                        ? const Icon(Icons.movie_outlined, size: 18)
                        : Icon(
                            _remote
                                ? Icons.cloud_sync_outlined
                                : Icons.play_arrow,
                          ),
                    label: Text(_remote ? '连接管理服务' : '启动局域网服务'),
                  ),
                  const SizedBox(height: 12),
                  const Text('局域网模式请保持服务设备开机、联网。热点需在系统设置中开启。'),
                  if (Platform.isIOS)
                    const Text('iOS 当前支持参与和远程管理，本机服务请使用 Android 或 Windows。'),
                ],
                if (host.error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      host.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (host.running) ...[
                  if (e?['ended'] == true)
                    Card(
                      child: ListTile(
                        title: const Text('正在查看已结束的活动'),
                        subtitle: const Text('历史活动不能邀请新参与者，请使用当前活动的新二维码。'),
                        trailing: host.history.any((v) => v['ended'] != true)
                            ? TextButton(
                                onPressed: () => _run(
                                  () => host.refresh(
                                    eventId: host.history.firstWhere(
                                      (v) => v['ended'] != true,
                                    )['id'],
                                  ),
                                ),
                                child: const Text('返回当前活动'),
                              )
                            : null,
                      ),
                    ),
                  if (host.networkNotice != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(host.networkNotice!),
                    ),
                  if (host.hasPendingCommand)
                    Card(
                      child: ListTile(
                        title: const Text('有一项管理操作尚未确认'),
                        subtitle: const Text('先核对上次操作，避免重复添加或切换轮次。'),
                        trailing: TextButton(
                          onPressed: disabled
                              ? null
                              : () => _run(host.retryCommand),
                          child: const Text('核对'),
                        ),
                      ),
                    ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.circle,
                                color: Colors.green,
                                size: 10,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                host.remote ? '已连接在线服务器' : '局域网服务运行中',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            host.remote
                                ? '在线参与地址'
                                : _address == null
                                ? '自动推荐 · ${host.addressLabel(shareAddress ?? '')}'
                                : '已选择 · ${host.addressLabel(shareAddress ?? '')}',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 6),
                          SelectableText(shareAddress ?? ''),
                          if (!host.remote &&
                              (shareAddress?.startsWith('http://127.') ??
                                  false))
                            const Text(
                              '尚未找到可分享的局域网地址。请连接 Wi-Fi 或开启热点；当前仅本机可进入。',
                            ),
                          if (!host.remote)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                '直接点击「邀请参与」即可。MuBangumi 扫码会自动尝试备选地址；系统相机等扫码工具使用上方地址。',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          if (host.addresses.length > 1)
                            ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              title: const Text('连接问题 / 切换网络'),
                              children: [
                                DropdownButtonFormField<String>(
                                  key: ValueKey(shareAddress),
                                  isExpanded: true,
                                  initialValue: shareAddress,
                                  items: host.addresses
                                      .map(
                                        (a) => DropdownMenuItem(
                                          value: a,
                                          child: Text(
                                            '${host.addressLabel(a)} · $a',
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) =>
                                      setState(() => _address = v),
                                  decoration: const InputDecoration(
                                    labelText: '网页参与使用的地址',
                                  ),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      setState(() => _address = null),
                                  child: const Text('恢复自动推荐'),
                                ),
                              ],
                            ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 12,
                            runSpacing: 10,
                            children: [
                              FilledButton.icon(
                                onPressed: () => _openAdmin(host),
                                icon: const Icon(Icons.dashboard_outlined),
                                label: const Text('进入管理'),
                              ),
                              OutlinedButton.icon(
                                // Viewing an ended activity while another is
                                // live must not create a second one.
                                onPressed:
                                    disabled ||
                                        (e?['ended'] == true && hasActive)
                                    ? null
                                    : () => _invite(host),
                                icon: const Icon(Icons.qr_code),
                                label: const Text('邀请参与'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          if (host.password != null) ...[
                            const Text('管理密码 · 仅分享给主持人'),
                            const SizedBox(height: 6),
                            SelectableText(
                              host.password!,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 6),
                            const Text('服务重启会更换管理密码。参与二维码不含此密码。'),
                          ],
                          const SizedBox(height: 12),
                          const Text(
                            '关闭管理网页不会停止活动。若同网设备无法访问，请检查网卡、防火墙或 Wi-Fi 客户端隔离。',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          TextButton(
                            onPressed: disabled
                                ? null
                                : () => _run(() async {
                                    final yes = await showDialog<bool>(
                                      context: context,
                                      builder: (c) => AlertDialog(
                                        title: Text(
                                          host.remote ? '断开管理连接？' : '停止服务？',
                                        ),
                                        content: Text(
                                          host.remote
                                              ? '服务器中的活动会继续运行。'
                                              : '参与端将断开，已确认数据保留；可以稍后重新启动恢复。',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(c, false),
                                            child: const Text('取消'),
                                          ),
                                          FilledButton(
                                            onPressed: () =>
                                                Navigator.pop(c, true),
                                            child: const Text('确定'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (yes == true) await host.stop();
                                  }),
                            child: Text(host.remote ? '断开管理连接' : '停止本机服务'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (e != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e['title'],
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${e['ended'] == true ? '已结束' : '进行中'} · ${(e['rounds'] as List).length} 部番剧 · ${e['memberCount']} 人已入场',
                            ),
                            const SizedBox(height: 16),
                            if (e['ended'] != true)
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: disabled
                                        ? null
                                        : () => Navigator.of(context).push(
                                            MaterialPageRoute<void>(
                                              builder: (_) =>
                                                  const RoomSubjectPicker(),
                                            ),
                                          ),
                                    icon: const Icon(Icons.playlist_add),
                                    label: const Text('添加番剧 / 导入收藏'),
                                  ),
                                  OutlinedButton(
                                    onPressed: () => _invite(host),
                                    child: const Text('分享参与入口'),
                                  ),
                                ],
                              ),
                            for (final r in e['rounds'] as List)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(r['subject']['title']),
                                subtitle: Text(_status(r['status'])),
                                trailing:
                                    r['status'] == 'waiting' &&
                                        e['ended'] != true
                                    ? TextButton(
                                        onPressed: disabled
                                            ? null
                                            : () => _run(
                                                () => host.command('start', {
                                                  'round': r['id'],
                                                }),
                                              ),
                                        child: const Text('开始'),
                                      )
                                    : null,
                              ),
                            const Text(
                              '评分开关、匿名短评管理、统计、导出和结束活动，请进入管理页面。',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            if ((e['rounds'] as List).any(
                              (r) => (r['subject']['cover'] as String? ?? '')
                                  .isEmpty,
                            ))
                              TextButton.icon(
                                onPressed: disabled
                                    ? null
                                    : () => _run(() async {
                                        await host.api!.request(
                                          'repair-covers',
                                          {'event': e['id']},
                                        );
                                        if (context.mounted) {
                                          roomMessage(
                                            context,
                                            '正在后台补齐封面，请保持服务设备联网',
                                          );
                                        }
                                      }),
                                icon: const Icon(Icons.image_outlined),
                                label: const Text('重试补全封面'),
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (e == null || !hasActive)
                    FilledButton.icon(
                      onPressed: disabled
                          ? null
                          : () => _run(() async {
                              final name = await _input(
                                '创建番键会',
                                initial: '今晚的番键会',
                              );
                              if (name != null && name.isNotEmpty) {
                                await host.command('create', {'title': name});
                              }
                            }),
                      icon: const Icon(Icons.add),
                      label: const Text('创建新活动'),
                    ),
                  const SizedBox(height: 24),
                  Text('历史活动', style: Theme.of(context).textTheme.titleMedium),
                  for (final item in host.history)
                    ListTile(
                      title: Text(item['title']),
                      subtitle: Text(
                        '${item['ended'] == true ? '已结束' : '进行中'} · ${item['rounds']} 部番剧',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          _run(() => host.refresh(eventId: item['id'])),
                    ),
                ],
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () async {
                    final raw = await _input('粘贴参与链接', maxLength: 2048);
                    if (raw == null || !context.mounted) return;
                    final target = RoomInvite.parse(raw);
                    if (target == null) {
                      roomMessage(context, '请粘贴完整番键会邀请链接');
                      return;
                    }
                    await openRoomInvite(context, target);
                  },
                  icon: const Icon(Icons.link),
                  label: const Text('通过邀请链接参与'),
                ),
                const ParticipationReturnTile(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RoomSubjectPicker extends ConsumerStatefulWidget {
  const RoomSubjectPicker({super.key});
  @override
  ConsumerState<RoomSubjectPicker> createState() => _RoomSubjectPickerState();
}

class _RoomSubjectPickerState extends ConsumerState<RoomSubjectPicker> {
  final _query = TextEditingController();
  final _searchAnimation = GlobalKey<AsciiRefreshState>();
  Future<void> _requestSearch() async {
    await _searchAnimation.currentState?.refresh();
  }

  List<Json> _results = [];
  final _selected = <String, Json>{};
  bool _local = false, _busy = false;
  String? _error;
  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(roomHostProvider)
          .api!
          .request('search?q=${Uri.encodeQueryComponent(_query.text.trim())}');
      if (mounted) {
        setState(() => _results = (result['subjects'] as List).cast<Json>());
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    setState(() => _busy = true);
    final host = ref.read(roomHostProvider);
    try {
      for (final entry in _selected.entries.toList()) {
        Json subject = entry.value;
        if (!entry.key.startsWith('local:')) {
          subject = await host.api!.request('subject?id=${subject['id']}');
        }
        await host.command('add', {'subject': subject});
        _selected.remove(entry.key);
      }
      if (mounted) {
        roomMessage(context, '已加入番单，封面会在后台补齐');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = '${e.toString()}；已添加的条目保留，可继续添加剩余条目');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final collections = ref.watch(sessionProvider.select((v) => v.collections));
    final items = _local
        ? collections
              .where(
                (v) =>
                    v.subject.type == SubjectType.anime &&
                    v.subject.displayName.toLowerCase().contains(
                      _query.text.toLowerCase(),
                    ),
              )
              .map(
                (v) => <String, dynamic>{
                  'id': v.subject.id,
                  'title': v.subject.displayName,
                  'summary': String.fromCharCodes(
                    v.subject.summary.runes.take(6000),
                  ),
                  'cover': '',
                  'coverSource': v.subject.imageUrl,
                },
              )
              .toList()
        : _results;
    return Scaffold(
      appBar: AppBar(title: const Text('添加番剧')),
      body: AsciiRefresh(
        key: _searchAnimation,
        initialRefresh: false,
        onRefresh: () async {
          if (!_local) {
            await _search();
            if (_error != null) throw StateError(_error!);
          }
        },
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                            value: false,
                            label: Text('Bangumi 搜索'),
                          ),
                          ButtonSegment(value: true, label: Text('本机收藏')),
                        ],
                        selected: {_local},
                        onSelectionChanged: _busy
                            ? null
                            : (v) => setState(() => _local = v.first),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _query,
                        onChanged: _local ? (_) => setState(() {}) : null,
                        onSubmitted: (_) => _local ? null : _requestSearch(),
                        decoration: InputDecoration(
                          hintText: _local ? '筛选本机收藏' : '番剧名称或条目 ID',
                          suffixIcon: IconButton(
                            onPressed: _busy ? null : _requestSearch,
                            icon: const Icon(Icons.search),
                          ),
                        ),
                      ),
                      if (_local)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            '只导入勾选的条目；封面自动缓存，未联网时先保存文字。',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      if (_error != null)
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                    ],
                  ),
                ),
                if (_busy) const SizedBox.shrink(),
                Expanded(
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      for (final subject in items)
                        CheckboxListTile(
                          value: _selected.containsKey(
                            '${_local ? 'local' : 'search'}:${subject['id']}',
                          ),
                          title: Text(subject['title']),
                          subtitle: Text('Bangumi #${subject['id']}'),
                          onChanged: _busy
                              ? null
                              : (checked) => setState(() {
                                  final key =
                                      '${_local ? 'local' : 'search'}:${subject['id']}';
                                  if (checked == true) {
                                    _selected[key] = subject;
                                  } else {
                                    _selected.remove(key);
                                  }
                                }),
                        ),
                    ],
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton(
                      onPressed: _busy || _selected.isEmpty
                          ? null
                          : () => _searchAnimation.currentState?.refresh(
                              task: _add,
                            ),
                      child: Text('加入番单（${_selected.length}）'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _status(Object? value) => switch (value) {
  'open' => '评分进行中',
  'waiting' => '等待开始',
  'paused' => '已暂停',
  'closed' => '已截止',
  _ => '等待开始',
};

class ParticipationReturnTile extends ConsumerWidget {
  const ParticipationReturnTile({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(participationProvider);
    if (!c.active) return const SizedBox.shrink();
    return Material(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.movie_filter_outlined),
        title: Text(c.event?['title'] ?? '番键会进行中'),
        subtitle: Text(c.online ? '返回活动 · ${c.name}' : '连接中断 · 点击返回活动'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => openRoomInvite(context, c.invite!),
      ),
    );
  }
}

class RoomParticipationPage extends ConsumerStatefulWidget {
  const RoomParticipationPage({super.key, required this.invite});
  final RoomInvite invite;
  @override
  ConsumerState<RoomParticipationPage> createState() =>
      _RoomParticipationPageState();
}

class _RoomParticipationPageState extends ConsumerState<RoomParticipationPage> {
  final _name = TextEditingController(), _comment = TextEditingController();
  Json? _preview;
  String? _error, _editorRound;
  final _commentFocus = FocusNode();
  final _loadingIndicator = GlobalKey<AsciiRefreshState>();
  bool _loading = true, _submitting = false;
  int? _score;
  Timer? _draftTimer;
  @override
  void initState() {
    super.initState();
    _name.text = ref.read(sessionProvider).user?.displayName ?? '';
  }

  /// Signed-in users enter with their Bangumi avatar on the member list.
  String? get _avatar {
    final url = ref.read(sessionProvider).user?.avatarUrl ?? '';
    return roomAvatarUri(url) == null ? null : url;
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _preview = null;
      });
    }
    try {
      final data = await ref.read(participationProvider).preview(widget.invite);
      if (mounted) setState(() => _preview = data);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    // The captured draft text still saves if this page closes during debounce.
    _name.dispose();
    _comment.dispose();
    _commentFocus.dispose();
    super.dispose();
  }

  Future<void> _action(Future<void> Function() action) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await action();
    } catch (e) {
      if (mounted) roomMessage(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _card(List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final c = ref.watch(participationProvider);
    final joined = c.active && widget.invite.sameRoom(c.invite);
    Json? r = joined ? c.current : null;
    if (r != null && _editorRound != r['id']) {
      final previous = _editorRound;
      if (previous != null) {
        _draftTimer?.cancel();
        unawaited(
          c.saveDraft(previous, text: _comment.text, score: _score).catchError((
            Object error,
          ) {
            if (context.mounted) roomMessage(context, error);
          }),
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _commentFocus.unfocus();
            roomMessage(this.context, '已切换轮次，上一轮草稿已保留');
          }
        });
      }
      _editorRound = r['id'];
      _comment.text = c.drafts[r['id']]?['text'] ?? '';
      _score = c.drafts[r['id']]?['score'] ?? r['myScore'];
    }
    final round = r;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          joined ? (c.event?['title'] ?? '番键会') : '番键会',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (joined)
            IconButton(
              tooltip: '刷新活动',
              onPressed: () => _loadingIndicator.currentState?.refresh(),
              icon: const Icon(Icons.refresh),
            ),
          if (joined)
            TextButton(
              onPressed: () => _action(() async {
                final yes = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('退出番键会？'),
                    content: const Text('已提交的评分保留，临时入口会隐藏。下次使用此设备可以恢复身份。'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('退出'),
                      ),
                    ],
                  ),
                );
                if (yes == true) {
                  await c.leave();
                  if (context.mounted) Navigator.pop(context);
                }
              }),
              child: const Text('退出活动'),
            ),
        ],
      ),
      body: AsciiRefresh(
        key: _loadingIndicator,
        onRefresh: () async {
          if (joined) {
            await c.refresh();
            if (!c.online) throw StateError(c.message ?? '连接失败');
          } else {
            await _load();
            if (_error != null) throw StateError(_error!);
          }
        },
        child: joined
            ? RoomDanmaku(
                event: c.event,
                child: ParticipantWorkspace(
                  controller: c,
                  comment: _comment,
                  focus: _commentFocus,
                  score: _score,
                  busy: _submitting,
                  keyboardVisible: MediaQuery.viewInsetsOf(context).bottom > 0,
                  onScore: (value) => setState(() {
                    _score = value;
                    unawaited(
                      c.saveDraft(round!['id'], score: value).catchError((
                        Object e,
                      ) {
                        if (context.mounted) roomMessage(context, e);
                      }),
                    );
                  }),
                  onDraft: (text) {
                    _draftTimer?.cancel();
                    final id = round!['id'] as String;
                    _draftTimer = Timer(
                      const Duration(milliseconds: 300),
                      () => unawaited(
                        c.saveDraft(id, text: text).catchError((Object e) {
                          if (context.mounted) roomMessage(context, e);
                        }),
                      ),
                    );
                  },
                  onSubmitScore: () => _action(
                    () =>
                        c.submit('score', score: _score, roundId: round!['id']),
                  ),
                  onSubmitComment: () => _action(() async {
                    final text = _comment.text.trim();
                    if (text.isEmpty) return;
                    final id = round!['id'] as String;
                    _draftTimer?.cancel();
                    await c.saveDraft(id, text: text);
                    await c.submit('comment', text: text, roundId: id);
                    if (mounted &&
                        _editorRound == id &&
                        _comment.text.trim() == text) {
                      _comment.clear();
                    }
                  }),
                ),
              )
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    children: [
                      if (!joined) ...[
                        const SizedBox(height: 28),
                        Icon(
                          Icons.movie_filter_rounded,
                          size: 56,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          _preview?['title'] ?? '加入番键会',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 12),
                        const Text('同一场鉴赏，不同的感受。'),
                        const SizedBox(height: 28),
                        if (_loading) ...[
                          const Text('正在自动寻找这场番键会…'),
                          const SizedBox(height: 8),
                          const SizedBox.shrink(),
                        ],
                        if (_error != null) ...[
                          Text(_error!),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _error = null;
                                _loading = true;
                              });
                              _loadingIndicator.currentState?.refresh();
                            },
                            child: const Text('重新连接'),
                          ),
                        ],
                        if (_preview?['ended'] == true)
                          _card([
                            const Text(
                              '这张二维码对应的活动已结束',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            const Text('请扫描主持人正在进行的活动的新二维码。启动服务不会重新开放已结束的活动。'),
                          ]),
                        TextField(
                          controller: _name,
                          maxLength: 40,
                          decoration: const InputDecoration(
                            labelText: '活动显示名',
                            helperText: '默认使用你的 Bangumi 昵称，可在入场前确认',
                          ),
                        ),
                        const SizedBox(height: 18),
                        _card([
                          const Text(
                            '有名入场，匿名评分',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '主持人会看到你的名字${_avatar == null ? '' : '、Bangumi 头像'}和是否提交。普通管理页面、导出记录不展示姓名与分数或评论的对应关系。',
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _preview != null
                                ? '已找到活动，确认昵称即可加入。'
                                : '局域网参与请先连接主持人的 Wi-Fi / 热点。',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ]),
                        FilledButton(
                          onPressed:
                              _preview == null ||
                                  (_preview?['ended'] == true &&
                                      !c.hasIdentity(widget.invite)) ||
                                  _submitting
                              ? null
                              : () => _action(() async {
                                  if (c.active && !joined) {
                                    await c.leave();
                                  }
                                  try {
                                    await c.join(
                                      widget.invite,
                                      _name.text,
                                      avatar: _avatar,
                                    );
                                  } catch (_) {
                                    // A route may change after preview; retry should discover again.
                                    if (mounted) unawaited(_load());
                                    rethrow;
                                  }
                                }),
                          child: Text(
                            _submitting
                                ? '正在加入…'
                                : _preview?['ended'] == true
                                ? (c.hasIdentity(widget.invite)
                                      ? '返回活动记录'
                                      : '活动已结束')
                                : '加入番键会 →',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
