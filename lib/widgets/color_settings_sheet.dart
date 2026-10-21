import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/custom_colors.dart';
import '../core/theme/app_theme.dart';
import '../state/custom_colors_controller.dart';

Future<void> showColorSettings(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const ColorSettingsSheet(),
    );

class ColorSettingsSheet extends ConsumerStatefulWidget {
  const ColorSettingsSheet({super.key});
  @override
  ConsumerState<ColorSettingsSheet> createState() => _ColorSettingsState();
}

class _ColorSettingsState extends ConsumerState<ColorSettingsSheet> {
  late CustomColors _draft =
      ref.read(customColorsProvider) ?? const CustomColors();
  bool _dark = false, _busy = false;
  String? _error;
  Future<void> _save(CustomColors? colors) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(customColorsProvider.notifier).choose(colors);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _error = '配色保存失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final derivedPreview = applyCustomColors(
      _dark ? AppTheme.dark : AppTheme.light,
      _draft,
    );
    final family = Theme.of(context).textTheme.bodyMedium?.fontFamily;
    final preview = derivedPreview.copyWith(
      textTheme: derivedPreview.textTheme.apply(fontFamily: family),
      filledButtonTheme: FilledButtonThemeData(
        style: derivedPreview.filledButtonTheme.style?.copyWith(
          textStyle: WidgetStatePropertyAll(
            derivedPreview.textTheme.labelLarge?.copyWith(fontFamily: family),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: derivedPreview.textTheme.labelLarge?.copyWith(
            fontFamily: family,
          ),
        ),
      ),
    );
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .85,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text('自定义配色', style: Theme.of(context).textTheme.titleLarge),
            const Text('选择颜色或输入十六进制色值，预览满意后再应用。'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('预览深色模式'),
              value: _dark,
              onChanged: (v) => setState(() => _dark = v),
            ),
            Theme(
              data: preview,
              child: Builder(
                builder: (context) => Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: preview.scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('喜欢的故事，慢慢记录', style: preview.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            '收藏 · 看过 12 / 24 话',
                            style: preview.textTheme.bodyMedium,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          FilledButton(
                            onPressed: () {},
                            child: const Text('看完下一集'),
                          ),
                          TextButton(
                            onPressed: () {},
                            child: const Text('查看条目'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _field(
              '主色',
              _draft.primary,
              (v) => CustomColors(
                primary: v,
                secondary: _draft.secondary,
                lightCanvas: _draft.lightCanvas,
                darkCanvas: _draft.darkCanvas,
              ),
            ),
            _field(
              '辅助色',
              _draft.secondary,
              (v) => CustomColors(
                primary: _draft.primary,
                secondary: v,
                lightCanvas: _draft.lightCanvas,
                darkCanvas: _draft.darkCanvas,
              ),
            ),
            _field(
              '浅色背景',
              _draft.lightCanvas,
              (v) => CustomColors(
                primary: _draft.primary,
                secondary: _draft.secondary,
                lightCanvas: v,
                darkCanvas: _draft.darkCanvas,
              ),
            ),
            _field(
              '深色背景',
              _draft.darkCanvas,
              (v) => CustomColors(
                primary: _draft.primary,
                secondary: _draft.secondary,
                lightCanvas: _draft.lightCanvas,
                darkCanvas: v,
              ),
            ),
            if (_error != null) Text(_error!),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: _busy ? null : () => _save(_draft),
                  child: const Text('应用配色'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _save(null),
                  child: const Text('恢复默认班娘粉'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    String label,
    Color color,
    CustomColors Function(Color) change,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 8),
      TextFormField(
        key: ValueKey('$label:${color.toARGB32()}'),
        initialValue: color
            .toARGB32()
            .toRadixString(16)
            .substring(2)
            .toUpperCase(),
        maxLength: 6,
        decoration: InputDecoration(
          labelText: label,
          prefixText: '#',
          counterText: '',
          suffixIcon: Padding(
            padding: const EdgeInsets.all(12),
            child: CircleAvatar(backgroundColor: color, radius: 10),
          ),
        ),
        onChanged: (v) {
          if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(v)) {
            setState(
              () =>
                  _draft = change(Color(0xFF000000 | int.parse(v, radix: 16))),
            );
          }
        },
      ),
      Wrap(
        spacing: 8,
        children: [
          for (final c in [
            const Color(0xFFF09199),
            const Color(0xFF9386C8),
            const Color(0xFF4F9F97),
            const Color(0xFF648FC0),
            const Color(0xFFE5AC5B),
            Colors.white,
            const Color(0xFF101014),
          ])
            IconButton(
              tooltip: '#${c.toARGB32().toRadixString(16).substring(2)}',
              onPressed: () => setState(() => _draft = change(c)),
              icon: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
            ),
        ],
      ),
    ],
  );
}
