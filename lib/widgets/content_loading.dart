import 'dart:async';
import 'package:flutter/material.dart';
import '../core/theme/app_tokens.dart';

/// Static placeholders: no shimmer ticker and no network images.
class ContentSkeleton extends StatelessWidget {
  const ContentSkeleton({super.key, this.rows = 4});
  final int rows;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < rows; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                _block(context, 48, 56),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _block(context, double.infinity, 14),
                      const SizedBox(height: 10),
                      FractionallySizedBox(
                        widthFactor: .65,
                        child: _block(context, double.infinity, 10),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
  Widget _block(BuildContext context, double width, double height) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: AppRadius.small,
    ),
  );
}

/// Non-blocking foreground feedback, delayed to avoid flashes for fast reads.
class LoadingStatus extends StatefulWidget {
  const LoadingStatus({
    super.key,
    required this.active,
    required this.message,
    this.operation,
    this.onRetry,
    this.onOpenWebsite,
  });
  final bool active;
  final String message;
  final Object? operation;
  final VoidCallback? onRetry, onOpenWebsite;
  @override
  State<LoadingStatus> createState() => _LoadingStatusState();
}

class _LoadingStatusState extends State<LoadingStatus> {
  Timer? _delay, _slowTimer;
  bool _visible = false, _slow = false;
  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant LoadingStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active ||
        widget.operation != oldWidget.operation) {
      _start();
    }
  }

  void _start() {
    _delay?.cancel();
    _slowTimer?.cancel();
    _visible = _slow = false;
    if (!widget.active) return;
    _delay = Timer(AppMotion.loadingDelay, () {
      if (mounted) setState(() => _visible = true);
    });
    _slowTimer = Timer(AppMotion.slowLoading, () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _delay?.cancel();
    _slowTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active || !_visible) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.sync_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.message,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            if (_slow) ...[
              const SizedBox(height: 4),
              const Text('仍在加载，网络可能较慢'),
              Wrap(
                spacing: 8,
                children: [
                  if (widget.onRetry != null)
                    TextButton(
                      onPressed: widget.onRetry,
                      child: const Text('重试'),
                    ),
                  if (widget.onOpenWebsite != null)
                    TextButton(
                      onPressed: widget.onOpenWebsite,
                      child: const Text('在官网打开'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ContentTransition extends StatelessWidget {
  const ContentTransition({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context)) {
      return child;
    }
    return AnimatedSwitcher(
      duration: AppMotion.content,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: child,
    );
  }
}
