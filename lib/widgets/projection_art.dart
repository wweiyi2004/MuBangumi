import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// MuBangumi's small projection-window motif. Drawn locally, with theme colors;
/// it needs no downloaded images, fonts, or animation assets.
enum ProjectionScene { discover, collection, conversation }

class ProjectionIllustration extends StatelessWidget {
  const ProjectionIllustration({
    super.key,
    required this.scene,
    this.width = 108,
  });
  final ProjectionScene scene;
  final double width;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: width,
      height: width * .64,
      child: CustomPaint(
        painter: _ProjectionPainter(scene, Theme.of(context).colorScheme),
      ),
    ),
  );
}

class _ProjectionPainter extends CustomPainter {
  _ProjectionPainter(this.scene, this.colors);
  final ProjectionScene scene;
  final ColorScheme colors;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 160, size.height / 104);
    final line = Paint()
      ..color = colors.onSurfaceVariant.withValues(alpha: .65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final accent = Paint()..color = colors.primary;
    final paper = Paint()..color = colors.surfaceContainerLow;
    final wash = Paint()..color = colors.primary.withValues(alpha: .08);
    canvas.drawOval(const Rect.fromLTWH(24, 86, 116, 8), wash);
    canvas.drawCircle(const Offset(79, 49), 40, wash);
    void frame(Rect rect, {bool filled = true}) {
      final shape = RRect.fromRectAndRadius(rect, const Radius.circular(8));
      if (filled) canvas.drawRRect(shape, paper);
      canvas.drawRRect(shape, line);
    }

    void play(Offset at) {
      canvas.drawPath(
        Path()
          ..moveTo(at.dx - 4, at.dy - 7)
          ..lineTo(at.dx + 7, at.dy)
          ..lineTo(at.dx - 4, at.dy + 7)
          ..close(),
        accent,
      );
    }

    switch (scene) {
      case ProjectionScene.discover:
        frame(const Rect.fromLTWH(28, 23, 82, 57));
        for (var i = 0; i < 4; i++) {
          canvas.drawLine(
            Offset(35.0 + i * 20, 29),
            Offset(40.0 + i * 20, 29),
            line,
          );
        }
        play(const Offset(65, 54));
        canvas.drawCircle(const Offset(112, 64), 19, paper);
        canvas.drawCircle(const Offset(112, 64), 19, line);
        canvas.drawLine(
          const Offset(126, 78),
          const Offset(139, 91),
          line..strokeWidth = 3,
        );
        canvas.drawCircle(const Offset(112, 64), 4, wash);
      case ProjectionScene.collection:
        frame(const Rect.fromLTWH(47, 18, 59, 60));
        frame(const Rect.fromLTWH(38, 28, 79, 57));
        frame(const Rect.fromLTWH(30, 39, 100, 47));
        canvas.drawLine(const Offset(40, 47), const Offset(120, 47), line);
        play(const Offset(80, 65));
      case ProjectionScene.conversation:
        frame(const Rect.fromLTWH(56, 22, 76, 46));
        frame(const Rect.fromLTWH(26, 39, 79, 44));
        canvas.drawPath(
          Path()
            ..moveTo(41, 83)
            ..lineTo(38, 92)
            ..lineTo(54, 83),
          line,
        );
        play(const Offset(65, 60));
        for (var i = 0; i < 3; i++) {
          canvas.drawCircle(Offset(85.0 + i * 11, 32), 1.5, accent);
        }
    }
    line.strokeWidth = 1.3;
    canvas.drawLine(const Offset(22, 20), const Offset(22, 28), line);
    canvas.drawLine(const Offset(18, 24), const Offset(26, 24), line);
    canvas.drawCircle(const Offset(137, 39), 2, accent);
    canvas.drawLine(const Offset(15, 67), const Offset(20, 67), line);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ProjectionPainter old) =>
      old.scene != scene || old.colors != colors;
}

/// Five text frames gather scattered pixels into the brand's play mark.
class ProjectionGlyph extends StatelessWidget {
  const ProjectionGlyph({
    super.key,
    this.progress = 0,
    this.complete = false,
    this.failed = false,
  });
  final double progress;
  final bool complete, failed;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const frames = [
      [' ·     · ', '    ·    ', ' ·     · '],
      ['   · ·   ', '  · · ·  ', '   · ·   '],
      ['   ▸     ', '   ▸ ▸   ', '   ▸     '],
      ['   ▸▸    ', '   ▸▸▸   ', '   ▸▸    '],
      ['   ▸     ', '   ▸▸    ', '   ▸     '],
    ];
    final frame =
        frames[(progress * frames.length).floor().clamp(0, frames.length - 1)];
    final rows = complete
        ? ['         ', failed ? '    !    ' : '   OK    ', '         ']
        : frame;
    return ExcludeSemantics(
      child: Text.rich(
        TextSpan(
          style: TextStyle(
            fontFamily: defaultTargetPlatform == TargetPlatform.windows
                ? 'Consolas'
                : 'monospace',
            fontSize: 8.5,
            height: 1.03,
            color: colors.onSurfaceVariant,
          ),
          children: [
            const TextSpan(text: '╭─────────╮\n'),
            for (final row in rows) ...[
              const TextSpan(text: '│'),
              TextSpan(
                text: row,
                style: TextStyle(color: failed ? colors.error : colors.primary),
              ),
              const TextSpan(text: '│\n'),
            ],
            const TextSpan(text: '╰─────────╯'),
          ],
        ),
        textScaler: TextScaler.noScaling,
      ),
    );
  }
}
