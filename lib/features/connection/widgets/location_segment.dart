import 'package:flutter/material.dart';

import 'package:pulse_vpn/core/models/connection_models.dart';
import 'package:pulse_vpn/app/theme/nord_signal_theme.dart';

class LocationSegment extends StatelessWidget {
  const LocationSegment({
    super.key,
    required this.mode,
    required this.onChanged,
    required this.autoLabel,
    required this.countryLabel,
  });

  final LocationMode mode;
  final ValueChanged<LocationMode> onChanged;
  final String autoLabel;
  final String countryLabel;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: (isDark ? NordColors.surface : NordColors.lightSurface)
            .withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? NordColors.border : NordColors.lightBorder,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Chip(
              label: autoLabel,
              selected: mode == LocationMode.auto,
              onTap: () => onChanged(LocationMode.auto),
            ),
          ),
          Expanded(
            child: _Chip(
              label: countryLabel,
              selected: mode == LocationMode.country,
              onTap: () => onChanged(LocationMode.country),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? selectedBg : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? selectedFg : idleFg,
            ),
          ),
        ),
      ),
    );
  }
}
