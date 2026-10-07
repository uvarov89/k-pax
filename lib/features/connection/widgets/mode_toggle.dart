import 'package:flutter/material.dart';

import 'package:pulse_vpn/core/models/connection_models.dart';
import 'package:pulse_vpn/app/theme/nord_signal_theme.dart';

class ModeToggle extends StatelessWidget {
  const ModeToggle({
    super.key,
    required this.mode,
    required this.onChanged,
    required this.simpleLabel,
    required this.proLabel,
  });

  final AppUserMode mode;
  final ValueChanged<AppUserMode> onChanged;
  final String simpleLabel;
  final String proLabel;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: (isDark ? NordColors.surface : NordColors.lightSurface)
            .withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? NordColors.border : NordColors.lightBorder,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Segment(
            label: simpleLabel,
            selected: mode == AppUserMode.simple,
            onTap: () => onChanged(AppUserMode.simple),
          ),
          _Segment(
            label: proLabel,
            selected: mode == AppUserMode.pro,
            onTap: () => onChanged(AppUserMode.pro),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedBg =
        isDark ? NordColors.surfaceElevated : NordColors.lightSurfaceElevated;
    final selectedFg =
        isDark ? NordColors.textPrimary : NordColors.lightTextPrimary;
    final idleFg =
        isDark ? NordColors.textSecondary : NordColors.lightTextSecondary;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? selectedBg : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? selectedFg : idleFg,
          ),
        ),
      ),
    );
  }
}
