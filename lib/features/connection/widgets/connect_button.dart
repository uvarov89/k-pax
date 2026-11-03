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

    switch (state) {
      case VpnConnectionState.connected:
        ringColor = xplm ? XplmColors.accent : NordColors.accent;
        fillColor = xplm ? XplmColors.accentHover : NordColors.accentDim;
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
        ? (xplm ? XplmColors.onAccent : Colors.white)
        : (xplm
            ? XplmColors.ink
            : (isDark ? NordColors.textPrimary : NordColors.lightTextPrimary));

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
                _OrbitRing(
                  diameter: diameter,
                  color: ringColor,
                ),
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
