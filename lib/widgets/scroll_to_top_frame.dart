import 'package:flutter/material.dart';
import '../core/theme/anime_icon.dart';

class ScrollToTopFrame extends StatefulWidget {
  const ScrollToTopFrame({
    super.key,
    required this.controller,
    required this.child,
  });
  final ScrollController controller;
  final Widget child;
  @override
  State<ScrollToTopFrame> createState() => _ScrollToTopFrameState();
}

class _ScrollToTopFrameState extends State<ScrollToTopFrame> {
  bool _show = false;
  bool _returning = false;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_update);
  }

  @override
  void didUpdateWidget(covariant ScrollToTopFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_update);
      widget.controller.addListener(_update);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_update);
    super.dispose();
  }

  void _update() {
    final show = widget.controller.hasClients && widget.controller.offset > 240;
    if (show != _show && mounted) setState(() => _show = show);
  }

  Future<void> _toTop() async {
    if (_returning || !widget.controller.hasClients) return;
    setState(() => _returning = true);
    try {
      await widget.controller.animateTo(
        0,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    } finally {
      if (mounted) setState(() => _returning = false);
    }
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      widget.child,
      Positioned(
        right: 16,
        bottom: 24,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: _show
              ? SizedBox.square(
                  dimension: 48,
                  child: FloatingActionButton.small(
                    heroTag: null,
                    tooltip: '回到顶部',
                    elevation: 0,
                    shape: const CircleBorder(),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    onPressed: _returning ? null : _toTop,
                    child: const AnimeIcon(
                      Icons.arrow_upward_rounded,
                      size: 22,
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ),
    ],
  );
}
