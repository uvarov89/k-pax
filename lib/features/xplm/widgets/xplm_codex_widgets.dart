import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:pulse_vpn/app/theme/xplm_colors.dart';

/// Italic XPLM / VPN wordmark from Codex HTML.
class XplmWordmark extends StatelessWidget {
  const XplmWordmark({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final titleSize = compact ? 18.0 : 24.0;
    final subSize = compact ? 16.0 : 22.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'XPLM',
          style: TextStyle(
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w900,
            fontSize: titleSize,
            height: 0.85,
            letterSpacing: -1,
            color: XplmColors.wordmark,
            shadows: const [
              Shadow(color: Color(0xFF5186A5), offset: Offset(0, 2), blurRadius: 2),
            ],
          ),
        ),
        Text(
          'VPN',
          style: TextStyle(
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w900,
            fontSize: subSize,
            height: 1,
            letterSpacing: 1,
            color: XplmColors.wordmarkVpn,
          ),
        ),
      ],
    );
  }
}

class XplmGlass extends StatelessWidget {
  const XplmGlass({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = 17,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: const LinearGradient(
          begin: Alignment(-0.6, -1),
          end: Alignment(0.8, 1),
          colors: [Color(0xFF06203C), Color(0xFF06172D), Color(0xFF092B50)],
          stops: [0.0, 0.55, 1.0],
        ),
        border: Border.all(color: XplmColors.line),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A84DC).withValues(alpha: 0.16),
            blurRadius: 9,
            spreadRadius: -1,
          ),
          BoxShadow(
            color: const Color(0xFF008EFF).withValues(alpha: 0.09),
            blurRadius: 8,
          ),
        ],
      ),
      child: Padding(
        padding: padding ?? EdgeInsets.zero,
        child: child,
      ),
    );
  }
}

class XplmRoundIconButton extends StatelessWidget {
  const XplmRoundIconButton({
    super.key,
    required this.onTap,
    this.icon,
    this.label,
  });

  final VoidCallback onTap;
  final IconData? icon;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 28,
        height: 30,
        child: Center(
          child: label != null
              ? Text(
                  label!,
                  style: const TextStyle(
                    color: Color(0xFF96B3D1),
                    fontSize: 22,
                    height: 1,
                  ),
                )
              : Icon(icon, size: 20, color: const Color(0xFF96B3D1)),
        ),
      ),
    );
  }
}

/// Metallic X mark used on shield / profile logo.
class XplmMetalX extends StatelessWidget {
  const XplmMetalX({super.key, this.width = 76, this.height = 58});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, height),
      painter: const _MetalXPainter(),
    );
  }
}

class _MetalXPainter extends CustomPainter {
  const _MetalXPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 100;
    final sy = size.height / 70;
    Path p(String d) {
      // Hard-coded paths from SVG #xmark
      return Path();
    }

    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFFFFFFF),
          Color(0xFFBCE9FF),
          Color(0xFF3E9BD4),
          Color(0xFFD6F5FF),
        ],
        stops: [0.0, 0.45, 0.5, 1.0],
      ).createShader(Offset.zero & size);

    final a = Path()
      ..moveTo(3 * sx, 4 * sy)
      ..lineTo(27 * sx, 4 * sy)
      ..lineTo(97 * sx, 66 * sy)
      ..lineTo(73 * sx, 66 * sy)
      ..close();
    final b = Path()
      ..moveTo(72 * sx, 4 * sy)
      ..lineTo(97 * sx, 4 * sy)
      ..lineTo(28 * sx, 66 * sy)
      ..lineTo(3 * sx, 66 * sy)
      ..lineTo(39 * sx, 34 * sy)
      ..lineTo(52 * sx, 46 * sy)
      ..close();
    canvas.drawPath(a, paint);
    canvas.drawPath(b, paint);
    // silence unused
    p('');
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class XplmHeroShield extends StatelessWidget {
  const XplmHeroShield({
    super.key,
    required this.connected,
    this.width = 123,
    this.height = 139,
  });

  final bool connected;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _HeroShieldPainter(connected: connected),
        child: Center(
          child: Padding(
            padding: EdgeInsets.only(top: height * 0.18),
            child: XplmMetalX(width: width * 0.54, height: height * 0.42),
          ),
        ),
      ),
    );
  }
}

class _HeroShieldPainter extends CustomPainter {
  _HeroShieldPainter({required this.connected});

  final bool connected;

  @override
  void paint(Canvas canvas, Size size) {
    Path shield(double inset) {
      final w = size.width;
      final h = size.height;
      final path = Path();
      final t = inset;
      path.moveTo(w * 0.5, h * 0.05 + t);
      path.cubicTo(w * 0.35, h * 0.15, w * 0.18, h * 0.17, w * 0.08 + t, h * 0.19);
      path.lineTo(w * 0.08 + t, h * 0.42);
      path.cubicTo(
        w * 0.08,
        h * 0.68,
        w * 0.32,
        h * 0.84,
        w * 0.5,
        h * 0.95 - t,
      );
      path.cubicTo(
        w * 0.68,
        h * 0.84,
        w * 0.92,
        h * 0.68,
        w * 0.92 - t,
        h * 0.42,
      );
      path.lineTo(w * 0.92 - t, h * 0.19);
      path.cubicTo(w * 0.82, h * 0.17, w * 0.65, h * 0.14, w * 0.5, h * 0.05 + t);
      path.close();
      return path;
    }

    final glow = Paint()
      ..color = const Color(0xFF012A56)
      ..style = PaintingStyle.fill;
    canvas.drawPath(shield(0), glow);
    canvas.drawPath(
      shield(0),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF62DEFF),
    );

    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: connected
            ? const [Color(0xFF078FFF), Color(0xFF042547), Color(0xFF0063C7)]
            : const [Color(0xFF3A779B), Color(0xFF1A3040), Color(0xFF244A66)],
      ).createShader(Offset.zero & size);
    canvas.drawPath(shield(size.width * 0.04), fill);
    canvas.drawPath(
      shield(size.width * 0.04),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF33BAFF),
    );
  }

  @override
  bool shouldRepaint(covariant _HeroShieldPainter oldDelegate) =>
      oldDelegate.connected != connected;
}

class XplmEarthBackdrop extends StatelessWidget {
  const XplmEarthBackdrop({
    super.key,
    this.width = 345,
    this.height = 225,
    this.rotate = -9,
  });

  final double width;
  final double height;
  final double rotate;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Transform.rotate(
        angle: rotate * math.pi / 180,
        child: Center(
          child: SizedBox(
            width: width,
            height: height,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(width),
                border: const Border(
                  top: BorderSide(color: Color(0xFF50D9FF), width: 3),
                ),
                gradient: const RadialGradient(
                  center: Alignment(0, -1),
                  radius: 1.2,
                  colors: [
                    Color(0xFF036AC5),
                    Color(0xFF063569),
                    Color(0xFF001A35),
                    Color(0xFF010B1C),
                  ],
                  stops: [0.0, 0.3, 0.55, 0.7],
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0xFF00BAFF),
                    blurRadius: 9,
                    offset: Offset(0, -5),
                  ),
                  BoxShadow(
                    color: Color(0x990077FF),
                    blurRadius: 30,
                    offset: Offset(0, -12),
                  ),
                  BoxShadow(
                    color: Color(0xFF008EFF),
                    blurRadius: 22,
                    offset: Offset(0, 10),
                    blurStyle: BlurStyle.inner,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(width),
                child: CustomPaint(painter: _EarthDotsPainter()),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EarthDotsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(7);
    for (var i = 0; i < 90; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = rnd.nextDouble() * size.height * 0.55;
      final r = 0.6 + rnd.nextDouble() * 1.4;
      final color = i.isEven
          ? const Color(0xFFB7EFFF)
          : (i % 3 == 0 ? const Color(0xFFE4D7A4) : const Color(0xFF278FE6));
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()..color = color.withValues(alpha: 0.55),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class XplmSignalBars extends StatelessWidget {
  const XplmSignalBars({super.key, required this.latencyMs, this.height = 17});

  final int latencyMs;
  final double height;

  @override
  Widget build(BuildContext context) {
    // Codex HTML `.signal i` is always #33cf8f, all four bars filled.
    const c = Color(0xFF33CF8F);
    const hs = [5.0, 9.0, 12.0, 16.0];
    return SizedBox(
      height: height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 4; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            Container(
              width: 3,
              height: hs[i],
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(1),
                color: latencyMs < 0 ? c.withValues(alpha: 0.25) : c,
                boxShadow: latencyMs < 0
                    ? null
                    : const [
                        BoxShadow(color: Color(0x4D08DBA1), blurRadius: 3),
                      ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class XplmFlagCircle extends StatelessWidget {
  const XplmFlagCircle({super.key, required this.code, this.size = 30});

  final String code;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = code.toLowerCase();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.3),
            blurRadius: 5,
            spreadRadius: -2,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ClipOval(
        child: CustomPaint(
          size: Size.square(size),
          painter: _CodexFlagPainter(c),
        ),
      ),
    );
  }
}

class _CodexFlagPainter extends CustomPainter {
  _CodexFlagPainter(this.code);
  final String code;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    void bands(List<Color> colors, {bool vertical = false}) {
      if (vertical) {
        final w = size.width / colors.length;
        for (var i = 0; i < colors.length; i++) {
          canvas.drawRect(
            Rect.fromLTWH(w * i, 0, w, size.height),
            Paint()..color = colors[i],
          );
        }
      } else {
        final h = size.height / colors.length;
        for (var i = 0; i < colors.length; i++) {
          canvas.drawRect(
            Rect.fromLTWH(0, h * i, size.width, h),
            Paint()..color = colors[i],
          );
        }
      }
    }

    switch (code) {
      case 'de':
        bands(const [Color(0xFF101010), Color(0xFFE52E29), Color(0xFFFFCF20)]);
      case 'fi':
        canvas.drawRect(r, Paint()..color = const Color(0xFFF3F7FA));
        canvas.drawRect(
          Rect.fromLTWH(0, size.height * 0.39, size.width, size.height * 0.18),
          Paint()..color = const Color(0xFF005BAA),
        );
        canvas.drawRect(
          Rect.fromLTWH(size.width * 0.30, 0, size.width * 0.17, size.height),
          Paint()..color = const Color(0xFF005BAA),
        );
      case 'bg':
        bands(const [Color(0xFFFFFFFF), Color(0xFF009671), Color(0xFFD52D38)]);
      case 'fr':
        bands(const [Color(0xFF034EA3), Color(0xFFFFFFFF), Color(0xFFE13B49)],
            vertical: true);
      case 'nl':
        bands(const [Color(0xFFD62F43), Color(0xFFFFFFFF), Color(0xFF1748A0)]);
      case 'us':
        for (var i = 0; i < 7; i++) {
          canvas.drawRect(
            Rect.fromLTWH(0, size.height / 7 * i, size.width, size.height / 7),
            Paint()
              ..color = i.isEven ? const Color(0xFFE34451) : Colors.white,
          );
        }
        canvas.drawRect(
          Rect.fromLTWH(0, 0, size.width * 0.45, size.height * 0.55),
          Paint()..color = const Color(0xFF1C478E),
        );
      case 'gb':
      case 'uk':
        canvas.drawRect(r, Paint()..color = const Color(0xFF17447C));
        final white = Paint()
          ..color = Colors.white
          ..strokeWidth = size.shortestSide * 0.14
          ..style = PaintingStyle.stroke;
        final red = Paint()
          ..color = const Color(0xFFDC3352)
          ..strokeWidth = size.shortestSide * 0.08
          ..style = PaintingStyle.stroke;
        canvas.drawLine(r.topLeft, r.bottomRight, white);
        canvas.drawLine(r.topRight, r.bottomLeft, white);
        canvas.drawLine(r.topLeft, r.bottomRight, red);
        canvas.drawLine(r.topRight, r.bottomLeft, red);
        canvas.drawRect(
          Rect.fromCenter(center: r.center, width: size.width, height: size.height * 0.22),
          Paint()..color = Colors.white,
        );
        canvas.drawRect(
          Rect.fromCenter(center: r.center, width: size.width * 0.22, height: size.height),
          Paint()..color = Colors.white,
        );
        canvas.drawRect(
          Rect.fromCenter(center: r.center, width: size.width, height: size.height * 0.12),
          Paint()..color = const Color(0xFFDC3352),
        );
        canvas.drawRect(
          Rect.fromCenter(center: r.center, width: size.width * 0.12, height: size.height),
          Paint()..color = const Color(0xFFDC3352),
        );
      case 'sg':
        bands(const [Color(0xFFDF3045), Color(0xFFFFFFFF)]);
      case 'auto':
        canvas.drawRect(r, Paint()..color = const Color(0xFF06416A));
        final tp = TextPainter(
          text: const TextSpan(
            text: 'A',
            style: TextStyle(
              color: Color(0xFF00AAFF),
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2),
        );
      default:
        bands(const [Color(0xFF00AAFF), Color(0xFF0063C7), Color(0xFF00AAFF)]);
    }
  }

  @override
  bool shouldRepaint(covariant _CodexFlagPainter oldDelegate) =>
      oldDelegate.code != code;
}

class XplmPrimaryButton extends StatelessWidget {
  const XplmPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.height = 46,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final double height;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF00ADFF), Color(0xFF0074F6)],
        ),
        border: Border.all(color: const Color(0xFF008CFF)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8DEEFF).withValues(alpha: 0.27),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: const Color(0xFF007CFF).withValues(alpha: 0.19),
            blurRadius: 17,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(25),
          onTap: busy ? null : onPressed,
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[
                          Icon(icon, color: Colors.white, size: 20),
                          const SizedBox(width: 10),
                        ],
                        Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
