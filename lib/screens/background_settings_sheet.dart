import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/background_controller.dart';
import '../core/diagnostics/background_diagnostics.dart';
import '../state/system_appearance_controller.dart';
import '../widgets/app_background.dart';
import '../widgets/app_slider.dart';
import '../widgets/subject_widgets.dart';
import '../core/theme/app_tokens.dart';

Future<void> showBackgroundSettingsSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  BackgroundDiagnostics.record('sheet_open');
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) => const _BackgroundSettingsSheet(),
  );
  if (context.mounted) {
    BackgroundDiagnostics.record('sheet_close');
    await ref.read(backgroundSettingsProvider.notifier).flush();
  }
}

class _BackgroundSettingsSheet extends ConsumerWidget {
  const _BackgroundSettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(backgroundSettingsProvider);
    final effective = ref.watch(effectiveBackgroundProvider);
    final system = ref.watch(systemAppearanceProvider);
    final controller = ref.read(backgroundSettingsProvider.notifier);
    final theme = Theme.of(context);
    final highContrast =
        MediaQuery.highContrastOf(context) || system.highContrast;
    final blocked =
        highContrast || system.reduceEffects || settings.reduceTransparency;
    final editable = settings.ready && !settings.busy;
    final active = editable && effective.isActive && !highContrast;
    final String? reason = highContrast
        ? '高对比度已开启，当前使用纯色界面。'
        : !system.transparency
        ? '系统已关闭透明效果，当前使用纯色界面。'
        : system.batterySaver
        ? '省电模式已开启，当前使用纯色界面。'
        : settings.reduceTransparency
        ? '已减少透明效果，背景设置仍会保留。'
        : null;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              BackgroundDiagnostics.enabled
                  ? '背景与毛玻璃 · 诊断版 ${BackgroundDiagnostics.buildLabel}'
                  : '背景与毛玻璃',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              '壁纸融入背景，导航轻透；文字、输入框和弹窗保持清晰。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            ExcludeSemantics(
              child: BackgroundSettingsPreview(
                settings: blocked
                    ? settings.copyWith(enabled: false)
                    : settings,
              ),
            ),
            if (reason != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(reason),
              ),
            if (settings.saveError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      settings.saveError!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    TextButton(
                      onPressed: editable ? controller.flush : null,
                      child: const Text('重试保存'),
                    ),
                  ],
                ),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('启用自定义背景'),
              subtitle: settings.hasImage ? null : const Text('请先选择一张图片'),
              value: settings.enabled && settings.hasImage,
              onChanged: editable && settings.hasImage
                  ? controller.setEnabled
                  : null,
            ),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: !editable
                        ? null
                        : () async {
                            try {
                              final path = await controller.pickAndSetImage();
                              if (path != null &&
                                  context.mounted &&
                                  ref
                                          .read(backgroundSettingsProvider)
                                          .saveError ==
                                      null) {
                                showAppMessage(context, '背景已更新');
                              }
                            } catch (_) {
                              if (context.mounted) {
                                showAppMessage(
                                  context,
                                  '无法读取这张图片，请选择 32 MB 以内的有效图片后重试',
                                );
                              }
                            }
                          },
                    icon: settings.busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.photo_library_outlined),
                    label: Text(
                      settings.busy
                          ? '正在处理图片…'
                          : settings.hasImage
                          ? '更换图片'
                          : '选择图片',
                    ),
                  ),
                ),
                if (settings.hasImage) ...[
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: editable ? controller.clearImage : null,
                    icon: const Icon(Icons.hide_image_outlined),
                    label: const Text('清除'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            Text('推荐样式', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in BackgroundPreset.values)
                  ChoiceChip(
                    label: Text(switch (preset) {
                      BackgroundPreset.plain => '默认纯色',
                      BackgroundPreset.soft => '柔和背景',
                      BackgroundPreset.frosted => '轻度毛玻璃',
                    }),
                    selected: preset == BackgroundPreset.plain
                        ? !settings.enabled
                        : settings.enabled &&
                              (preset == BackgroundPreset.soft
                                  ? settings.blur == 10 &&
                                        settings.dim == .5 &&
                                        settings.glass == .7
                                  : settings.blur == 22 &&
                                        settings.dim == .32 &&
                                        settings.glass == .42),
                    onSelected:
                        editable &&
                            (preset == BackgroundPreset.plain ||
                                (settings.hasImage && !blocked))
                        ? (_) => controller.applyPreset(preset)
                        : null,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('高级调整'),
              subtitle: const Text('拖动时预览，松手后应用并保存'),
              children: [
                _SliderTile(
                  label: '背景模糊',
                  formatValue: (value) => value.toStringAsFixed(0),
                  value: settings.blur,
                  min: 0,
                  max: 40,
                  onChanged: active ? controller.setBlur : null,
                  onChangeStart: (_) => controller.beginAdjustments(),
                  onChangeEnd: (_) => unawaited(controller.flush()),
                ),
                _SliderTile(
                  label: '背景柔化',
                  formatValue: (value) => '${(value / .75 * 100).round()}%',
                  value: settings.dim,
                  min: 0,
                  max: .75,
                  onChanged: active ? controller.setDim : null,
                  onChangeStart: (_) => controller.beginAdjustments(),
                  onChangeEnd: (_) => unawaited(controller.flush()),
                ),
                Text(
                  '浅色主题提亮，深色主题压暗，始终保护文字可读性。',
                  style: theme.textTheme.bodySmall,
                ),
                _SliderTile(
                  label: '导航不透明度',
                  formatValue: (value) =>
                      '${(AppBackgroundSettings(glass: value).panelOpacity * 100).round()}%',
                  value: settings.glass,
                  min: .15,
                  max: .8,
                  onChanged: active ? controller.setGlass : null,
                  onChangeStart: (_) => controller.beginAdjustments(),
                  onChangeEnd: (_) => unawaited(controller.flush()),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: active ? controller.resetAdjustments : null,
                    icon: const Icon(Icons.restore_rounded),
                    label: const Text('恢复推荐参数'),
                  ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('减少透明效果'),
              subtitle: const Text('使用纯色界面，保留已选择的壁纸和参数'),
              value: settings.reduceTransparency,
              onChanged: editable ? controller.setReduceTransparency : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// Uses exactly the same wallpaper, veil and navigation opacity as the app.
class BackgroundSettingsPreview extends StatelessWidget {
  const BackgroundSettingsPreview({super.key, required this.settings});
  final AppBackgroundSettings settings;
  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final themed = applyBackgroundTheme(base, settings);
    return ClipRRect(
      borderRadius: AppRadius.medium,
      child: SizedBox(
        height: 196,
        child: Theme(
          data: themed,
          child: BackgroundWallpaper(
            settings: settings,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  color: settings.isActive
                      ? base.colorScheme.surface.withValues(
                          alpha: settings.panelOpacity,
                        )
                      : base.colorScheme.surface,
                  child: const Text('导航区域'),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          settings.isActive
                              ? '背景效果预览'
                              : settings.hasImage
                              ? '当前使用纯色界面'
                              : '尚未选择图片',
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '内容清晰，阅读不受壁纸干扰',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: base.textTheme.bodyMedium,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
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

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.label,
    required this.formatValue,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.onChangeStart,
    required this.onChangeEnd,
  });
  final String label;
  final String Function(double) formatValue;
  final double value, min, max;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double> onChangeStart;
  final ValueChanged<double> onChangeEnd;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ExcludeSemantics(
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(formatValue(value)),
          ],
        ),
      ),
      AppSlider(
        label: label,
        value: value.clamp(min, max),
        min: min,
        max: max,
        formatValue: formatValue,
        onChanged: onChanged,
        onChangeStart: onChanged == null ? null : onChangeStart,
        onChangeEnd: onChanged == null ? null : onChangeEnd,
      ),
    ],
  );
}
