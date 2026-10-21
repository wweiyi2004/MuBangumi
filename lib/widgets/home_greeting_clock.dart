import 'dart:async';
import 'package:flutter/material.dart';
import '../core/layout/app_layout.dart';

class HomeGreetingClock extends StatefulWidget {
  const HomeGreetingClock({
    super.key,
    required this.nickname,
    required this.phone,
    this.now,
  });
  final String nickname;
  final bool phone;
  final DateTime Function()? now;
  @override
  State<HomeGreetingClock> createState() => _HomeGreetingClockState();
}

class _HomeGreetingClockState extends State<HomeGreetingClock> {
  late DateTime _time;
  Timer? _timer;
  late final AppLifecycleListener _lifecycle;
  DateTime _now() => widget.now?.call() ?? DateTime.now();
  @override
  void initState() {
    super.initState();
    _time = _now();
    _schedule();
    _lifecycle = AppLifecycleListener(
      onResume: _refresh,
      onPause: () => _timer?.cancel(),
      onHide: () => _timer?.cancel(),
    );
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(
      Duration(milliseconds: 60000 - (_time.second * 1000 + _time.millisecond)),
      _refresh,
    );
  }

  void _refresh() {
    if (!mounted) return;
    setState(() => _time = _now());
    _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final titleStyle = AppLayout.pageTitleStyle(context)?.copyWith(height: 1.1);
    final greeting = _time.hour < 11
        ? '早上好'
        : _time.hour < 18
        ? '下午好'
        : '晚上好';
    const weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    final clock =
        '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                widget.phone ? greeting : '$greeting，${widget.nickname}',
                style: titleStyle,
              ),
              const SizedBox(width: 12),
              Semantics(
                label: '当前时间 $clock',
                excludeSemantics: true,
                child: Text(
                  clock,
                  key: const ValueKey('home-clock'),
                  style: titleStyle?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 5),
        Text(
          '${_time.month} 月 ${_time.day} 日 · ${weekdays[_time.weekday - 1]}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: widget.phone ? 13 : null,
          ),
        ),
      ],
    );
  }
}
