import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/background_controller.dart';
import '../widgets/subject_widgets.dart';

Future<void> showBackgroundSettingsSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) => const _BackgroundSettingsSheet(),
  );
}

class _BackgroundSettingsSheet extends ConsumerWidget {
  const _BackgroundSettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(backgroundSettingsProvider);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '背景与毛玻璃',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              '自选壁纸，再叠一层有层次的磨砂玻璃，卡片与导航会半透明浮在上面。',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (settings.hasImage)
                      Image.file(
                        File(settings.imagePath!),
                        fit: BoxFit.cover,
                        cacheWidth: 1200,
                        errorBuilder: (_, _, _) =>
                            ColoredBox(color: scheme.surfaceContainerHighest),
                      )
                    else
                      ColoredBox(
                        color: scheme.surfaceContainerHighest,
                        child: Center(
                          child: Text(
                            '尚未选择图片',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ),
                    if (settings.hasImage)
                      ColoredBox(
                        color: Colors.black.withValues(alpha: settings.dim),
                      ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        margin: const EdgeInsets.all(12),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surface.withValues(
                            alpha: settings.glass,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: scheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                        child: const Text(
                          '毛玻璃预览卡片',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('启用自定义背景'),
              subtitle: Text(settings.hasImage ? '壁纸 + 分层毛玻璃' : '请先选择一张图片'),
              value: settings.isActive,
              onChanged: settings.hasImage
                  ? (value) => ref
                        .read(backgroundSettingsProvider.notifier)
                        .setEnabled(value)
                  : null,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () async {
                      try {
                        final path = await ref
                            .read(backgroundSettingsProvider.notifier)
                            .pickAndSetImage();
                        if (path != null && context.mounted) {
                          showAppMessage(context, '背景已更新');
                        }
                      } catch (error) {
                        if (context.mounted) {
                          showAppMessage(
                            context,
                            '选择图片失败：${error.toString().replaceFirst(RegExp(r'^.*Exception:\s*'), '')}',
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(settings.hasImage ? '更换图片' : '选择图片'),
                  ),
                ),
                if (settings.hasImage) ...[
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await ref
                          .read(backgroundSettingsProvider.notifier)
                          .clearImage();
                      if (context.mounted) {
                        showAppMessage(context, '已清除背景');
                      }
                    },
                    icon: const Icon(Icons.hide_image_outlined),
                    label: const Text('清除'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 18),
            _SliderTile(
              icon: Icons.blur_on_rounded,
              label: '毛玻璃强度',
              valueLabel: settings.blur.toStringAsFixed(0),
              value: settings.blur,
              min: 0,
              max: 40,
              onChanged: (value) =>
                  ref.read(backgroundSettingsProvider.notifier).setBlur(value),
            ),
            _SliderTile(
              icon: Icons.contrast_rounded,
              label: '压暗程度',
              valueLabel: '${(settings.dim * 100).round()}%',
              value: settings.dim,
              min: 0,
              max: 0.75,
              onChanged: (value) =>
                  ref.read(backgroundSettingsProvider.notifier).setDim(value),
            ),
            _SliderTile(
              icon: Icons.layers_outlined,
              label: '玻璃不透明度',
              valueLabel: '${(settings.glass * 100).round()}%',
              value: settings.glass,
              min: 0.15,
              max: 0.8,
              onChanged: (value) =>
                  ref.read(backgroundSettingsProvider.notifier).setGlass(value),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.icon,
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(label)),
            Text(
              valueLabel,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
