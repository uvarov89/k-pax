import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:pulse_vpn/core/models/app_settings.dart';
import 'package:pulse_vpn/core/models/connection_models.dart';
import 'package:pulse_vpn/core/models/split_tunnel.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';
import 'package:pulse_vpn/app/theme/nord_signal_theme.dart';
import 'package:pulse_vpn/features/connection/widgets/pro_settings_sheet.dart';
import 'package:pulse_vpn/features/account/account_screen.dart';
import 'package:pulse_vpn/features/paywall/paywall_screen.dart';
import 'package:pulse_vpn/features/settings/legal_screen.dart';
import 'package:pulse_vpn/features/settings/split_tunnel_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VpnController>();
    final s = controller.strings;
    final settings = controller.appSettings;
    final account = controller.account;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        isDark ? NordColors.textSecondary : NordColors.lightTextSecondary;
    final muted = isDark ? NordColors.textMuted : NordColors.lightTextMuted;
    final border = isDark ? NordColors.border : NordColors.lightBorder;
    final surface =
        isDark ? NordColors.surface : NordColors.lightSurface;

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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _SectionHeader(s.sectionPremium),
            _SettingsCard(
              surface: surface,
              border: border,
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: Text(s.subscription),
                  subtitle: Text(
                    '${controller.planLabel(account.plan)} · ${s.daysLeft(account.daysRemaining)}',
                    style: TextStyle(color: muted, fontSize: 13),
                  ),
                  trailing: Icon(Icons.chevron_right, color: muted),
                  onTap: () => openPaywall(context),
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: Text(s.account),
                  subtitle: Text(
                    account.userId,
                    style: TextStyle(color: muted, fontSize: 13),
                  ),
                  trailing: Icon(Icons.chevron_right, color: muted),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const AccountScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 18),
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
                _SwitchRow(
                  title: s.rememberLastCountry,
                  value: settings.rememberLastCountry,
                  onChanged: (v) => controller.updateAppSettings(
                    settings.copyWith(rememberLastCountry: v),
                  ),
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: Text(s.splitTunneling),
                  subtitle: Text(
                    s.splitSubtitle(
                      switch (settings.splitTunnelMode) {
                        SplitTunnelMode.allApps => s.splitModeAll,
                        SplitTunnelMode.excludeSelected => s.splitModeExclude,
                        SplitTunnelMode.includeOnly => s.splitModeInclude,
                      },
                      settings.splitTunnelPackages.length,
                    ),
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
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: Text(s.alwaysOnVpn),
                  subtitle: Text(
                    s.alwaysOnVpnHint,
                    style: TextStyle(color: muted, fontSize: 13),
                  ),
                  trailing: TextButton(
                    onPressed: () => _showAlwaysOnHelp(context, controller),
                    child: Text(s.openSystemVpnSettings),
                  ),
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: Text(s.refreshServers),
                  subtitle: Text(
                    s.refreshServersHint,
                    style: TextStyle(color: muted, fontSize: 13),
                  ),
                  trailing: controller.isRefreshingServers
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.refresh, color: secondary),
                  onTap: controller.isRefreshingServers
                      ? null
                      : () async {
                          await controller.refreshServers();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(s.serversUpdated)),
                            );
                          }
                        },
                ),
              ],
            ),
            const SizedBox(height: 18),
            _SectionHeader(s.proMode),
            _SettingsCard(
              surface: surface,
              border: border,
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
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
            const SizedBox(height: 18),
            _SectionHeader(s.sectionAppearance),
            _SettingsCard(
              surface: surface,
              border: border,
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: Text(s.language),
                  subtitle: Text(
                    settings.language.nativeName,
                    style: TextStyle(color: muted, fontSize: 13),
                  ),
                  trailing: DropdownButtonHideUnderline(
                    child: DropdownButton<AppLanguage>(
                      value: settings.language,
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
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: Text(s.theme),
                  trailing: DropdownButtonHideUnderline(
                    child: DropdownButton<AppThemePreference>(
                      value: settings.theme,
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
                ),
              ],
            ),
            const SizedBox(height: 18),
            _SectionHeader(s.sectionAbout),
            _SettingsCard(
              surface: surface,
              border: border,
              children: [
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snapshot) {
                    final version = snapshot.data?.version ?? '—';
                    final build = snapshot.data?.buildNumber ?? '';
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      title: Text(s.version),
                      subtitle: Text(
                        build.isEmpty ? version : '$version ($build)',
                        style: TextStyle(color: muted, fontSize: 13),
                      ),
                    );
                  },
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: Text(s.terms),
                  subtitle: Text(
                    s.termsStub,
                    style: TextStyle(color: muted, fontSize: 13),
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => LegalScreen(
                          title: s.terms,
                          paragraphs: s.termsParagraphs,
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: Text(s.privacy),
                  subtitle: Text(
                    s.privacySoon,
                    style: TextStyle(color: muted, fontSize: 13),
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => LegalScreen(
                          title: s.privacy,
                          paragraphs: s.privacyParagraphs,
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: Text(s.support),
                  subtitle: Text(
                    s.supportSoon,
                    style: TextStyle(color: muted, fontSize: 13),
                  ),
                  onTap: () => launchUrl(
                    Uri.parse('https://t.me/k_pax_space'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: Text(s.rateApp),
                  subtitle: Text(
                    s.rateAppStub,
                    style: TextStyle(color: muted, fontSize: 13),
                  ),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(s.rateAppStub)),
                    );
                  },
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: Text(s.diagnostics),
                  subtitle: Text(
                    s.diagnosticsHint,
                    style: TextStyle(color: muted, fontSize: 13),
                  ),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(s.diagnosticsHint)),
                    );
                  },
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
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: isDark ? NordColors.textSecondary : NordColors.lightTextSecondary,
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
    return Container(
      decoration: BoxDecoration(
        color: surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Text(title),
      value: value,
      onChanged: onChanged,
    );
  }
}
