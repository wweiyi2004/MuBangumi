import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

/// A small MuBangumi projection window, shared by initial loading and pulling
/// a scrollable from its top edge. Live data pushes never trigger this widget.
class AsciiRefresh extends StatefulWidget {
  const AsciiRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    this.initialRefresh = true,
  });
  final Future<void> Function() onRefresh;
  final Widget child;
  final bool initialRefresh;
  @override
  State<AsciiRefresh> createState() => AsciiRefreshState();
}

class AsciiRefreshState extends State<AsciiRefresh>
    with TickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  late final AnimationController _frames = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  Future<void>? _flight;
  Timer? _delayTimer;
  Completer<void>? _delayDone;
  Future<void> _pause(Duration duration) {
    final done = Completer<void>();
    _delayDone = done;
    _delayTimer = Timer(duration, () {
      if (!done.isCompleted) done.complete();
    });
    return done.future;
  }

  bool _tracking = false,
      _busy = false,
      _initial = false,
      _failed = false,
      _complete = false;
  double _pull = 0;
  bool get _reduced => MediaQuery.disableAnimationsOf(context);
  @override
  void initState() {
    super.initState();
    if (widget.initialRefresh) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(refresh(initial: true));
      });
    }
  }

  Future<void> refresh({bool initial = false, Future<void> Function()? task}) {
    if (_flight != null) return _flight!;
    final work = _run(initial, task ?? widget.onRefresh);
    _flight = work;
    return work.whenComplete(() {
      _flight = null;
    });
  }

  Future<void> _run(bool initial, Future<void> Function() task) async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _initial = initial;
      _failed = false;
      _complete = false;
      _tracking = false;
    });
    if (_reduced) {
      _reveal.value = 1;
    } else {
      unawaited(_reveal.forward());
      _frames.repeat();
    }
    final elapsed = Stopwatch()..start();
    try {
      await task();
    } catch (_) {
      _failed = true;
    }
    if (elapsed.elapsedMilliseconds < 400) {
      await _pause(Duration(milliseconds: 400 - elapsed.elapsedMilliseconds));
    }
    if (!mounted) return;
    setState(() => _complete = true);
    await _pause(Duration(milliseconds: _failed ? 650 : 220));
    if (!mounted) return;
    _frames.stop();
    setState(() {
      _busy = false;
      _pull = 0;
    });
    if (_reduced) {
      _reveal.value = 0;
    } else {
      unawaited(_reveal.reverse());
    }
  }

  bool _scroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical || _busy) return false;
    if (n is ScrollStartNotification && n.dragDetails != null) {
      _tracking = n.metrics.extentBefore < 1;
      _pull = 0;
      _complete = false;
      _failed = false;
    }
    if (!_tracking) return false;
    if (n is OverscrollNotification && n.dragDetails != null) {
      _pull = (_pull - n.overscroll * .5).clamp(0, 80);
      _reveal.value = (_pull / 64).clamp(0, 1);
      setState(() {});
    } else if (n is ScrollUpdateNotification &&
        n.dragDetails != null &&
        n.metrics.pixels < n.metrics.minScrollExtent) {
      _pull = ((n.metrics.minScrollExtent - n.metrics.pixels) * .6).clamp(
        0,
        80,
      );
      _reveal.value = (_pull / 64).clamp(0, 1);
      setState(() {});
    } else if (n is ScrollEndNotification) {
      _tracking = false;
      if (_pull >= 60) {
        unawaited(refresh());
      } else {
        _pull = 0;
        unawaited(_reveal.reverse());
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final label = _complete
        ? (_failed ? '加载失败，向下重试' : '已更新')
        : _busy
        ? (_initial ? '正在加载…' : '正在更新…')
        : _pull >= 60
        ? '松开刷新'
        : '下拉刷新';
    return Column(
      children: [
        SizeTransition(
          sizeFactor: CurvedAnimation(
            parent: _reveal,
            curve: Curves.easeOutCubic,
          ),
          alignment: Alignment.topCenter,
          child: Semantics(
            liveRegion: true,
            label: label,
            child: Container(
              key: const ValueKey('ascii-loading-strip'),
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExcludeSemantics(
                    child: AnimatedBuilder(
                      animation: _frames,
                      builder: (context, _) {
                        final trail = const [
                          '·       ',
                          '  ·     ',
                          '    ·   ',
                          '      · ',
                        ][(_frames.value * 4).floor().clamp(0, 3)];
                        final colors = Theme.of(context).colorScheme;
                        final style = TextStyle(
                          fontFamily:
                              defaultTargetPlatform == TargetPlatform.windows
                              ? 'Consolas'
                              : 'monospace',
                          fontSize: 12,
                          height: 1.05,
                          color: colors.onSurfaceVariant,
                        );
                        return Text.rich(
                          TextSpan(
                            style: style,
                            children: [
                              const TextSpan(text: '╭───────────╮\n│ '),
                              WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: SizedBox(
                                  width: 7.2,
                                  height: 12,
                                  child: FittedBox(
                                    fit: BoxFit.contain,
                                    child: Icon(
                                      _complete
                                          ? (_failed
                                                ? Icons.priority_high
                                                : Icons.check)
                                          : Icons.play_arrow,
                                      size: 12,
                                      color: _failed
                                          ? colors.error
                                          : colors.primary,
                                    ),
                                  ),
                                ),
                              ),
                              TextSpan(
                                text:
                                    ' ${_complete ? '        ' : trail}│\n╰───────────╯',
                              ),
                            ],
                          ),
                          textScaler: TextScaler.noScaling,
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 14),
                  ExcludeSemantics(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _scroll,
            child: widget.child,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    if (_delayDone?.isCompleted == false) _delayDone!.complete();
    _frames.dispose();
    _reveal.dispose();
    super.dispose();
  }
}
