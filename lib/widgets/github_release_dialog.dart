import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import '../core/external_link.dart';
import '../core/update/github_release.dart';
import '../core/update/update_download.dart';
import '../state/update_controller.dart';

enum GithubReleaseDialogResult { skip, later, download }

Future<GithubReleaseDialogResult?> showGithubReleaseDialog(
  BuildContext context, {
  required String currentVersion,
  required String currentBuild,
  required GithubRelease release,
}) => showDialog<GithubReleaseDialogResult>(
  context: context,
  builder: (_) => GithubReleaseDialog(
    currentVersion: currentVersion,
    currentBuild: currentBuild,
    release: release,
  ),
);

class GithubReleaseDialog extends ConsumerStatefulWidget {
  const GithubReleaseDialog({
    super.key,
    required this.currentVersion,
    required this.currentBuild,
    required this.release,
  });
  final String currentVersion, currentBuild;
  final GithubRelease release;
  @override
  ConsumerState<GithubReleaseDialog> createState() =>
      _GithubReleaseDialogState();
}

class _GithubReleaseDialogState extends ConsumerState<GithubReleaseDialog> {
  GithubReleaseAsset? _asset;
  bool _loading = true, _opening = false, _permissionNeeded = false;
  String? _message;
  late String _build;
  @override
  void initState() {
    super.initState();
    _build = widget.currentBuild;
    unawaited(_load());
  }

  Future<void> _load() async {
    final asset = await deviceReleaseAsset(widget.release);
    final build = await logicalUpdateBuild(widget.currentBuild);
    if (mounted) {
      setState(() {
        _asset = asset;
        _build = build;
        _loading = false;
      });
    }
  }

  Future<void> _postpone() async {
    final ok = await ref
        .read(updateControllerProvider.notifier)
        .postponeGithubRelease(widget.release);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, GithubReleaseDialogResult.later);
    } else {
      setState(() => _message = '提醒设置未保存，请重试');
    }
  }

  Future<void> _skip() async {
    try {
      await ref
          .read(updateControllerProvider.notifier)
          .skipGithubRelease(widget.release);
      if (mounted) Navigator.pop(context, GithubReleaseDialogResult.skip);
    } catch (_) {
      if (mounted) setState(() => _message = '跳过设置未保存，请重试');
    }
  }

  Future<void> _open(UpdateDownload download) async {
    setState(() => _opening = true);
    final ok = await download.open(version: widget.release.version);
    if (mounted) {
      setState(() {
        _opening = false;
        _permissionNeeded = !ok && download.error == null && Platform.isAndroid;
      });
    }
  }

  Future<void> _launch(String? url) async {
    try {
      if (await launchExternalLink(Uri.tryParse(url ?? ''))) return;
    } catch (_) {
      // Report platform/browser failures inside the panel, preserving its state.
    }
    if (mounted) setState(() => _message = '无法打开链接，请重试');
  }

  @override
  Widget build(BuildContext context) {
    final release = widget.release;
    final notes = release.body?.trim() ?? '';
    final highlights = notes
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.startsWith('- ') || s.startsWith('* '))
        .take(3)
        .toList();
    final download = ref.watch(updateDownloadProvider);
    return AnimatedBuilder(
      animation: download,
      builder: (context, _) {
        final matches =
            _asset != null && download.asset?.sha256Hex == _asset!.sha256Hex;
        final ready = matches && download.phase == UpdateDownloadPhase.ready;
        final busy = download.busy;
        return AlertDialog(
          title: const Text('发现新版本'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${widget.currentVersion}+$_build → ${release.version}${release.effectiveBuildNumber == null ? "" : "+${release.effectiveBuildNumber}"}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  if (highlights.isNotEmpty)
                    MarkdownBody(data: highlights.join('\n'))
                  else
                    const Text('新版已发布，查看更新说明了解变化。'),
                  if (notes.isNotEmpty)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('完整更新说明'),
                      children: [
                        MarkdownBody(
                          data: notes,
                          onTapLink: (_, href, _) => unawaited(_launch(href)),
                        ),
                      ],
                    ),
                  if (_loading)
                    const Text('正在匹配安装包…')
                  else if (_asset != null)
                    Text(
                      '安装包 ${(_asset!.size / 1000000).toStringAsFixed(1)} MB',
                    ),
                  if (busy) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value:
                          matches &&
                              download.phase == UpdateDownloadPhase.downloading
                          ? download.progress
                          : null,
                    ),
                    Text(
                      matches
                          ? download.phase == UpdateDownloadPhase.verifying
                                ? '正在校验安装包…'
                                : '已下载 ${(download.received / 1000000).toStringAsFixed(1)} MB'
                          : '另一个版本正在下载',
                    ),
                    const Text('关闭面板后下载继续，可从“我的 → 检查更新”返回。'),
                    TextButton(
                      onPressed: download.cancel,
                      child: const Text('取消下载'),
                    ),
                  ],
                  if (ready && Platform.isWindows)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('这是便携包。请解压到新目录后打开；保留旧目录，确认个人数据正常后再整理。'),
                    ),
                  if (_permissionNeeded)
                    const Text('允许 MuBangumi 安装应用后，返回此处再次点击“安装更新”。'),
                  if (_message != null) Text(_message!),
                  if (matches && download.error != null) Text(download.error!),
                  const SizedBox(height: 12),
                  if (_asset != null)
                    FilledButton.icon(
                      onPressed: busy || _opening
                          ? null
                          : ready
                          ? () => _open(download)
                          : () {
                              download.release = release;
                              unawaited(download.start(_asset!));
                            },
                      icon: Icon(
                        ready
                            ? Icons.install_desktop_rounded
                            : Icons.download_rounded,
                      ),
                      label: Text(
                        _opening
                            ? '正在打开…'
                            : ready
                            ? Platform.isWindows
                                  ? '打开下载位置'
                                  : '安装更新'
                            : matches &&
                                  download.phase == UpdateDownloadPhase.error
                            ? '重新下载'
                            : '下载更新',
                      ),
                    ),
                  TextButton.icon(
                    onPressed: () => _launch(release.htmlUrl),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('前往发布页'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: _skip, child: const Text('跳过此版本')),
            TextButton(onPressed: _postpone, child: const Text('明天提醒')),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }
}
