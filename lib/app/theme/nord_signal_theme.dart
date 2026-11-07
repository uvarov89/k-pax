import 'package:flutter/material.dart';

import 'package:pulse_vpn/app/brand/app_brand.dart';
import 'package:pulse_vpn/app/theme/kpax_space_background.dart';
import 'package:pulse_vpn/app/theme/xplm_colors.dart';
import 'package:pulse_vpn/app/theme/xplm_paper_background.dart';
import 'package:pulse_vpn/core/models/app_settings.dart';

/// K-Pax brand palette: deep navy, cyan glow, green signal.
abstract final class NordColors {
  static const bgTop = Color(0xFF070B14);
  static const bgMid = Color(0xFF0E1524);
  static const bgBottom = Color(0xFF121A2C);
  static const surface = Color(0xFF172033);
  static const surfaceElevated = Color(0xFF1E2A40);
  static const border = Color(0xFF2C3A52);
  static const borderGlow = Color(0xFF3D5578);
  static const textPrimary = Color(0xFFE8EEF7);
  static const textSecondary = Color(0xFFA8B4C8);
  static const textMuted = Color(0xFF6E7C94);
  static const cyan = Color(0xFF6EB6FF);
  static const cyanDim = Color(0xFF3D8FE0);
  static const accent = Color(0xFF3DDC97);
  static const accentDim = Color(0xFF2BB87A);
  static const connecting = Color(0xFFF0B429);
  static const disconnectFill = Color(0xFF1A2436);
  static const danger = Color(0xFFEF6B7B);

  static const lightBgTop = Color(0xFFF5F8FC);
  static const lightBgBottom = Color(0xFFE4EBF5);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceElevated = Color(0xFFF0F4FA);
  static const lightBorder = Color(0xFFCDD7E6);
  static const lightTextPrimary = Color(0xFF0E1524);
  static const lightTextSecondary = Color(0xFF40506A);
  static const lightTextMuted = Color(0xFF6E7C94);
  static const lightDisconnectFill = Color(0xFFE4EBF5);
}

abstract final class NordSignalTheme {
  static ThemeData get dark {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Roboto',
      colorScheme: const ColorScheme.dark(
        primary: NordColors.accent,
        onPrimary: Color(0xFF062216),
        secondary: NordColors.cyan,
        onSecondary: Color(0xFF041018),
        surface: NordColors.surface,
        onSurface: NordColors.textPrimary,
        error: NordColors.danger,
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
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: NordColors.accent,
          foregroundColor: const Color(0xFF062216),
          disabledBackgroundColor: NordColors.border,
          disabledForegroundColor: NordColors.textMuted,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: NordColors.bgTop,
        hintStyle: const TextStyle(color: NordColors.textMuted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: NordColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: NordColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: NordColors.cyan, width: 1.4),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: NordColors.surfaceElevated,
        contentTextStyle: const TextStyle(color: NordColors.textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    return base.copyWith(
      textTheme: _readableText(base.textTheme, NordColors.textPrimary),
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
        secondary: NordColors.cyanDim,
        surface: NordColors.lightSurface,
        onSurface: NordColors.lightTextPrimary,
        error: NordColors.danger,
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
      textTheme: _readableText(base.textTheme, NordColors.lightTextPrimary),
    );
  }

  static ThemeData get xplmLight {
    // Kept name for call sites; X-Plm UI is dark neon (flashy refs).
    final base = ThemeData(
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      brightness: Brightness.dark,
      fontFamily: 'XplmArial',
      colorScheme: const ColorScheme.dark(
        primary: XplmColors.accent,
        onPrimary: XplmColors.onAccent,
        secondary: XplmColors.cyan,
        surface: XplmColors.surface,
        onSurface: XplmColors.ink,
        error: XplmColors.danger,
      ),
      scaffoldBackgroundColor: XplmColors.paper,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        foregroundColor: XplmColors.ink,
      ),
      dividerColor: XplmColors.line,
      dividerTheme: const DividerThemeData(
        color: XplmColors.line,
        thickness: 1,
        space: 1,
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: XplmColors.cyan,
          side: const BorderSide(color: XplmColors.lineStrong),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          textStyle: const TextStyle(fontFamily: 'XplmArial', fontSize: 14),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: XplmColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: XplmColors.line),
        ),
        titleTextStyle: const TextStyle(
          fontFamily: 'XplmArial',
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: XplmColors.ink,
        ),
        contentTextStyle: const TextStyle(
          fontFamily: 'XplmArial',
          fontSize: 14,
          color: XplmColors.ink2,
          height: 1.4,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: XplmColors.paper,
        modalBackgroundColor: XplmColors.paper,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: XplmColors.cyan,
        titleTextStyle: TextStyle(
          fontFamily: 'XplmArial',
          fontSize: 14,
          color: XplmColors.ink,
        ),
        subtitleTextStyle: TextStyle(
          fontFamily: 'XplmArial',
          fontSize: 12,
          color: XplmColors.ink2,
        ),
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return XplmColors.ink2;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return XplmColors.accent;
          return XplmColors.lineStrong;
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: XplmColors.accent,
          foregroundColor: XplmColors.onAccent,
          disabledBackgroundColor: XplmColors.lineStrong,
          disabledForegroundColor: XplmColors.ink3,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: XplmColors.surfaceElevated,
        hintStyle: const TextStyle(color: XplmColors.ink3),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: XplmColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: XplmColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: XplmColors.cyan, width: 1.4),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: XplmColors.surfaceElevated,
        contentTextStyle: const TextStyle(color: XplmColors.ink),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
    return base.copyWith(
      textTheme: _readableText(base.textTheme, XplmColors.ink),
    );
  }

  static ThemeData forPreference(AppThemePreference preference) {
    if (AppBrand.current.isXplm) return xplmLight;
    return preference == AppThemePreference.light ? light : dark;
  }

  static TextTheme _readableText(TextTheme theme, Color color) {
    final applied = theme.apply(bodyColor: color, displayColor: color);
    return applied.copyWith(
      bodyLarge: applied.bodyLarge?.copyWith(height: 1.55),
      bodyMedium: applied.bodyMedium?.copyWith(height: 1.55),
      bodySmall: applied.bodySmall?.copyWith(height: 1.5),
    );
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
    if (AppBrand.current.isXplm) {
      return XplmPaperBackground(child: child);
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (!isDark) {
      return DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [NordColors.lightBgTop, NordColors.lightBgBottom],
          ),
        ),
        child: child,
      );
    }
    return KpaxSpaceBackground(child: child);
  }
}

class KpaxCard extends StatelessWidget {
  const KpaxCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    this.onTap,
    this.glow = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final xplm = AppBrand.current.isXplm;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(xplm ? 18 : 16);
    final surface = xplm
        ? XplmColors.surface.withValues(alpha: 0.9)
        : (isDark ? NordColors.surface : NordColors.lightSurface);
    final border = xplm
        ? (glow
              ? XplmColors.cyan.withValues(alpha: 0.7)
              : XplmColors.cyan.withValues(alpha: 0.28))
        : (glow
              ? NordColors.cyan.withValues(alpha: 0.35)
              : (isDark ? NordColors.border : NordColors.lightBorder));
    final box = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        color: xplm ? surface : surface.withValues(alpha: isDark ? 0.92 : 0.96),
        border: Border.all(color: border, width: xplm ? (glow ? 1.5 : 1.2) : 1),
        boxShadow: [
          if (xplm)
            BoxShadow(
              color: XplmColors.cyan.withValues(alpha: glow ? 0.35 : 0.14),
              blurRadius: glow ? 30 : 20,
              spreadRadius: glow ? 1 : 0,
            ),
          if (glow && isDark && !xplm)
            BoxShadow(
              color: NordColors.cyan.withValues(alpha: 0.12),
              blurRadius: 24,
              spreadRadius: 0,
            ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return box;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: radius, onTap: onTap, child: box),
    );
  }
}
