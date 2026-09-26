import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'room_storage.dart';

final roomWifiVaultProvider = Provider<RoomSecretVault>(
  (_) => const PlatformRoomSecretVault(),
);

const _wifiKey = 'banjian_wifi_share_v1';

/// The host's own network. Apps cannot read system Wi-Fi or hotspot
/// passwords, so the host enters them once and they stay in the device vault.
class RoomWifiNetwork {
  const RoomWifiNetwork(this.ssid, this.password);
  final String ssid, password;

  /// Standard `WIFI:` payload joined directly by the iOS and Android cameras.
  String get payload {
    String escape(String v) =>
        v.replaceAllMapped(RegExp(r'[\\;,:"]'), (m) => '\\${m[0]}');
    return password.isEmpty
        ? 'WIFI:T:nopass;S:${escape(ssid)};;'
        : 'WIFI:T:WPA;S:${escape(ssid)};P:${escape(password)};;';
  }

  static Future<RoomWifiNetwork?> load(RoomSecretVault vault) async {
    try {
      final raw = await vault.read(_wifiKey);
      if (raw == null) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final ssid = json['ssid'] as String? ?? '';
      if (ssid.isEmpty) return null;
      return RoomWifiNetwork(ssid, json['password'] as String? ?? '');
    } catch (_) {
      return null;
    }
  }

  Future<void> save(RoomSecretVault vault) =>
      vault.write(_wifiKey, jsonEncode({'ssid': ssid, 'password': password}));

  static Future<void> clear(RoomSecretVault vault) => vault.delete(_wifiKey);
}

/// Step ① of a LAN invitation: bring the guest onto the host's network.
class RoomWifiJoinCard extends ConsumerStatefulWidget {
  const RoomWifiJoinCard({super.key, this.qrSize = 230});
  final double qrSize;
  @override
  ConsumerState<RoomWifiJoinCard> createState() => _RoomWifiJoinCardState();
}

class _RoomWifiJoinCardState extends ConsumerState<RoomWifiJoinCard> {
  RoomWifiNetwork? _network;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    RoomWifiNetwork.load(ref.read(roomWifiVaultProvider)).then((v) {
      if (!mounted) return;
      setState(() {
        _network = v;
        _loading = false;
      });
    });
  }

  Future<void> _edit() async {
    final result = await showDialog<({RoomWifiNetwork? network})>(
      context: context,
      builder: (_) => _RoomWifiDialog(initial: _network),
    );
    if (result == null || !mounted) return;
    final vault = ref.read(roomWifiVaultProvider);
    try {
      if (result.network == null) {
        await RoomWifiNetwork.clear(vault);
      } else {
        await result.network!.save(vault);
      }
    } catch (_) {
      // The QR code still works for this session when the vault is unavailable.
    }
    if (mounted) setState(() => _network = result.network);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final network = _network;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('① 扫码连接 Wi-Fi', style: theme.textTheme.titleSmall),
        const SizedBox(height: 12),
        if (_loading)
          SizedBox.square(
            dimension: widget.qrSize,
            child: const Center(child: CircularProgressIndicator()),
          )
        else if (network == null)
          SizedBox(
            width: widget.qrSize + 24,
            child: Column(
              children: [
                OutlinedButton.icon(
                  onPressed: _edit,
                  icon: const Icon(Icons.wifi),
                  label: const Text('添加 Wi-Fi 二维码'),
                ),
                const SizedBox(height: 8),
                Text(
                  '填写这台设备连接的 Wi-Fi 或已开启的热点。密码只保存在本机安全存储。',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else ...[
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: QrImageView(
              key: ValueKey(network.payload),
              data: network.payload,
              size: widget.qrSize,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi, size: 16),
              const SizedBox(width: 4),
              Flexible(
                child: Text(network.ssid, overflow: TextOverflow.ellipsis),
              ),
              TextButton(onPressed: _edit, child: const Text('修改')),
            ],
          ),
        ],
      ],
    );
  }
}

class _RoomWifiDialog extends StatefulWidget {
  const _RoomWifiDialog({this.initial});
  final RoomWifiNetwork? initial;
  @override
  State<_RoomWifiDialog> createState() => _RoomWifiDialogState();
}

class _RoomWifiDialogState extends State<_RoomWifiDialog> {
  late final _ssid = TextEditingController(text: widget.initial?.ssid);
  late final _password = TextEditingController(text: widget.initial?.password);
  bool _hidden = true, _tried = false;

  @override
  void dispose() {
    _ssid.dispose();
    _password.dispose();
    super.dispose();
  }

  String? get _ssidError =>
      _ssid.text.trim().isEmpty ? '请填写 Wi-Fi / 热点名称' : null;
  String? get _passwordError =>
      _password.text.isNotEmpty && _password.text.length < 8
      ? 'WPA 密码至少 8 位；开放网络请留空'
      : null;

  void _save() {
    setState(() => _tried = true);
    if (_ssidError != null || _passwordError != null) return;
    Navigator.pop(context, (
      network: RoomWifiNetwork(_ssid.text.trim(), _password.text),
    ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Wi-Fi 二维码'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _ssid,
          autofocus: widget.initial == null,
          maxLength: 32,
          decoration: InputDecoration(
            labelText: '名称',
            errorText: _tried ? _ssidError : null,
          ),
          onChanged: (_) => setState(() {}),
        ),
        TextField(
          controller: _password,
          obscureText: _hidden,
          maxLength: 63,
          decoration: InputDecoration(
            labelText: '密码',
            errorText: _tried ? _passwordError : null,
            suffixIcon: IconButton(
              onPressed: () => setState(() => _hidden = !_hidden),
              icon: Icon(_hidden ? Icons.visibility : Icons.visibility_off),
              tooltip: _hidden ? '显示密码' : '隐藏密码',
            ),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _save(),
        ),
      ],
    ),
    actions: [
      if (widget.initial != null)
        TextButton(
          onPressed: () => Navigator.pop(context, (network: null)),
          child: const Text('清除'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _save, child: const Text('保存')),
    ],
  );
}
