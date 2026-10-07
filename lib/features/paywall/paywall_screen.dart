import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:pulse_vpn/app/theme/nord_signal_theme.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';

class PaywallScreen extends StatelessWidget {
  const PaywallScreen({super.key, this.fromExpired = false});

  final bool fromExpired;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VpnController>();
    final s = controller.strings;
    final account = controller.account;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? NordColors.textMuted : NordColors.lightTextMuted;
    final secondary =
        isDark ? NordColors.textSecondary : NordColors.lightTextSecondary;
    final surface = isDark ? NordColors.surface : NordColors.lightSurface;
    final title = account.isExpired || fromExpired ? s.paywallTitle : s.choosePlan;

    return NordBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(s.subscription),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            ClipOval(
              child: Image.asset(
                'assets/brand/logo.png',
                width: 88,
                height: 88,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(s.paywallSubtitle, style: TextStyle(color: secondary, height: 1.35)),
            if (account.hasAccess) ...[
              const SizedBox(height: 12),
              Text(
                '${s.planName} · ${s.daysLeft(account.daysRemaining)}',
                style: const TextStyle(
                  color: NordColors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: surface.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: NordColors.accent, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.planName,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    s.paywallSubtitle,
                    style: const TextStyle(height: 1.35),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              s.paymentStubNote,
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> openPaywall(
  BuildContext context, {
  bool fromExpired = false,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PaywallScreen(fromExpired: fromExpired),
      fullscreenDialog: true,
    ),
  );
}
