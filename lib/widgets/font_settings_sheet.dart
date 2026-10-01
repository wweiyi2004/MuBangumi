import '../core/theme/anime_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../models/app_font.dart';
import '../state/font_controller.dart';

Future<void> showFontSettings(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const FontSettingsSheet(),
    );

class FontSettingsSheet extends ConsumerWidget {
  const FontSettingsSheet({super.key});
  static final _registeredLicenses = <String>{};
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(fontProvider);
    final controller = ref.read(fontProvider.notifier);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('字体', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('默认沿用系统字体。其他字体仅在点击下载时获取，下载后可离线使用。'),
            OutlinedButton.icon(
              onPressed: state.downloading != null
                  ? null
                  : () async {
                      try {
                        final result = await FilePicker.platform.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: ['ttf', 'otf', 'ttc'],
                        );
                        if (result == null || !context.mounted) return;
                        final file = result.files.single;
                        if (file.size > 64 * 1024 * 1024) {
                          throw const FormatException('字库不能超过 64 MB');
                        }
                        final bytes =
                            file.bytes ??
                            (file.path == null
                                ? Uint8List(0)
                                : await File(file.path!).readAsBytes());
                        if (!context.mounted) return;
                        await controller.importFont(
                          file.name.replaceFirst(
                            RegExp(r'\.(ttf|otf|ttc)$', caseSensitive: false),
                            '',
                          ),
                          bytes,
                        );
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('字体导入失败：$error')),
                          );
                        }
                      }
                    },
              icon: const AnimeIcon(Icons.file_upload_outlined),
              label: const Text('导入本地字库 · TTF / OTF / TTC'),
            ),
            ListTile(
              leading: AnimeIcon(
                state.selected == null
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: const Text('默认字体'),
              subtitle: const Text('保持当前系统字体'),
              onTap: () => controller.choose(null),
            ),
            for (final font in [...downloadableFonts, ...state.imported])
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              font.name,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          if (state.selected?.id == font.id) const Text('使用中'),
                        ],
                      ),
                      Text(
                        '${font.description} · ${(font.bytes / 1024 / 1024).toStringAsFixed(1)} MB${font.imported ? '' : ' · SIL OFL'}',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '喜欢的故事，值得好好记录。\nMuBangumi · 0123456789',
                        style: TextStyle(
                          fontFamily: state.installed.contains(font.id)
                              ? font.family
                              : null,
                        ),
                      ),
                      if (state.downloading == font.id) ...[
                        const SizedBox(height: 8),
                        LinearProgressIndicator(value: state.progress),
                      ],
                      Wrap(
                        spacing: 8,
                        children: [
                          if (state.downloading == font.id)
                            TextButton(
                              onPressed: controller.cancelDownload,
                              child: Text(
                                '取消下载 ${(state.progress * 100).round()}%',
                              ),
                            )
                          else
                            FilledButton.tonal(
                              onPressed:
                                  state.downloading != null ||
                                      (font.imported &&
                                          !state.installed.contains(font.id))
                                  ? null
                                  : () => state.installed.contains(font.id)
                                        ? controller.choose(font)
                                        : controller.download(font),
                              child: Text(
                                state.installed.contains(font.id)
                                    ? '使用字体'
                                    : font.imported
                                    ? '字库缺失，请重新导入'
                                    : '下载并使用',
                              ),
                            ),
                          if (state.installed.contains(font.id) ||
                              font.imported)
                            TextButton(
                              onPressed: state.downloading != null
                                  ? null
                                  : () => controller.remove(font),
                              child: Text(font.imported ? '移除字库' : '移除下载'),
                            ),
                          if (!font.imported)
                            TextButton(
                              onPressed: () async {
                                final text = await rootBundle.loadString(
                                  font.licenseAsset,
                                );
                                if (!context.mounted) return;
                                if (_registeredLicenses.add(font.id)) {
                                  LicenseRegistry.addLicense(() async* {
                                    yield LicenseEntryWithLineBreaks([
                                      font.name,
                                    ], text);
                                  });
                                }
                                showLicensePage(
                                  context: context,
                                  applicationName: font.name,
                                );
                              },
                              child: const Text('字体许可'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (state.error != null)
              Text(
                state.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    );
  }
}
