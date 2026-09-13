import 'package:flutter/material.dart';

/// Exposes a stable Windows accessibility node for the complete slider.
/// Flutter 3.44 creates a portal even when its value indicator is disabled.
/// Keep that portal inside the excluded subtree: a portal attached to the
/// navigator's overlay can otherwise leave orphaned Windows AXTree nodes.
class AppSlider extends StatefulWidget {
  const AppSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.formatValue,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
  });

  final String label;
  final double value, min, max;
  final String Function(double) formatValue;
  final ValueChanged<double>? onChanged, onChangeStart, onChangeEnd;

  @override
  State<AppSlider> createState() => _AppSliderState();
}

class _AppSliderState extends State<AppSlider> {
  late final FocusNode _focus = FocusNode()..addListener(_focusChanged);

  void _focusChanged() => setState(() {});

  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    super.dispose();
  }

  void _adjust(double value) {
    widget.onChangeStart?.call(widget.value);
    widget.onChanged?.call(value);
    widget.onChangeEnd?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onChanged != null && widget.max > widget.min;
    final value = widget.value.clamp(widget.min, widget.max);
    final slider = Slider(
      focusNode: _focus,
      label: widget.label,
      showValueIndicator: ShowValueIndicator.never,
      value: value,
      min: widget.min,
      max: widget.max,
      semanticFormatterCallback: widget.formatValue,
      onChanged: widget.onChanged,
      onChangeStart: widget.onChangeStart,
      onChangeEnd: widget.onChangeEnd,
    );
    if (Theme.of(context).platform != TargetPlatform.windows) {
      return Semantics(label: widget.label, child: slider);
    }

    final step = (widget.max - widget.min) / 20;
    final increased = (value + step).clamp(widget.min, widget.max);
    final decreased = (value - step).clamp(widget.min, widget.max);
    return Semantics(
      container: true,
      slider: true,
      label: widget.label,
      value: widget.formatValue(value),
      increasedValue: enabled ? widget.formatValue(increased) : null,
      decreasedValue: enabled ? widget.formatValue(decreased) : null,
      enabled: enabled,
      focusable: enabled,
      focused: enabled ? _focus.hasFocus : null,
      onFocus: enabled ? _focus.requestFocus : null,
      onIncrease: enabled ? () => _adjust(increased) : null,
      onDecrease: enabled ? () => _adjust(decreased) : null,
      child: ExcludeSemantics(
        child: Overlay.wrap(alwaysSizeToContent: true, child: slider),
      ),
    );
  }
}
