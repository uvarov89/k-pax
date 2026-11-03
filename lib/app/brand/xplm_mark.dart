import 'package:flutter/material.dart';

import 'package:pulse_vpn/app/theme/xplm_colors.dart';

/// Vector X-Plm mark (same geometry as assets/brand/xplm_mark.svg).
class XplmMark extends StatelessWidget {
  const XplmMark({
    super.key,
    this.size = 36,
    this.color = XplmColors.accent,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _XplmMarkPainter(color: color),
      ),
    );
  }
}

class _XplmMarkPainter extends CustomPainter {
  const _XplmMarkPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 128;
    canvas.save();
    canvas.scale(scale);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final path = Path()
      ..moveTo(22.2, 24.4)
      ..cubicTo(24.1, 22.1, 27.6, 21.8, 30.2, 23.6)
      ..lineTo(61.4, 48.8)
      ..lineTo(94.8, 22.1)
      ..cubicTo(97.5, 20, 101.2, 20.4, 103.2, 22.9)
      ..cubicTo(105.3, 25.5, 104.9, 29.3, 102.4, 31.4)
      ..lineTo(70.6, 56.9)
      ..lineTo(103.1, 96.4)
      ..cubicTo(105.4, 99.1, 104.9, 103.1, 102.1, 105.3)
      ..cubicTo(99.4, 107.5, 95.5, 107, 93.3, 104.3)
      ..lineTo(62.1, 66.5)
      ..lineTo(30.6, 105.1)
      ..cubicTo(28.3, 107.8, 24.3, 107.9, 21.7, 105.4)
      ..cubicTo(19.1, 102.9, 19.2, 98.9, 21.7, 96.4)
      ..lineTo(54.8, 56.1)
      ..lineTo(23.4, 31.2)
      ..cubicTo(20.9, 29.1, 20.4, 25.4, 22.2, 24.4)
      ..close();
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _XplmMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}
