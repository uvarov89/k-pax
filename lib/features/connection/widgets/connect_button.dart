import 'package:flutter/material.dart';

import 'package:pulse_vpn/core/models/connection_models.dart';
import 'package:pulse_vpn/app/theme/nord_signal_theme.dart';

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final connected = state == VpnConnectionState.connected;
    final busy = state == VpnConnectionState.connecting ||
        state == VpnConnectionState.disconnecting;

    final Color ringColor;
    final Color fillColor;
    final String label;

    switch (state) {
      case VpnConnectionState.connected:
        ringColor = NordColors.accent;
        fillColor = NordColors.accentDim;
        label = disconnectLabel;
      case VpnConnectionState.connecting:
        ringColor = NordColors.connecting;
        fillColor = isDark
            ? NordColors.disconnectFill
            : NordColors.lightDisconnectFill;
        label = connectingLabel;
      case VpnConnectionState.disconnecting:
        ringColor = NordColors.connecting;
        fillColor = isDark
            ? NordColors.disconnectFill
            : NordColors.lightDisconnectFill;
        label = disconnectingLabel;
      case VpnConnectionState.error:
        ringColor = const Color(0xFFEF4444);
        fillColor = isDark
            ? NordColors.disconnectFill
            : NordColors.lightDisconnectFill;
        label = retryLabel;
      case VpnConnectionState.disconnected:
        ringColor = isDark ? NordColors.border : NordColors.lightBorder;
        fillColor = isDark
            ? NordColors.disconnectFill
            : NordColors.lightDisconnectFill;
        label = connectLabel;
    }

    final labelColor =
        isDark ? NordColors.textPrimary : NordColors.lightTextPrimary;

    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: busy ? null : onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          width: diameter,
          height: diameter,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: fillColor,
            border: Border.all(color: ringColor, width: connected ? 4 : 2),
            boxShadow: connected
                ? [
                    BoxShadow(
                      color: NordColors.accent.withValues(alpha: 0.28),
                      blurRadius: 28,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: busy
                ? SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: ringColor,
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
                          color: connected ? Colors.white : labelColor,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
