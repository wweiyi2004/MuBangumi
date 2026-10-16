import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../core/theme/anime_icon.dart';

/// Data-space viewport shared by history and comparison plots. Axes are
/// redrawn at their new scale rather than magnified as bitmap labels.
class ChartViewport extends StatefulWidget {
  const ChartViewport({
    super.key,
    required this.builder,
    this.resetKey,
    this.enabled = true,
    this.height = 260,
    this.plotInsets = const EdgeInsets.fromLTRB(40, 12, 12, 12),
  });
  final Widget Function(BuildContext, Rect) builder;
  final Object? resetKey;
  final bool enabled;
  final double height;
  final EdgeInsets plotInsets;
  @override
  State<ChartViewport> createState() => _ChartViewportState();
}

class _ChartViewportState extends State<ChartViewport> {
  static const full = Rect.fromLTWH(0, 0, 1, 1);
  Rect _rect = full, _start = full;
  Offset _anchor = Offset.zero;
  @override
  void didUpdateWidget(covariant ChartViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetKey != widget.resetKey) _rect = full;
  }

  Rect _zoom(Rect source, double factor, Offset anchor, Offset current) {
    final width = (source.width / factor).clamp(1 / 64, 1.0);
    final height = (source.height / factor).clamp(1 / 64, 1.0);
    return Rect.fromLTWH(
      (source.left + anchor.dx * source.width - current.dx * width).clamp(
        0,
        1 - width,
      ),
      (source.top + anchor.dy * source.height - current.dy * height).clamp(
        0,
        1 - height,
      ),
      width,
      height,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.builder(context, full);
    return LayoutBuilder(
      builder: (context, constraints) {
        // The plot has a fixed height even inside vertically unbounded lists.
        Offset normalize(Offset at) => Offset(
          ((at.dx - widget.plotInsets.left) /
                  math.max(
                    1,
                    constraints.maxWidth - widget.plotInsets.horizontal,
                  ))
              .clamp(0, 1),
          ((at.dy - widget.plotInsets.top) /
                  math.max(1, widget.height - widget.plotInsets.vertical))
              .clamp(0, 1),
        );
        return Stack(
          children: [
            Listener(
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) {
                  GestureBinding.instance.pointerSignalResolver.register(
                    event,
                    (signal) {
                      if (!mounted) return;
                      final anchor = normalize(event.localPosition);
                      setState(
                        () => _rect = _zoom(
                          _rect,
                          math.exp(-event.scrollDelta.dy * .003),
                          anchor,
                          anchor,
                        ),
                      );
                    },
                  );
                }
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: (details) {
                  _start = _rect;
                  _anchor = normalize(details.localFocalPoint);
                },
                onScaleUpdate: (details) => setState(
                  () => _rect = _zoom(
                    _start,
                    details.scale,
                    _anchor,
                    normalize(details.localFocalPoint),
                  ),
                ),
                child: widget.builder(context, _rect),
              ),
            ),
            if (_rect != full)
              Positioned(
                top: 0,
                right: 0,
                child: IconButton.filledTonal(
                  tooltip: '重置图表视图',
                  onPressed: () => setState(() => _rect = full),
                  icon: const AnimeIcon(Icons.fit_screen_rounded, size: 18),
                ),
              ),
          ],
        );
      },
    );
  }
}
