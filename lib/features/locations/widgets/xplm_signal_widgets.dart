import 'package:flutter/material.dart';

import 'package:pulse_vpn/app/theme/xplm_colors.dart';

/// Circular country flag (CSS-style gradients from HTML mock).
class XplmCountryFlag extends StatelessWidget {
  const XplmCountryFlag({
    super.key,
    required this.countryCode,
    this.size = 34,
  });

  final String countryCode;
  final double size;

  @override
  Widget build(BuildContext context) {
    final code = countryCode.toUpperCase();
    if (code == 'AUTO' || code == 'NODE' || code.isEmpty) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: XplmColors.accentSoft,
          border: Border.all(color: XplmColors.cyan.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: XplmColors.cyan.withValues(alpha: 0.2),
              blurRadius: 10,
            ),
          ],
        ),
        child: Text(
          code == 'AUTO' ? 'A' : '?',
          style: TextStyle(
            fontSize: size * 0.34,
            fontWeight: FontWeight.w800,
            color: XplmColors.cyan,
          ),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.18),
            blurRadius: 0,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: XplmColors.cyan.withValues(alpha: 0.2),
            blurRadius: 10,
          ),
        ],
      ),
      child: ClipOval(
        child: CustomPaint(
          size: Size.square(size),
          painter: _FlagPainter(code),
        ),
      ),
    );
  }
}

/// 4-bar cellular ping meter: green / yellow / red by latency.
class XplmPingBars extends StatelessWidget {
  const XplmPingBars({
    super.key,
    required this.latencyMs,
    this.height = 16,
  });

  final int latencyMs;
  final double height;

  static PingQuality qualityFor(int latencyMs) {
    if (latencyMs < 0) return PingQuality.unknown;
    if (latencyMs <= 55) return PingQuality.good;
    if (latencyMs <= 100) return PingQuality.medium;
    return PingQuality.bad;
  }

  static Color colorFor(PingQuality q) {
    switch (q) {
      case PingQuality.good:
        return XplmColors.ok;
      case PingQuality.medium:
        return const Color(0xFFFFC24A);
      case PingQuality.bad:
        return XplmColors.danger;
      case PingQuality.unknown:
        return XplmColors.ink3;
    }
  }

  static int filledBarsFor(PingQuality q) {
    switch (q) {
      case PingQuality.good:
        return 4;
      case PingQuality.medium:
        return 3;
      case PingQuality.bad:
        return 2;
      case PingQuality.unknown:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = qualityFor(latencyMs);
    final color = colorFor(q);
    final filled = filledBarsFor(q);
    const heights = [0.32, 0.55, 0.78, 1.0];
    return SizedBox(
      height: height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 4; i++) ...[
            if (i > 0) const SizedBox(width: 2.5),
            Container(
              width: 3.2,
              height: height * heights[i],
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: i < filled
                    ? color
                    : color.withValues(alpha: 0.22),
                boxShadow: i < filled
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.65),
                          blurRadius: 6,
                        ),
                      ]
                    : null,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum PingQuality { good, medium, bad, unknown }

class _FlagPainter extends CustomPainter {
  _FlagPainter(this.code);

  final String code;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    switch (code) {
      case 'DE':
        _hBands(canvas, rect, const [
          Color(0xFF111111),
          Color(0xFFDD0000),
          Color(0xFFFFCE00),
        ]);
      case 'FI':
        _fi(canvas, rect);
      case 'BG':
        _hBands(canvas, rect, const [
          Color(0xFFFFFFFF),
          Color(0xFF00966E),
          Color(0xFFD62612),
        ]);
      case 'FR':
        _vBands(canvas, rect, const [
          Color(0xFF002395),
          Color(0xFFFFFFFF),
          Color(0xFFED2939),
        ]);
      case 'NL':
        _hBands(canvas, rect, const [
          Color(0xFFAE1C28),
          Color(0xFFFFFFFF),
          Color(0xFF21468B),
        ]);
      case 'US':
        _us(canvas, rect);
      case 'GB':
      case 'UK':
        _gb(canvas, rect);
      case 'SG':
        _hBands(canvas, rect, const [
          Color(0xFFEF3340),
          Color(0xFFFFFFFF),
        ]);
      case 'SE':
        _se(canvas, rect);
      case 'PL':
        _hBands(canvas, rect, const [
          Color(0xFFFFFFFF),
          Color(0xFFDC143C),
        ]);
      case 'IT':
        _vBands(canvas, rect, const [
          Color(0xFF009246),
          Color(0xFFFFFFFF),
          Color(0xFFCE2B37),
        ]);
      case 'ES':
        _hBands(
          canvas,
          rect,
          const [
            Color(0xFFAA151B),
            Color(0xFFF1BF00),
            Color(0xFFAA151B),
          ],
          ratios: const [0.25, 0.5, 0.25],
        );
      case 'TR':
        canvas.drawRect(rect, Paint()..color = const Color(0xFFE30A17));
      case 'RU':
        _hBands(canvas, rect, const [
          Color(0xFFFFFFFF),
          Color(0xFF0039A6),
          Color(0xFFD52B1E),
        ]);
      case 'JP':
        canvas.drawRect(rect, Paint()..color = Colors.white);
        canvas.drawCircle(
          Offset(size.width * 0.5, size.height * 0.5),
          size.shortestSide * 0.28,
          Paint()..color = const Color(0xFFBC002D),
        );
      case 'KR':
        canvas.drawRect(rect, Paint()..color = Colors.white);
        canvas.drawCircle(
          Offset(size.width * 0.5, size.height * 0.5),
          size.shortestSide * 0.22,
          Paint()..color = const Color(0xFFCD2E3A),
        );
      case 'CN':
        canvas.drawRect(rect, Paint()..color = const Color(0xFFDE2910));
      case 'CA':
        _hBands(
          canvas,
          rect,
          const [
            Color(0xFFFF0000),
            Color(0xFFFFFFFF),
            Color(0xFFFF0000),
          ],
          ratios: const [0.25, 0.5, 0.25],
        );
      case 'AU':
        canvas.drawRect(rect, Paint()..color = const Color(0xFF00008B));
      default:
        _hBands(canvas, rect, const [
          XplmColors.accent,
          XplmColors.cyan,
          XplmColors.accent,
        ]);
    }
  }

  void _hBands(
    Canvas canvas,
    Rect rect,
    List<Color> colors, {
    List<double>? ratios,
  }) {
    final r = ratios ?? List.filled(colors.length, 1 / colors.length);
    var y = rect.top;
    for (var i = 0; i < colors.length; i++) {
      final h = rect.height * r[i];
      canvas.drawRect(
        Rect.fromLTWH(rect.left, y, rect.width, h),
        Paint()..color = colors[i],
      );
      y += h;
    }
  }

  void _vBands(Canvas canvas, Rect rect, List<Color> colors) {
    final w = rect.width / colors.length;
    for (var i = 0; i < colors.length; i++) {
      canvas.drawRect(
        Rect.fromLTWH(rect.left + w * i, rect.top, w, rect.height),
        Paint()..color = colors[i],
      );
    }
  }

  void _fi(Canvas canvas, Rect rect) {
    canvas.drawRect(rect, Paint()..color = Colors.white);
    final paint = Paint()..color = const Color(0xFF003580);
    canvas.drawRect(
      Rect.fromLTWH(
        rect.left,
        rect.top + rect.height * 0.38,
        rect.width,
        rect.height * 0.24,
      ),
      paint,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        rect.left + rect.width * 0.28,
        rect.top,
        rect.width * 0.22,
        rect.height,
      ),
      paint,
    );
  }

  void _se(Canvas canvas, Rect rect) {
    canvas.drawRect(rect, Paint()..color = const Color(0xFF006AA7));
    final paint = Paint()..color = const Color(0xFFFECC00);
    canvas.drawRect(
      Rect.fromLTWH(
        rect.left,
        rect.top + rect.height * 0.38,
        rect.width,
        rect.height * 0.24,
      ),
      paint,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        rect.left + rect.width * 0.28,
        rect.top,
        rect.width * 0.22,
        rect.height,
      ),
      paint,
    );
  }

  void _us(Canvas canvas, Rect rect) {
    final stripeH = rect.height / 7;
    for (var i = 0; i < 7; i++) {
      canvas.drawRect(
        Rect.fromLTWH(rect.left, rect.top + stripeH * i, rect.width, stripeH),
        Paint()
          ..color = i.isEven
              ? const Color(0xFFB22234)
              : Colors.white,
      );
    }
    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.top, rect.width * 0.42, rect.height * 0.54),
      Paint()..color = const Color(0xFF3C3B6E),
    );
  }

  void _gb(Canvas canvas, Rect rect) {
    canvas.drawRect(rect, Paint()..color = const Color(0xFF012169));
    final white = Paint()
      ..color = Colors.white
      ..strokeWidth = rect.shortestSide * 0.18
      ..style = PaintingStyle.stroke;
    final red = Paint()
      ..color = const Color(0xFFC8102E)
      ..strokeWidth = rect.shortestSide * 0.1
      ..style = PaintingStyle.stroke;
    canvas.drawLine(rect.topLeft, rect.bottomRight, white);
    canvas.drawLine(rect.topRight, rect.bottomLeft, white);
    canvas.drawLine(rect.topLeft, rect.bottomRight, red);
    canvas.drawLine(rect.topRight, rect.bottomLeft, red);
    canvas.drawRect(
      Rect.fromCenter(
        center: rect.center,
        width: rect.width,
        height: rect.height * 0.22,
      ),
      Paint()..color = Colors.white,
    );
    canvas.drawRect(
      Rect.fromCenter(
        center: rect.center,
        width: rect.width * 0.22,
        height: rect.height,
      ),
      Paint()..color = Colors.white,
    );
    canvas.drawRect(
      Rect.fromCenter(
        center: rect.center,
        width: rect.width,
        height: rect.height * 0.12,
      ),
      Paint()..color = const Color(0xFFC8102E),
    );
    canvas.drawRect(
      Rect.fromCenter(
        center: rect.center,
        width: rect.width * 0.12,
        height: rect.height,
      ),
      Paint()..color = const Color(0xFFC8102E),
    );
  }

  @override
  bool shouldRepaint(covariant _FlagPainter oldDelegate) =>
      oldDelegate.code != code;
}
