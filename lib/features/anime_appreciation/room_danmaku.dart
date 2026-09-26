import 'dart:async';
import 'dart:math';
import 'package:banjian_server/banjian_server.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_tokens.dart';

/// New visible comments of the current round fly across [child] once. The
/// first snapshot of a round only records what is already there, and hidden
/// comments never fly. Purely decorative: the wall lists the same text.
class RoomDanmaku extends StatefulWidget {
  const RoomDanmaku({super.key, required this.event, required this.child});
  final Json? event;
  final Widget child;
  @override
  State<RoomDanmaku> createState() => _RoomDanmakuState();
}

class _Bullet {
  _Bullet(this.text, this.lane, this.controller);
  final String text;
  final int lane;
  final AnimationController controller;
  Timer? start;
}

class _RoomDanmakuState extends State<RoomDanmaku>
    with TickerProviderStateMixin {
  static const _lanes = 5, _laneHeight = 44.0, _limit = 12;
  String? _round;
  final _seen = <String>{};
  final _flying = <_Bullet>[];
  var _lane = 0;
  var _reduced = false;

  @override
  void initState() {
    super.initState();
    _sync(launch: false);
  }

  @override
  void didUpdateWidget(RoomDanmaku old) {
    super.didUpdateWidget(old);
    _sync(launch: true);
  }

  @override
  void dispose() {
    for (final b in _flying) {
      b.start?.cancel();
      b.controller.dispose();
    }
    super.dispose();
  }

  void _sync({required bool launch}) {
    final e = widget.event;
    final r = ((e?['rounds'] as List?) ?? const [])
        .cast<Json>()
        .where((r) => r['id'] == e?['current'])
        .firstOrNull;
    final comments = ((r?['comments'] as List?) ?? const []).cast<Json>();
    if (r?['id'] != _round) {
      _round = r?['id'] as String?;
      _seen
        ..clear()
        ..addAll(comments.map((c) => c['id'] as String));
      return;
    }
    final fresh = comments
        .where((c) => !_seen.contains(c['id']) && c['hidden'] != true)
        .toList();
    _seen.addAll(comments.map((c) => c['id'] as String));
    if (!launch || _reduced || fresh.isEmpty) return;
    // Comments arrive oldest first; a burst only shows its newest few.
    final burst = fresh.skip(max(0, fresh.length - 6)).toList();
    for (var i = 0; i < burst.length && _flying.length < _limit; i++) {
      final chars = (burst[i]['text'] as String).characters;
      final bullet = _Bullet(
        chars.length > 40 ? '${chars.take(40)}…' : chars.string,
        _lane++ % _lanes,
        AnimationController(vsync: this, duration: const Duration(seconds: 7)),
      );
      bullet.controller.addStatusListener((status) {
        if (status != AnimationStatus.completed || !mounted) return;
        setState(() => _flying.remove(bullet));
        bullet.controller.dispose();
      });
      bullet.start = Timer(
        Duration(milliseconds: 600 * i),
        () => bullet.controller.forward(),
      );
      _flying.add(bullet);
    }
  }

  @override
  Widget build(BuildContext context) {
    _reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Stack(
      children: [
        widget.child,
        if (_flying.isNotEmpty)
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            height: _lanes * _laneHeight,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: ClipRect(
                  child: LayoutBuilder(
                    builder: (context, box) => Stack(
                      children: [
                        for (final b in _flying)
                          Positioned(
                            key: ObjectKey(b),
                            left: 0,
                            top: b.lane * _laneHeight,
                            child: AnimatedBuilder(
                              animation: b.controller,
                              // Enter from the right edge, leave fully left.
                              builder: (_, child) => Transform.translate(
                                offset: Offset(
                                  box.maxWidth * (1 - b.controller.value),
                                  0,
                                ),
                                child: FractionalTranslation(
                                  translation: Offset(-b.controller.value, 0),
                                  child: child,
                                ),
                              ),
                              child: _pill(b.text),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _pill(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .58),
      borderRadius: AppRadius.round,
    ),
    child: Text(
      text,
      maxLines: 1,
      softWrap: false,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        shadows: [Shadow(blurRadius: 2, color: Colors.black54)],
      ),
    ),
  );
}
