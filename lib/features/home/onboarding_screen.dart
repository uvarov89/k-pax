import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:pulse_vpn/app/theme/nord_signal_theme.dart';
import 'package:pulse_vpn/core/services/settings_repository.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  static Future<void> showIfNeeded(BuildContext context) async {
    final seen = await SettingsRepository().loadOnboardingSeen();
    if (seen || !context.mounted) return;
    await Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: true,
        barrierDismissible: false,
        pageBuilder: (_, _, _) => const OnboardingScreen(),
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  Future<void> _finish(BuildContext context) async {
    await SettingsRepository().markOnboardingSeen();
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<VpnController>().strings;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        isDark ? NordColors.textSecondary : NordColors.lightTextSecondary;

    return NordBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
            child: Column(
              children: [
                const Spacer(flex: 2),
                Image.asset(
                  'assets/brand/logo.png',
                  width: 112,
                  height: 112,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 22),
                Text(
                  s.onboardingTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: NordColors.accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'K-Pax',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  s.onboardingBody,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: secondary,
                    height: 1.55,
                    fontSize: 16,
                  ),
                ),
                const Spacer(flex: 3),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => _finish(context),
                    child: Text(s.onboardingCta),
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
