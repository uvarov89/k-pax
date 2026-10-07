import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:pulse_vpn/core/models/connection_models.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';
import 'package:pulse_vpn/app/theme/nord_signal_theme.dart';
import 'package:pulse_vpn/features/connection/widgets/connect_button.dart';
import 'package:pulse_vpn/features/connection/widgets/location_segment.dart';
import 'package:pulse_vpn/features/account/account_screen.dart';
import 'package:pulse_vpn/features/locations/country_picker_screen.dart';
import 'package:pulse_vpn/features/paywall/paywall_screen.dart';
import 'package:pulse_vpn/features/settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<void> _openProfile() {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const AccountScreen(),
      ),
    );
  }

  Future<void> _onConnectPressed(VpnController controller) async {
    if (controller.needsLink) {
      await _openProfile();
      return;
    }
    if (controller.isConnected || controller.isBusy) {
      await controller.toggleConnection();
      return;
    }
    final ok = await controller.connect();
    if (!ok && mounted) {
      await openPaywall(context, fromExpired: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VpnController>();
    final s = controller.strings;
    final account = controller.account;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? NordColors.textMuted : NordColors.lightTextMuted;
    final secondary =
        isDark ? NordColors.textSecondary : NordColors.lightTextSecondary;

    return NordBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Row(
                  children: [
                    ClipOval(
                      child: Image.asset(
                        'assets/brand/logo.png',
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      s.appName,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (!controller.needsLink)
                      _PlanBadge(
                      label: account.hasAccess
                          ? s.daysLeft(account.daysRemaining)
                          : s.planExpired,
                      warning: !account.hasAccess || account.daysRemaining <= 3,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const AccountScreen(),
                        ),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: s.account,
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const AccountScreen(),
                          ),
                        );
                      },
                      icon: Icon(Icons.person_outline, color: secondary),
                    ),
                    IconButton(
                      tooltip: s.settings,
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const SettingsScreen(),
                          ),
                        );
                      },
                      icon: Icon(Icons.settings_outlined, color: secondary),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (controller.linkState == SubscriptionLinkState.loading)
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                if (controller.needsLink) ...[
                  const SizedBox(height: 12),
                  _SubscriptionBanner(
                    text: s.openProfileForAccess,
                    actionLabel: s.account,
                    onAction: _openProfile,
                  ),
                ] else if (!account.hasAccess) ...[
                  const SizedBox(height: 12),
                  _SubscriptionBanner(
                    text: s.paywallTitle,
                    actionLabel: s.seePlans,
                    danger: true,
                    onAction: () => openPaywall(context, fromExpired: true),
                  ),
                ],
                const Spacer(flex: 2),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: Text(
                    controller.statusLine,
                    key: ValueKey(controller.statusLine),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: controller.isConnected
                          ? NordColors.accent
                          : secondary,
                    ),
                  ),
                ),
                if (controller.isConnected) ...[
                  const SizedBox(height: 8),
                  Text(
                    controller.sessionLabel,
                    style: TextStyle(
                      fontSize: 14,
                      color: muted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                ConnectButton(
                  state: controller.connectionState,
                  connectLabel: s.connect,
                  disconnectLabel: s.disconnect,
                  connectingLabel: s.connecting,
                  disconnectingLabel: s.disconnecting,
                  retryLabel: s.retry,
                  onPressed: () => _onConnectPressed(controller),
                ),
                const Spacer(flex: 2),
                LocationSegment(
                  mode: controller.locationMode,
                  autoLabel: s.auto,
                  countryLabel: s.country,
                  onChanged: (mode) async {
                    await controller.setLocationMode(mode);
                    if (mode == LocationMode.country && context.mounted) {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const CountryPickerScreen(),
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(height: 10),
                Text(
                  controller.locationMode == LocationMode.auto
                      ? s.bestServerAuto
                      : s.selected(
                          controller.selectedLocation.isAuto
                              ? s.auto
                              : controller.selectedLocation.nameRu,
                        ),
                  style: TextStyle(color: muted, fontSize: 13),
                ),
                const SizedBox(height: 16),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlanBadge extends StatelessWidget {
  const _PlanBadge({
    required this.label,
    required this.onTap,
    this.warning = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: warning
          ? const Color(0xFFB45309).withValues(alpha: 0.25)
          : NordColors.accentDim.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: warning ? NordColors.connecting : NordColors.accent,
            ),
          ),
        ),
      ),
    );
  }
}

class _SubscriptionBanner extends StatelessWidget {
  const _SubscriptionBanner({
    required this.text,
    required this.actionLabel,
    required this.onAction,
    this.danger = false,
  });

  final String text;
  final String actionLabel;
  final VoidCallback onAction;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: danger
            ? const Color(0xFF7F1D1D).withValues(alpha: 0.45)
            : NordColors.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: danger ? const Color(0xFFEF4444) : NordColors.border,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          TextButton(
            onPressed: onAction,
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}
