import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:pulse_vpn/app/brand/app_brand.dart';
import 'package:pulse_vpn/app/theme/nord_signal_theme.dart';
import 'package:pulse_vpn/app/theme/xplm_colors.dart';
import 'package:pulse_vpn/core/models/connection_models.dart';

class ConnectButton extends StatelessWidget {
  const ConnectButton({
    super.key,
    required this.state,
    required this.onPressed,
    required this.connectLabel,
    required this.disconnectLabel,
    required this.connectingLabel,
    required this.disconnectingLabel,
    required this.retryLabel,
    this.diameter = 188,
  });

  final VpnConnectionState state;
  final VoidCallback? onPressed;
  final String connectLabel;
  final String disconnectLabel;
  final String connectingLabel;
  final String disconnectingLabel;
  final String retryLabel;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    if (AppBrand.current.isXplm && state == VpnConnectionState.connected) {
      return _XplmSunConnect(
        diameter: diameter,
        label: disconnectLabel,
        onPressed: onPressed,
      );
    }
    return _ClassicConnect(
      state: state,
      onPressed: onPressed,
      connectLabel: connectLabel,
      disconnectLabel: disconnectLabel,
      connectingLabel: connectingLabel,
      disconnectingLabel: disconnectingLabel,
      retryLabel: retryLabel,
      diameter: diameter,
    );
  }
}

/// Living sun for X-Plm connected state: pulsing corona, rotating rays, hot core.
class _XplmSunConnect extends StatefulWidget {
  const _XplmSunConnect({
    required this.diameter,
    required this.label,
    required this.onPressed,
  });

  final double diameter;
  final String label;
  final VoidCallback? onPressed;

  @override
  State<_XplmSunConnect> createState() => _XplmSunConnectState();
}

class _XplmSunConnectState extends State<_XplmSunConnect>
    with TickerProviderStateMixin {
  late final AnimationController _pulse;
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.diameter;
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: SizedBox(
          width: d * 1.45,
          height: d * 1.45,
          child: AnimatedBuilder(
            animation: Listenable.merge([_pulse, _spin]),
            builder: (context, _) {
              final breath = Curves.easeInOut.transform(_pulse.value);
              return CustomPaint(
                painter: _SunPainter(
                  spin: _spin.value * math.pi * 2,
                  breath: breath,
                  disc: d,
                ),
                child: Center(
                  child: SizedBox(
                    width: d,
                    height: d,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.power_settings_new_rounded,
                          size: 40,
                          color: XplmColors.onSun.withValues(alpha: 0.92),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.label,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                            color: XplmColors.onSun.withValues(alpha: 0.95),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SunPainter extends CustomPainter {
  _SunPainter({
    required this.spin,
    required this.breath,
    required this.disc,
  });

  final double spin;
  final double breath;
  final double disc;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = disc / 2;
    final glowBoost = 0.75 + breath * 0.45;

    // Soft outer corona layers.
    for (final layer in <(double, Color, double)>[
      (radius * 1.85, XplmColors.sunHot.withValues(alpha: 0.10 * glowBoost), 28),
      (radius * 1.55, XplmColors.sunMid.withValues(alpha: 0.18 * glowBoost), 18),
      (radius * 1.28, XplmColors.sunRim.withValues(alpha: 0.28 * glowBoost), 10),
      (radius * 1.12, XplmColors.sunCorona.withValues(alpha: 0.35 * glowBoost), 4),
    ]) {
      final paint = Paint()
        ..color = layer.$2
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, layer.$3);
      canvas.drawCircle(center, layer.$1, paint);
    }

    // Rotating ray flares.
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(spin);
    final rayPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(-radius * 1.6, 0),
        Offset(radius * 1.6, 0),
        [
          const Color(0x00FFCC33),
          XplmColors.sunHot.withValues(alpha: 0.22 + breath * 0.12),
          XplmColors.sunCore.withValues(alpha: 0.35 + breath * 0.15),
          XplmColors.sunHot.withValues(alpha: 0.22 + breath * 0.12),
          const Color(0x00FFCC33),
        ],
        const [0.0, 0.28, 0.5, 0.72, 1.0],
      );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: radius * 3.2,
        height: radius * 0.22 + breath * 4,
      ),
      rayPaint,
    );
    canvas.rotate(math.pi / 2.4);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: radius * 2.7,
        height: radius * 0.14 + breath * 3,
      ),
      rayPaint,
    );
    canvas.restore();

    // Plasma disc.
    final discPaint = Paint()
      ..shader = ui.Gradient.radial(
        center.translate(-radius * 0.18, -radius * 0.22),
        radius * 1.15,
        [
          XplmColors.sunCore,
          Color.lerp(XplmColors.sunHot, XplmColors.sunMid, breath)!,
          XplmColors.sunMid,
          XplmColors.sunRim,
        ],
        const [0.0, 0.35, 0.72, 1.0],
      );
    canvas.drawCircle(center, radius, discPaint);

    // Hot rim ring.
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2 + breath * 1.2
      ..color = XplmColors.sunCorona.withValues(alpha: 0.85)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2);
    canvas.drawCircle(center, radius - 1.5, rim);

    // Subtle surface grain (static speckles for depth).
    final speck = Paint()..color = const Color(0x33FFFFFF);
    final dark = Paint()..color = const Color(0x22C45A12);
    final rnd = math.Random(7);
    for (var i = 0; i < 42; i++) {
      final a = rnd.nextDouble() * math.pi * 2;
      final r = rnd.nextDouble() * radius * 0.78;
      final p = center + Offset(math.cos(a) * r, math.sin(a) * r);
      canvas.drawCircle(p, 1.1 + rnd.nextDouble() * 1.6, i.isEven ? speck : dark);
    }

    // Moving highlight.
    final highlight = Paint()
      ..shader = ui.Gradient.radial(
        center.translate(-radius * 0.28, -radius * (0.30 - breath * 0.04)),
        radius * 0.42,
        [
          const Color(0xAAFFFFFF),
          const Color(0x00FFFFFF),
        ],
      );
    canvas.drawCircle(
      center.translate(-radius * 0.28, -radius * 0.28),
      radius * 0.38,
      highlight,
    );
  }

  @override
  bool shouldRepaint(covariant _SunPainter oldDelegate) =>
      oldDelegate.spin != spin ||
      oldDelegate.breath != breath ||
      oldDelegate.disc != disc;
}

class _ClassicConnect extends StatelessWidget {
  const _ClassicConnect({
    required this.state,
    required this.onPressed,
    required this.connectLabel,
    required this.disconnectLabel,
    required this.connectingLabel,
    required this.disconnectingLabel,
    required this.retryLabel,
    required this.diameter,
  });

  final VpnConnectionState state;
  final VoidCallback? onPressed;
  final String connectLabel;
  final String disconnectLabel;
  final String connectingLabel;
  final String disconnectingLabel;
  final String retryLabel;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    final xplm = AppBrand.current.isXplm;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final connected = state == VpnConnectionState.connected;
    final busy = state == VpnConnectionState.connecting ||
        state == VpnConnectionState.disconnecting;

    final Color ringColor;
    final Color fillColor;
    final Color glowColor;
    final String label;

    switch (state) {
      case VpnConnectionState.connected:
        ringColor = NordColors.accent;
        fillColor = NordColors.accentDim;
        glowColor = ringColor;
        label = disconnectLabel;
      case VpnConnectionState.connecting:
        ringColor = xplm ? XplmColors.connecting : NordColors.connecting;
        fillColor = xplm
            ? XplmColors.disconnectFill
            : (isDark
                ? NordColors.disconnectFill
                : NordColors.lightDisconnectFill);
        glowColor = ringColor;
        label = connectingLabel;
      case VpnConnectionState.disconnecting:
        ringColor = xplm ? XplmColors.connecting : NordColors.connecting;
        fillColor = xplm
            ? XplmColors.disconnectFill
            : (isDark
                ? NordColors.disconnectFill
                : NordColors.lightDisconnectFill);
        glowColor = ringColor;
        label = disconnectingLabel;
      case VpnConnectionState.error:
        ringColor = xplm ? XplmColors.danger : NordColors.danger;
        fillColor = xplm
            ? XplmColors.disconnectFill
            : (isDark
                ? NordColors.disconnectFill
                : NordColors.lightDisconnectFill);
        glowColor = ringColor;
        label = retryLabel;
      case VpnConnectionState.disconnected:
        ringColor = xplm
            ? XplmColors.accent
            : (isDark ? NordColors.cyan : NordColors.cyanDim);
        fillColor = xplm
            ? XplmColors.disconnectFill
            : (isDark
                ? NordColors.disconnectFill
                : NordColors.lightDisconnectFill);
        glowColor = ringColor;
        label = connectLabel;
    }

    final labelColor = connected
        ? Colors.white
        : (xplm
            ? XplmColors.ink
            : (isDark
                ? NordColors.textPrimary
                : NordColors.lightTextPrimary));

    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: busy ? null : onPressed,
        child: SizedBox(
          width: diameter,
          height: diameter,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (busy)
                _OrbitRing(diameter: diameter, color: ringColor),
              AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                width: diameter,
                height: diameter,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: fillColor,
                  border: Border.all(
                    color: ringColor,
                    width: connected ? 4 : 2.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: glowColor.withValues(alpha: connected ? 0.38 : 0.22),
                      blurRadius: connected ? 36 : 28,
                      spreadRadius: connected ? 4 : 1,
                    ),
                    if (isDark)
                      BoxShadow(
                        color: glowColor.withValues(alpha: 0.12),
                        blurRadius: 60,
                        spreadRadius: 8,
                      ),
                  ],
                  gradient: connected
                      ? const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF4AE8A8), NordColors.accentDim],
                        )
                      : null,
                ),
                child: Center(
                  child: busy
                      ? Text(
                          label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: labelColor,
                            letterSpacing: 0.3,
                          ),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.power_settings_new_rounded,
                              size: 40,
                              color: connected ? Colors.white : ringColor,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              label,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: labelColor,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrbitRing extends StatefulWidget {
  const _OrbitRing({required this.diameter, required this.color});

  final double diameter;
  final Color color;

  @override
  State<_OrbitRing> createState() => _OrbitRingState();
}

class _OrbitRingState extends State<_OrbitRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Transform.rotate(
          angle: _controller.value * math.pi * 2,
          child: CustomPaint(
            size: Size.square(widget.diameter),
            painter: _OrbitPainter(color: widget.color),
          ),
        );
      },
    );
  }
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 3;
    final paint = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 1.15,
      false,
      paint,
    );
    final soft = Paint()
      ..color = color.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, soft);
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter oldDelegate) =>
      oldDelegate.color != color;
}
