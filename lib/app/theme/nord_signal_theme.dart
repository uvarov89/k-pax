import 'package:flutter/material.dart';

import 'package:pulse_vpn/core/models/app_settings.dart';

/// Nord Signal visual system from Variant A mockups.
abstract final class NordColors {
  static const bgTop = Color(0xFF0F172A);
  static const bgBottom = Color(0xFF1E293B);
  static const surface = Color(0xFF243044);
  static const surfaceElevated = Color(0xFF2C3B52);
  static const border = Color(0xFF3A4A63);
  static const textPrimary = Color(0xFFF1F5F9);
  static const textSecondary = Color(0xFF94A3B8);
  static const textMuted = Color(0xFF64748B);
  static const accent = Color(0xFF10B981);
  static const accentDim = Color(0xFF059669);
  static const connecting = Color(0xFFF59E0B);
  static const disconnectFill = Color(0xFF334155);

  static const lightBgTop = Color(0xFFF8FAFC);
  static const lightBgBottom = Color(0xFFE2E8F0);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceElevated = Color(0xFFF1F5F9);
  static const lightBorder = Color(0xFFCBD5E1);
  static const lightTextPrimary = Color(0xFF0F172A);
  static const lightTextSecondary = Color(0xFF475569);
  static const lightTextMuted = Color(0xFF64748B);
  static const lightDisconnectFill = Color(0xFFE2E8F0);
}

abstract final class NordSignalTheme {
  static ThemeData get dark {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Roboto',
      colorScheme: const ColorScheme.dark(
        primary: NordColors.accent,
        onPrimary: Colors.white,
        secondary: NordColors.surfaceElevated,
        surface: NordColors.surface,
        onSurface: NordColors.textPrimary,
      ),
      scaffoldBackgroundColor: NordColors.bgTop,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        foregroundColor: NordColors.textPrimary,
      ),
      dividerColor: NordColors.border,
      switchTheme: _switchTheme(dark: true),
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: NordColors.textPrimary,
        displayColor: NordColors.textPrimary,
      ),
    );
  }

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: 'Roboto',
      colorScheme: const ColorScheme.light(
        primary: NordColors.accentDim,
        onPrimary: Colors.white,
        secondary: NordColors.lightSurfaceElevated,
        surface: NordColors.lightSurface,
        onSurface: NordColors.lightTextPrimary,
      ),
      scaffoldBackgroundColor: NordColors.lightBgTop,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        foregroundColor: NordColors.lightTextPrimary,
      ),
      dividerColor: NordColors.lightBorder,
      switchTheme: _switchTheme(dark: false),
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: NordColors.lightTextPrimary,
        displayColor: NordColors.lightTextPrimary,
      ),
    );
  }

  static ThemeData forPreference(AppThemePreference preference) {
    return preference == AppThemePreference.light ? light : dark;
  }

  static SwitchThemeData _switchTheme({required bool dark}) {
    return SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return Colors.white;
        }
        return dark ? NordColors.textSecondary : NordColors.lightTextSecondary;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return NordColors.accent;
        }
        return dark ? NordColors.border : NordColors.lightBorder;
      }),
    );
  }
}

class NordBackground extends StatelessWidget {
  const NordBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? const [NordColors.bgTop, NordColors.bgBottom]
              : const [NordColors.lightBgTop, NordColors.lightBgBottom],
        ),
      ),
      child: child,
    );
  }
}
