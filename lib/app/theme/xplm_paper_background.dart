import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:pulse_vpn/app/theme/xplm_colors.dart';

/// Dark navy + neon wash + soft mesh/network (X-Plm mock atmosphere).
class XplmPaperBackground extends StatefulWidget {
  const XplmPaperBackground({super.key, required this.child});

  final Widget child;

  @override
  State<XplmPaperBackground> createState() => _XplmPaperBackgroundState();
}

class _XplmPaperBackgroundState extends State<XplmPaperBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift;

  @override
  void initState() {
    super.initState();
    _drift = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return ColoredBox(
      color: XplmColors.paper,
      child: reduce
          ? _WashLayer(t: 0.45, child: widget.child)
          : AnimatedBuilder(
              animation: _drift,
              builder: (context, child) {
                final t = Curves.easeInOutCubic.transform(_drift.value);
                return _WashLayer(t: t, child: child!);
              },
              child: widget.child,
            ),
    );
  }
}

class _WashLayer extends StatelessWidget {
  const _WashLayer({required this.t, required this.child});

  final double t;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dx = -0.06 + t * 0.12;
    final dy = -0.04 + t * 0.08;
    final a = 0.55 + t * 0.35;
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: Opacity(
            opacity: a,
            child: Transform.translate(
              offset: Offset(dx * 28, dy * 20),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0.0, -0.55),
                    radius: 1.05,
                    colors: [
                      Color(0x883D9BFF),
                      Color(0x331458C8),
                      Color(0x00050B18),
                    ],
                    stops: [0.0, 0.42, 1.0],
                  ),
                ),
                child: SizedBox.expand(),
              ),
            ),
          ),
        ),
        IgnorePointer(
          child: Opacity(
            opacity: a * 0.9,
            child: Transform.translate(
              offset: Offset(-dx * 18, dy * 14),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0.0, 1.05),
                    radius: 0.95,
                    colors: [
                      Color(0x552F8CFF),
                      Color(0x220B1224),
                      Color(0x00050B18),
                    ],
                    stops: [0.0, 0.5, 1.0],
                  ),
                ),
                child: SizedBox.expand(),
              ),
            ),
          ),
        ),
        IgnorePointer(
          child: Opacity(
            opacity: a * 0.55,
            child: Transform.translate(
              offset: Offset(dx * 20, -dy * 10),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0.95, 0.15),
                    radius: 0.75,
                    colors: [
                      Color(0x335EC8FF),
                      Color(0x00050B18),
                    ],
                    stops: [0.0, 0.7],
                  ),
                ),
                child: SizedBox.expand(),
              ),
            ),
          ),
        ),
        const IgnorePointer(child: CustomPaint(painter: _MeshNetPainter())),
        child,
      ],
    );
  }
}

class _MeshNetPainter extends CustomPainter {
  const _MeshNetPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final mesh = Paint()
      ..color = const Color(0x125EC8FF)
      ..strokeWidth = 1;
    const step = 28.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), mesh);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), mesh);
    }

    final fade = ui.Gradient.radial(
      Offset(size.width * 0.5, size.height * 0.72),
      size.shortestSide * 0.7,
      const [Color(0xFF000000), Color(0x00000000)],
      const [0.15, 1.0],
    );
    canvas.saveLayer(Offset.zero & size, Paint());
    final net = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = const Color(0x405EC8FF);
    final path = Path()
      ..moveTo(0, size.height * 0.78)
      ..lineTo(size.width * 0.18, size.height * 0.58)
      ..lineTo(size.width * 0.38, size.height * 0.72)
      ..lineTo(size.width * 0.58, size.height * 0.48)
      ..lineTo(size.width * 0.78, size.height * 0.66)
      ..lineTo(size.width, size.height * 0.42);
    final path2 = Path()
      ..moveTo(0, size.height * 0.9)
      ..lineTo(size.width * 0.25, size.height * 0.64)
      ..lineTo(size.width * 0.5, size.height * 0.8)
      ..lineTo(size.width * 0.72, size.height * 0.55)
      ..lineTo(size.width, size.height * 0.7);
    canvas.drawPath(path, net);
    canvas.drawPath(path2, net);
    final dots = Paint()..color = const Color(0x885EC8FF);
    for (final p in [
      Offset(size.width * 0.18, size.height * 0.58),
      Offset(size.width * 0.38, size.height * 0.72),
      Offset(size.width * 0.58, size.height * 0.48),
      Offset(size.width * 0.78, size.height * 0.66),
      Offset(size.width * 0.5, size.height * 0.8),
    ]) {
      canvas.drawCircle(p, 2.2, dots);
    }
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = fade,
    );
    canvas.restore();

    // Soft vignette so mesh does not fight text near edges.
    final vig = Paint()
      ..shader = ui.Gradient.radial(
        Offset(size.width / 2, size.height * 0.4),
        math.max(size.width, size.height) * 0.85,
        const [Color(0x00000000), Color(0x33050B18)],
        const [0.55, 1.0],
      );
    canvas.drawRect(Offset.zero & size, vig);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
