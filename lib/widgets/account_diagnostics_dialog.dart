import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../state/account_diagnostics_provider.dart';
import '../state/session_controller.dart';
import '../state/update_controller.dart';
import '../state/website_session_controller.dart';

Future<void> showAccountDiagnostics(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const AccountDiagnosticsDialog(),
);

class AccountDiagnosticsDialog extends ConsumerStatefulWidget {
  const AccountDiagnosticsDialog({super.key});
  @override
  ConsumerState<AccountDiagnosticsDialog> createState() =>
      _AccountDiagnosticsDialogState();
}

class _AccountDiagnosticsDialogState
    extends ConsumerState<AccountDiagnosticsDialog> {
  String? _report, _message;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final update = ref.read(updateControllerProvider).snapshot;
    var version = update?.appVersion ?? '', build = update?.buildNumber ?? '';
    if (version.isEmpty) {
      try {
        final info = await PackageInfo.fromPlatform();
        version = info.version;
        build = info.buildNumber;
      } catch (_) {}
    }
    if (!mounted) return;
    final report = ref
        .read(accountDiagnosticsProvider)
        .exportJson(
          platform: Platform.operatingSystem,
          version: version,
          build: build,
          patch: update?.currentPatch,
          apiSignedIn: ref.read(sessionProvider).user != null,
          websiteState: ref.read(websiteSessionProvider).status.index,
        );
    setState(() {
      _report = report;
      _message = null;
    });
  }

  Future<void> _save() async {
    final report = _report;
    if (report == null || _saving) return;
    setState(() => _saving = true);
    try {
      final destination = await FilePicker.platform.saveFile(
        dialogTitle: '保存登录诊断',
        fileName: 'MuBangumi-diagnostics.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: Uint8List.fromList(utf8.encode(report)),
        lockParentWindow: true,
      );
      if (mounted && destination != null) setState(() => _message = '诊断记录已保存');
    } catch (_) {
      if (mounted) setState(() => _message = '保存失败，可复制记录后另存');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('登录诊断'),
    content: SizedBox(
      width: 600,
      height: MediaQuery.sizeOf(context).height * .55,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('仅保留本次运行的状态与耗时，不包含账号、凭据、私信正文或完整网页。请核对后再导出。'),
          const SizedBox(height: 12),
          if (_message != null) Text(_message!),
          Expanded(
            child: SingleChildScrollView(
              child: SelectableText(
                _report ?? '正在读取版本信息…',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving
            ? null
            : () {
                ref.read(accountDiagnosticsProvider).clear();
                _refresh();
              },
        child: const Text('清空'),
      ),
      TextButton(onPressed: _saving ? null : _refresh, child: const Text('刷新')),
      TextButton(
        onPressed: _report == null
            ? null
            : () async {
                await Clipboard.setData(ClipboardData(text: _report!));
                if (mounted) setState(() => _message = '已复制诊断记录');
              },
        child: const Text('复制'),
      ),
      FilledButton(
        onPressed: _report == null || _saving ? null : _save,
        child: const Text('保存 JSON'),
      ),
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  );
}
