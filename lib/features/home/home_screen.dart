import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:pulse_vpn/core/state/vpn_controller.dart';
import 'package:pulse_vpn/features/settings/windows_update_prompt.dart';
import 'package:pulse_vpn/app/theme/nord_signal_theme.dart';
import 'package:pulse_vpn/features/connection/widgets/connect_button.dart';
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      checkForWindowsUpdate(context, manual: false);
    });
  }

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
    if (!ok && mounted && controller.isKPaxSubscription) {
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
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              children: [
                Row(
                  children: [
                    Image.asset(
                      'assets/brand/logo.png',
                      width: 36,
                      height: 36,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        s.appName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    if (!controller.needsLink &&
                        (controller.hasExpiry || !account.hasAccess)) ...[
                      _PlanBadge(
                        label: account.hasAccess
                            ? s.daysLeft(account.daysRemaining)
                            : s.planExpired,
                        warning: !account.hasAccess || account.daysRemaining <= 3,
                        onTap: _openProfile,
                      ),
                      const SizedBox(width: 4),
                    ],
                    IconButton(
                      tooltip: s.account,
                      onPressed: _openProfile,
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
                Expanded(
                  child: controller.linkState == SubscriptionLinkState.loading
                      ? const Center(child: CircularProgressIndicator())
                      : CustomScrollView(
                          slivers: [
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: Column(
                                children: [
                                  const SizedBox(height: 20),
                                  if (controller.needsLink)
                                    _SubscriptionBanner(
                                      text: s.openProfileForAccess,
                                      actionLabel: s.account,
                                      onAction: _openProfile,
                                    )
                                  else if (!account.hasAccess && controller.isKPaxSubscription)
                                    _SubscriptionBanner(
                                      text: s.paywallTitle,
                                      actionLabel: s.seePlans,
                                      danger: true,
                                      onAction: () => openPaywall(context, fromExpired: true),
                                    )
                                  else if (!account.hasAccess)
                                    _SubscriptionBanner(
                                      text: s.providerExpired,
                                      actionLabel: s.account,
                                      danger: true,
                                      onAction: _openProfile,
                                    ),
                                  const Spacer(),
                                  Text(
                                    controller.statusLine,
                                    textAlign: TextAlign.center,
                                    maxLines: 4,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: controller.isConnected
                                          ? NordColors.accent
                                          : secondary,
                                    ),
                                  ),
                                  if (controller.isConnected) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      controller.sessionLabel,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: muted,
                                        fontFeatures: const [FontFeature.tabularFigures()],
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '↓ ${_formatRate(controller.downloadBytesPerSec)}   ↑ ${_formatRate(controller.uploadBytesPerSec)}',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: muted,
                                        fontFeatures: const [FontFeature.tabularFigures()],
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 24),
                                  Center(
                                    child: ConnectButton(
                                      diameter: MediaQuery.sizeOf(context).width < 360
                                          ? 148
                                          : 168,
                                      state: controller.connectionState,
                                      connectLabel: s.connect,
                                      disconnectLabel: s.disconnect,
                                      connectingLabel: s.connecting,
                                      disconnectingLabel: s.disconnecting,
                                      retryLabel: s.retry,
                                      onPressed: () => _onConnectPressed(controller),
                                    ),
                                  ),
                                  const Spacer(),
                                  _ServerRow(
                                    title: s.location,
                                    value: controller.selectedLocation.isAuto
                                        ? s.auto
                                        : controller.selectedLocation.nameRu,
                                    hint: controller.selectedLocation.isAuto
                                        ? s.bestServerAuto
                                        : null,
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) => const CountryPickerScreen(),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
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
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 108),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: warning ? NordColors.connecting : NordColors.accent,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ServerRow extends StatelessWidget {
  const _ServerRow({
    required this.title,
    required this.value,
    required this.onTap,
    this.hint,
  });

  final String title;
  final String value;
  final String? hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? NordColors.textMuted : NordColors.lightTextMuted;
    return Material(
      color: (isDark ? NordColors.surface : NordColors.lightSurface).withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isDark ? NordColors.border : NordColors.lightBorder),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(color: muted, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    if (hint != null) ...[
                      const SizedBox(height: 2),
                      Text(hint!, style: TextStyle(color: muted, fontSize: 13)),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: muted),
            ],
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
      padding: const EdgeInsets.all(14),
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
              style: const TextStyle(fontSize: 13, height: 1.45, fontWeight: FontWeight.w500),
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

String _formatRate(int bytesPerSec) {
  if (bytesPerSec < 1024) return '$bytesPerSec Б/с';
  if (bytesPerSec < 1024 * 1024) {
    return '${(bytesPerSec / 1024).toStringAsFixed(0)} КБ/с';
  }
  return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} МБ/с';
}
