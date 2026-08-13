import 'package:flutter/material.dart';

/// Dimmed camera mask with an animated scan frame and traveling line.
class FriendQrScanOverlay extends StatefulWidget {
  const FriendQrScanOverlay({super.key, this.frameSize});

  final double? frameSize;

  @override
  State<FriendQrScanOverlay> createState() => _FriendQrScanOverlayState();
}

class _FriendQrScanOverlayState extends State<FriendQrScanOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shortest = MediaQuery.sizeOf(context).shortestSide;
    final frame = widget.frameSize ?? (shortest * 0.62).clamp(220.0, 300.0);
    const accent = Color(0xFFFF77A2);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = Curves.easeInOut.transform(_controller.value);
          return Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                key: const ValueKey('friend-qr-scan-frame'),
                painter: _ScanMaskPainter(
                  frameSize: frame,
                  accent: accent,
                  pulse: 0.55 + 0.45 * t,
                ),
              ),
              Center(
                child: SizedBox(
                  width: frame,
                  height: frame,
                  child: Align(
                    alignment: Alignment(0, -1 + 2 * t),
                    child: Container(
                      key: const ValueKey('friend-qr-scan-line'),
                      height: 2.5,
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(99),
                        gradient: LinearGradient(
                          colors: [
                            accent.withValues(alpha: 0),
                            accent.withValues(alpha: 0.95),
                            accent.withValues(alpha: 0),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.55),
                            blurRadius: 10,
                            spreadRadius: 0.4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ScanMaskPainter extends CustomPainter {
  const _ScanMaskPainter({
    required this.frameSize,
    required this.accent,
    required this.pulse,
  });

  final double frameSize;
  final Color accent;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: frameSize,
      height: frameSize,
    );
    final hole = RRect.fromRectAndRadius(rect, const Radius.circular(22));
    final mask = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(hole);
    canvas.drawPath(
      mask,
      Paint()..color = Colors.black.withValues(alpha: 0.58),
    );

    final corner = Paint()
      ..color = accent.withValues(alpha: pulse)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    const length = 28.0;
    _corner(canvas, rect.topLeft, Offset(length, 0), Offset(0, length), corner);
    _corner(
      canvas,
      rect.topRight,
      Offset(-length, 0),
      Offset(0, length),
      corner,
    );
    _corner(
      canvas,
      rect.bottomLeft,
      Offset(length, 0),
      Offset(0, -length),
      corner,
    );
    _corner(
      canvas,
      rect.bottomRight,
      Offset(-length, 0),
      Offset(0, -length),
      corner,
    );
  }

  void _corner(
    Canvas canvas,
    Offset origin,
    Offset alongX,
    Offset alongY,
    Paint paint,
  ) {
    canvas.drawPath(
      Path()
        ..moveTo(origin.dx + alongX.dx, origin.dy + alongX.dy)
        ..lineTo(origin.dx, origin.dy)
        ..lineTo(origin.dx + alongY.dx, origin.dy + alongY.dy),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ScanMaskPainter oldDelegate) =>
      oldDelegate.frameSize != frameSize ||
      oldDelegate.accent != accent ||
      oldDelegate.pulse != pulse;
}
