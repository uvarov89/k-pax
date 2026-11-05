import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:pulse_vpn/app/brand/app_brand.dart';
import 'package:pulse_vpn/app/brand/brand_logo.dart';
import 'package:pulse_vpn/app/theme/nord_signal_theme.dart';
import 'package:pulse_vpn/app/theme/xplm_colors.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';
import 'package:pulse_vpn/features/settings/app_update_prompt.dart';
import 'package:pulse_vpn/features/connection/widgets/connect_button.dart';
import 'package:pulse_vpn/features/account/account_screen.dart';
import 'package:pulse_vpn/features/locations/country_picker_screen.dart';
import 'package:pulse_vpn/features/home/onboarding_screen.dart';
import 'package:pulse_vpn/features/home/widgets/xplm_home_layout.dart';
import 'package:pulse_vpn/features/paywall/paywall_screen.dart';
import 'package:pulse_vpn/features/settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.embeddedInShell = false});

  /// When true (X-Plm shell tab), skip outer NordBackground — shell provides it.
  final bool embeddedInShell;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  VpnController? _bound;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await OnboardingScreen.showIfNeeded(context);
      if (!mounted) return;
      checkForAppUpdate(context, manual: false);
      final controller = context.read<VpnController>();
      _bound = controller;
      controller.addListener(_onControllerFlash);
      _onControllerFlash();
    });
  }

  @override
  void dispose() {
    _bound?.removeListener(_onControllerFlash);
    super.dispose();
  }

  void _onControllerFlash() {
    final controller = _bound;
    if (controller == null || !mounted) return;
    final flash = controller.takeUiFlash();
    if (flash == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(flash.message)),
    );
    if (flash.openAccount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_openProfile());
      });
    }
  }

  Future<void> _openProfile() {
    if (widget.embeddedInShell) {
      // Profile tab lives in XplmShell; still allow push for deep-link flashes.
    }
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

  Widget? _xplmBanner(VpnController controller) {
    final s = controller.strings;
    final account = controller.account;
    if (controller.isLoginWaiting) {
      return _SubscriptionBanner(
        text: controller.loginChannel == 'telegram'
            ? s.waitingTelegramConfirm
            : s.waitingEmailConfirm,
        actionLabel: controller.loginChannel == 'telegram' &&
                (controller.loginBotUrl ?? '').isNotEmpty
            ? s.openBotConfirm
            : s.account,
        onAction: () async {
          final bot = controller.loginBotUrl;
          if (controller.loginChannel == 'telegram' &&
              bot != null &&
              bot.isNotEmpty) {
            await launchUrl(
              Uri.parse(bot),
              mode: LaunchMode.externalApplication,
            );
            return;
          }
          await _openProfile();
        },
      );
    }
    if (controller.needsLink) {
      return _SubscriptionBanner(
        text: s.openProfileForAccess,
        actionLabel: s.account,
        onAction: _openProfile,
      );
    }
    if (!account.hasAccess && controller.isKPaxSubscription) {
      return _SubscriptionBanner(
        text: s.paywallTitle,
        actionLabel: s.seePlans,
        danger: true,
        onAction: () => openPaywall(context, fromExpired: true),
      );
    }
    if (!account.hasAccess) {
      return _SubscriptionBanner(
        text: s.providerExpired,
        actionLabel: s.account,
        danger: true,
        onAction: _openProfile,
      );
    }
    if (controller.showRefreshSubscriptionNotice) {
      return _SubscriptionBanner(
        text: s.refreshSubscriptionNotice,
        actionLabel: controller.isRefreshingServers
            ? '…'
            : s.refreshSubscriptionAction,
        onAction: controller.isRefreshingServers
            ? () {}
            : () => controller.refreshSubscriptionFromNotice(),
        onDismiss: () => controller.dismissRefreshSubscriptionNotice(),
        dismissLabel: s.dismissNotice,
      );
    }
    return null;
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

    if (AppBrand.current.isXplm) {
      final body = XplmHomeLayout(
        onConnectPressed: () => _onConnectPressed(controller),
        onOpenProfile: _openProfile,
        topBanner: _xplmBanner(controller),
      );
      if (widget.embeddedInShell) {
        return Scaffold(backgroundColor: Colors.transparent, body: body);
      }
      return NordBackground(
        child: Scaffold(backgroundColor: Colors.transparent, body: body),
      );
    }

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
                    const BrandLogo(size: 36),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.appName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          ),
                          if (AppBrand.current.isXplm)
                            Text(
                              'Premium connection',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: XplmColors.cyan.withValues(alpha: 0.9),
                              ),
                            ),
                        ],
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
                    _HeaderIconButton(
                      tooltip: s.account,
                      icon: Icons.person_outline,
                      color: secondary,
                      onPressed: _openProfile,
                    ),
                    const SizedBox(width: 4),
                    _HeaderIconButton(
                      tooltip: s.settings,
                      icon: Icons.settings_outlined,
                      color: secondary,
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const SettingsScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                Expanded(
                  child: controller.linkState == SubscriptionLinkState.loading &&
                          !controller.isLoginWaiting &&
                          controller.profile == null
                      ? const Center(child: CircularProgressIndicator())
                      : CustomScrollView(
                          slivers: [
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: Column(
                                children: [
                                  const SizedBox(height: 20),
                                  if (controller.isLoginWaiting)
                                    _SubscriptionBanner(
                                      text: controller.loginChannel == 'telegram'
                                          ? s.waitingTelegramConfirm
                                          : s.waitingEmailConfirm,
                                      actionLabel: controller.loginChannel == 'telegram' &&
                                              (controller.loginBotUrl ?? '').isNotEmpty
                                          ? s.openBotConfirm
                                          : s.account,
                                      onAction: () async {
                                        final bot = controller.loginBotUrl;
                                        if (controller.loginChannel == 'telegram' &&
                                            bot != null &&
                                            bot.isNotEmpty) {
                                          await launchUrl(
                                            Uri.parse(bot),
                                            mode: LaunchMode.externalApplication,
                                          );
                                          return;
                                        }
                                        await _openProfile();
                                      },
                                    )
                                  else if (controller.needsLink)
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
                                    )
                                  else if (controller.showRefreshSubscriptionNotice)
                                    _SubscriptionBanner(
                                      text: s.refreshSubscriptionNotice,
                                      actionLabel: controller.isRefreshingServers
                                          ? '…'
                                          : s.refreshSubscriptionAction,
                                      onAction: controller.isRefreshingServers
                                          ? () {}
                                          : () => controller.refreshSubscriptionFromNotice(),
                                      onDismiss: () =>
                                          controller.dismissRefreshSubscriptionNotice(),
                                      dismissLabel: s.dismissNotice,
                                    ),
                                  const Spacer(),
                                  // Fixed slot so the connect button never jumps when
                                  // connected details appear above it.
                                  SizedBox(
                                    height: 118,
                                    width: double.infinity,
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        Text(
                                          controller.statusLine,
                                          textAlign: TextAlign.center,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w600,
                                            color: controller.isConnected
                                                ? (AppBrand.current.isXplm
                                                    ? XplmColors.ok
                                                    : NordColors.accent)
                                                : secondary,
                                          ),
                                        ),
                                        if (controller.isConnected) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            s.connectedTagline,
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: 0.8,
                                              color: (AppBrand.current.isXplm
                                                      ? XplmColors.cyan
                                                      : NordColors.accent)
                                                  .withValues(alpha: 0.9),
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            controller.sessionLabel,
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: muted,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '↓ ${_formatRate(controller.downloadBytesPerSec)}   ↑ ${_formatRate(controller.uploadBytesPerSec)}',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: muted,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
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
                                  KpaxCard(
                                    glow: controller.isConnected,
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) => const CountryPickerScreen(),
                                        ),
                                      );
                                    },
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                s.location,
                                                style: TextStyle(color: muted, fontSize: 13),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                controller.selectedLocation.isAuto
                                                    ? s.auto
                                                    : controller.selectedLocation.nameRu,
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              if (controller.selectedLocation.isAuto) ...[
                                                const SizedBox(height: 2),
                                                Text(
                                                  s.bestServerAuto,
                                                  style: TextStyle(color: muted, fontSize: 13),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        Icon(
                                          Icons.chevron_right_rounded,
                                          color: muted,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final xplm = AppBrand.current.isXplm;
    if (!xplm) {
      return IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, color: color),
      );
    }
    return Tooltip(
      message: tooltip,
      child: Material(
        color: XplmColors.surface.withValues(alpha: 0.55),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: XplmColors.cyan.withValues(alpha: 0.35)),
              boxShadow: [
                BoxShadow(
                  color: XplmColors.cyan.withValues(alpha: 0.18),
                  blurRadius: 14,
                ),
              ],
            ),
            child: Icon(icon, size: 20, color: XplmColors.cyan),
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
    final xplm = AppBrand.current.isXplm;
    return Material(
      color: warning
          ? const Color(0xFFB45309).withValues(alpha: 0.25)
          : (xplm
              ? XplmColors.accentSoft
              : NordColors.accentDim.withValues(alpha: 0.35)),
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
                  color: warning
                      ? NordColors.connecting
                      : (xplm ? XplmColors.cyan : NordColors.accent),
                ),
              ),
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
    this.onDismiss,
    this.dismissLabel,
  });

  final String text;
  final String actionLabel;
  final VoidCallback onAction;
  final bool danger;
  final VoidCallback? onDismiss;
  final String? dismissLabel;

  @override
  Widget build(BuildContext context) {
    final xplm = AppBrand.current.isXplm;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: danger
            ? (xplm
                ? XplmColors.danger.withValues(alpha: 0.18)
                : NordColors.danger.withValues(alpha: 0.16))
            : (xplm
                ? XplmColors.cyan.withValues(alpha: 0.12)
                : NordColors.cyan.withValues(alpha: 0.10)),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: danger
              ? (xplm
                  ? XplmColors.danger.withValues(alpha: 0.55)
                  : NordColors.danger.withValues(alpha: 0.55))
              : (xplm
                  ? XplmColors.cyan.withValues(alpha: 0.45)
                  : NordColors.cyan.withValues(alpha: 0.35)),
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
            style: TextButton.styleFrom(
              foregroundColor: danger
                  ? (xplm ? XplmColors.danger : NordColors.danger)
                  : (xplm ? XplmColors.cyan : NordColors.cyan),
            ),
            child: Text(actionLabel),
          ),
          if (onDismiss != null)
            TextButton(
              onPressed: onDismiss,
              style: TextButton.styleFrom(
                foregroundColor: xplm ? XplmColors.ink3 : NordColors.textMuted,
              ),
              child: Text(dismissLabel ?? 'OK'),
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
