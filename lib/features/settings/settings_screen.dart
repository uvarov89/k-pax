import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:pulse_vpn/app/brand/app_brand.dart';
import 'package:pulse_vpn/app/theme/nord_signal_theme.dart';
import 'package:pulse_vpn/app/theme/xplm_colors.dart';
import 'package:pulse_vpn/core/models/app_settings.dart';
import 'package:pulse_vpn/core/models/connection_models.dart';
import 'package:pulse_vpn/core/models/split_tunnel.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';
import 'package:pulse_vpn/features/connection/widgets/pro_settings_sheet.dart';
import 'package:pulse_vpn/features/account/account_screen.dart';
import 'package:pulse_vpn/features/paywall/paywall_screen.dart';
import 'package:pulse_vpn/features/settings/split_tunnel_screen.dart';
import 'package:pulse_vpn/features/settings/windows_split_screen.dart';
import 'package:pulse_vpn/features/settings/about_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final android = !kIsWeb && Platform.isAndroid;
    final controller = context.watch<VpnController>();
    final s = controller.strings;
    final settings = controller.appSettings;
    final account = controller.account;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final xplm = AppBrand.current.isXplm;
    final muted = xplm
        ? XplmColors.ink3
        : (isDark ? NordColors.textMuted : NordColors.lightTextMuted);
    final border = xplm
        ? XplmColors.line
        : (isDark ? NordColors.border : NordColors.lightBorder);
    final surface = xplm
        ? XplmColors.surface
        : (isDark ? NordColors.surface : NordColors.lightSurface);

    return NordBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(s.settings),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            _SectionHeader(s.sectionPremium, first: true),
            _SettingsCard(
              surface: surface,
              border: border,
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  title: Text(s.subscription),
                  subtitle: Text(
                    controller.hasExpiry || !account.hasAccess
                        ? '${controller.planLabel(account.plan)} · ${s.daysLeft(account.daysRemaining)}'
                        : '${controller.planLabel(account.plan)} · ${s.noExpiry}',
                    style: TextStyle(color: muted, fontSize: 13),
                  ),
                  trailing: Icon(Icons.chevron_right, color: muted),
                  onTap: () {
                    if (controller.isKPaxSubscription || controller.needsLink) {
                      openPaywall(context);
                      return;
                    }
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            const AccountScreen(accountDetails: true),
                      ),
                    );
                  },
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  title: Text(s.account),
                  subtitle: Text(
                    controller.isKPaxSubscription
                        ? account.userId
                        : controller.subscriptionName,
                    style: TextStyle(color: muted, fontSize: 13),
                  ),
                  trailing: Icon(Icons.chevron_right, color: muted),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            const AccountScreen(accountDetails: true),
                      ),
                    );
                  },
                ),
              ],
            ),
            _SectionHeader(s.sectionConnection),
            _SettingsCard(
              surface: surface,
              border: border,
              children: [
                _SwitchRow(
                  title: s.autoConnectLaunch,
                  value: settings.autoConnectOnLaunch,
                  onChanged: (v) => controller.updateAppSettings(
                    settings.copyWith(autoConnectOnLaunch: v),
                  ),
                ),
                if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) ...[
                  _SwitchRow(
                    title: s.autoConnectWifi,
                    value: settings.autoConnectOnWifi,
                    onChanged: (v) => controller.updateAppSettings(
                      settings.copyWith(autoConnectOnWifi: v),
                    ),
                  ),
                  _SwitchRow(
                    title: s.autoConnectMobile,
                    value: settings.autoConnectOnMobile,
                    onChanged: (v) => controller.updateAppSettings(
                      settings.copyWith(autoConnectOnMobile: v),
                    ),
                  ),
                ],
                if (!kIsWeb && Platform.isWindows)
                  _SwitchRow(
                    title: s.launchWithWindows,
                    value: settings.launchAtLogin,
                    onChanged: (v) => controller.updateAppSettings(
                      settings.copyWith(launchAtLogin: v),
                    ),
                  ),
                if (!kIsWeb && Platform.isWindows)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: Text(s.splitTunneling),
                    subtitle: Text(
                      s.splitSubtitle(switch (settings.splitTunnelMode) {
                        SplitTunnelMode.allApps => s.splitModeAll,
                        SplitTunnelMode.excludeSelected => s.splitModeExclude,
                        SplitTunnelMode.includeOnly => s.splitModeInclude,
                      }, settings.splitTunnelPackages.length),
                      style: TextStyle(color: muted, fontSize: 13),
                    ),
                    trailing: Icon(Icons.chevron_right, color: muted),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const WindowsSplitScreen(),
                        ),
                      );
                    },
                  ),
                _SwitchRow(
                  title: s.rememberLastCountry,
                  value: settings.rememberLastCountry,
                  onChanged: (v) => controller.updateAppSettings(
                    settings.copyWith(rememberLastCountry: v),
                  ),
                ),
                if (android)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: Text(s.splitTunneling),
                    subtitle: Text(
                      s.splitSubtitle(switch (settings.splitTunnelMode) {
                        SplitTunnelMode.allApps => s.splitModeAll,
                        SplitTunnelMode.excludeSelected => s.splitModeExclude,
                        SplitTunnelMode.includeOnly => s.splitModeInclude,
                      }, settings.splitTunnelPackages.length),
                      style: TextStyle(color: muted, fontSize: 13),
                    ),
                    trailing: Icon(Icons.chevron_right, color: muted),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const SplitTunnelScreen(),
                        ),
                      );
                    },
                  ),
                if (android)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.alwaysOnVpn),
                        const SizedBox(height: 4),
                        Text(
                          s.alwaysOnVpnHint,
                          style: TextStyle(
                            color: muted,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 36),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () =>
                                _showAlwaysOnHelp(context, controller),
                            child: Text(s.openSystemVpnSettings),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            _SectionHeader(s.proMode),
            _SettingsCard(
              surface: surface,
              border: border,
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  title: Text(s.openProSettings),
                  subtitle: controller.canUseProNetworkTools
                      ? null
                      : Text(
                          s.proLockedHint,
                          style: TextStyle(color: muted, fontSize: 13),
                        ),
                  trailing: Icon(Icons.chevron_right, color: muted),
                  onTap: () async {
                    await controller.setUserMode(AppUserMode.pro);
                    if (context.mounted) {
                      await showProSettingsSheet(context);
                    }
                  },
                ),
              ],
            ),
            _SectionHeader(s.sectionAppearance),
            _SettingsCard(
              surface: surface,
              border: border,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Expanded(child: Text(s.language)),
                      const SizedBox(width: 12),
                      DropdownButtonHideUnderline(
                        child: DropdownButton<AppLanguage>(
                          value: settings.language,
                          isDense: true,
                          dropdownColor: surface,
                          items: AppLanguage.values
                              .map(
                                (lang) => DropdownMenuItem(
                                  value: lang,
                                  child: Text(lang.nativeName),
                                ),
                              )
                              .toList(),
                          onChanged: (lang) {
                            if (lang == null) return;
                            controller.updateAppSettings(
                              settings.copyWith(language: lang),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                if (!AppBrand.current.isXplm)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Expanded(child: Text(s.theme)),
                        const SizedBox(width: 12),
                        DropdownButtonHideUnderline(
                          child: DropdownButton<AppThemePreference>(
                            value: settings.theme,
                            isDense: true,
                            dropdownColor: surface,
                            items: [
                              DropdownMenuItem(
                                value: AppThemePreference.dark,
                                child: Text(s.themeDark),
                              ),
                              DropdownMenuItem(
                                value: AppThemePreference.light,
                                child: Text(s.themeLight),
                              ),
                            ],
                            onChanged: (theme) {
                              if (theme == null) return;
                              controller.updateAppSettings(
                                settings.copyWith(theme: theme),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            _SectionHeader(s.sectionAbout),
            _SettingsCard(
              surface: surface,
              border: border,
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  title: Text(s.about),
                  subtitle: Text(
                    AppBrand.current.host,
                    style: TextStyle(color: muted, fontSize: 13),
                  ),
                  trailing: Icon(Icons.chevron_right, color: muted),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const AboutScreen(),
                      ),
                    );
                  },
                ),
                if (!kIsWeb && Platform.isWindows)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.quitAppHint,
                          style: TextStyle(
                            color: muted,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: () => _quitWindows(controller),
                          child: Text(s.quitApp),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAlwaysOnHelp(
    BuildContext context,
    VpnController controller,
  ) {
    final s = controller.strings;
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.alwaysOnHelpTitle),
        content: Text(s.alwaysOnHelpBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(s.gotIt),
          ),
        ],
      ),
    );
  }

  Future<void> _quitWindows(VpnController controller) async {
    if (controller.connectionState != VpnConnectionState.disconnected &&
        controller.connectionState != VpnConnectionState.disconnecting) {
      await controller.disconnect();
    }
    const channel = MethodChannel('kpax/window');
    try {
      await channel.invokeMethod<void>('quit');
    } catch (_) {
      exit(0);
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, {this.first = false});

  final String title;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.only(top: first ? 4 : 22, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: isDark
              ? NordColors.textSecondary
              : NordColors.lightTextSecondary,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.children,
    required this.surface,
    required this.border,
  });

  final List<Widget> children;
  final Color surface;
  final Color border;

  @override
  Widget build(BuildContext context) {
    final xplm = AppBrand.current.isXplm;
    return Container(
      decoration: BoxDecoration(
        color: surface.withValues(alpha: xplm ? 0.88 : 0.92),
        borderRadius: BorderRadius.circular(xplm ? 16 : 14),
        border: Border.all(
          color: xplm ? XplmColors.cyan.withValues(alpha: 0.28) : border,
        ),
        boxShadow: xplm
            ? [
                BoxShadow(
                  color: XplmColors.cyan.withValues(alpha: 0.12),
                  blurRadius: 18,
                ),
              ]
            : null,
      ),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(children: children),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(title),
      value: value,
      onChanged: onChanged,
    );
  }
}
