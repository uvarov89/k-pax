import 'dart:math' as math;

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
    final xplm = AppBrand.current.isXplm;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final connected = state == VpnConnectionState.connected;
    final busy = state == VpnConnectionState.connecting ||
        state == VpnConnectionState.disconnecting;

    final Color ringColor;
    final Color fillColor;
    final Color glowColor;
    final String label;
    final List<Color>? fillGradient;

    switch (state) {
      case VpnConnectionState.connected:
        if (xplm) {
          ringColor = XplmColors.cyan;
          fillColor = XplmColors.accent;
          glowColor = XplmColors.cyan;
          fillGradient = const [
            XplmColors.neonCore,
            XplmColors.accent,
            XplmColors.neonDeep,
          ];
        } else {
          ringColor = NordColors.accent;
          fillColor = NordColors.accentDim;
          glowColor = ringColor;
          fillGradient = const [Color(0xFF4AE8A8), NordColors.accentDim];
        }
        label = disconnectLabel;
      case VpnConnectionState.connecting:
        ringColor = xplm ? XplmColors.cyan : NordColors.connecting;
        fillColor = xplm
            ? XplmColors.disconnectFill
            : (isDark
                ? NordColors.disconnectFill
                : NordColors.lightDisconnectFill);
        glowColor = ringColor;
        fillGradient = null;
        label = connectingLabel;
      case VpnConnectionState.disconnecting:
        ringColor = xplm ? XplmColors.cyan : NordColors.connecting;
        fillColor = xplm
            ? XplmColors.disconnectFill
            : (isDark
                ? NordColors.disconnectFill
                : NordColors.lightDisconnectFill);
        glowColor = ringColor;
        fillGradient = null;
        label = disconnectingLabel;
      case VpnConnectionState.error:
        ringColor = xplm ? XplmColors.danger : NordColors.danger;
        fillColor = xplm
            ? XplmColors.disconnectFill
            : (isDark
                ? NordColors.disconnectFill
                : NordColors.lightDisconnectFill);
        glowColor = ringColor;
        fillGradient = null;
        label = retryLabel;
      case VpnConnectionState.disconnected:
        ringColor = xplm
            ? XplmColors.cyan
            : (isDark ? NordColors.cyan : NordColors.cyanDim);
        fillColor = xplm
            ? XplmColors.disconnectFill
            : (isDark
                ? NordColors.disconnectFill
                : NordColors.lightDisconnectFill);
        glowColor = ringColor;
        fillGradient = xplm
            ? const [Color(0xFF1A3A6A), XplmColors.disconnectFill]
            : null;
        label = connectLabel;
    }

    final labelColor = connected
        ? (xplm ? XplmColors.onNeon : Colors.white)
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
            clipBehavior: Clip.none,
            children: [
              if (xplm)
                _XplmHalo(
                  diameter: diameter,
                  color: connected ? XplmColors.neon : XplmColors.cyan,
                  active: connected || busy,
                ),
              if (busy) _OrbitRing(diameter: diameter, color: ringColor),
              AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                width: diameter,
                height: diameter,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: fillColor,
                  border: Border.all(
                    color: ringColor,
                    width: connected || xplm ? 3.5 : 2.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: glowColor.withValues(
                        alpha: connected || xplm ? 0.45 : 0.22,
                      ),
                      blurRadius: connected || xplm ? 40 : 28,
                      spreadRadius: connected || xplm ? 5 : 1,
                    ),
                    if (connected || isDark || xplm)
                      BoxShadow(
                        color: glowColor.withValues(
                          alpha: connected || xplm ? 0.22 : 0.12,
                        ),
                        blurRadius: connected || xplm ? 80 : 60,
                        spreadRadius: connected || xplm ? 12 : 8,
                      ),
                  ],
                  gradient: fillGradient == null
                      ? null
                      : LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: fillGradient,
                        ),
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
                              color: connected
                                  ? (xplm ? XplmColors.onNeon : Colors.white)
                                  : ringColor,
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

/// Soft concentric rings behind the X-Plm connect disc (ref radar look).
class _XplmHalo extends StatelessWidget {
  const _XplmHalo({
    required this.diameter,
    required this.color,
    required this.active,
  });

  final double diameter;
  final Color color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.square(diameter * 1.55),
        painter: _HaloPainter(color: color, active: active),
      ),
    );
  }
}

class _HaloPainter extends CustomPainter {
  _HaloPainter({required this.color, required this.active});

  final Color color;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final base = size.shortestSide / 2;
    final rings = <(double, double, double)>[
      (0.72, active ? 0.22 : 0.12, 1.4),
      (0.88, active ? 0.16 : 0.08, 1.1),
      (1.0, active ? 0.10 : 0.05, 1.0),
    ];
    for (final ring in rings) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ring.$3
        ..color = color.withValues(alpha: ring.$2);
      canvas.drawCircle(center, base * ring.$1, paint);
    }
    if (active) {
      final dash = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = color.withValues(alpha: 0.28);
      const count = 42;
      final r = base * 0.95;
      for (var i = 0; i < count; i++) {
        if (i.isOdd) continue;
        final a0 = (i / count) * math.pi * 2;
        final a1 = ((i + 0.55) / count) * math.pi * 2;
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: r),
          a0,
          a1 - a0,
          false,
          dash,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HaloPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.active != active;
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
