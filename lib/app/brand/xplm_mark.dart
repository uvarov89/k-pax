import 'package:flutter/material.dart';

import 'package:pulse_vpn/app/theme/xplm_colors.dart';

/// Vector X-Plm mark — interlocking X with diamond void (matches site logo.svg).
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
      ..fillType = PathFillType.evenOdd
      ..moveTo(20, 22)
      ..lineTo(36, 16)
      ..lineTo(64, 48)
      ..lineTo(92, 16)
      ..lineTo(108, 22)
      ..lineTo(108, 38)
      ..lineTo(76, 64)
      ..lineTo(108, 90)
      ..lineTo(108, 106)
      ..lineTo(92, 112)
      ..lineTo(64, 80)
      ..lineTo(36, 112)
      ..lineTo(20, 106)
      ..lineTo(20, 90)
      ..lineTo(52, 64)
      ..lineTo(20, 38)
      ..close()
      ..moveTo(58, 64)
      ..lineTo(64, 58)
      ..lineTo(70, 64)
      ..lineTo(64, 70)
      ..close();
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _XplmMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}
