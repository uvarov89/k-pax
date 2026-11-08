import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pulse_vpn/core/models/app_settings.dart';
import 'package:pulse_vpn/core/models/split_tunnel.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';
import 'package:pulse_vpn/features/xplm/widgets/xplm_html_widgets.dart';
import 'split_tunnel_screen.dart';
import 'windows_split_screen.dart';
import 'xplm_device_settings_screen.dart';
import 'xplm_security_screen.dart';

/// One list of common controls and routes for all three X-Plm platforms.
class XplmPreferencesScreen extends StatelessWidget {
  const XplmPreferencesScreen({super.key, this.onOpenAndroidVpn, this.onQuit});
  final Future<void> Function()? onOpenAndroidVpn;
  final Future<void> Function()? onQuit;
  @override
  Widget build(BuildContext context) {
    final c = context.watch<VpnController>();
    final settings = c.appSettings;
    final s = c.strings;
    Widget section(String text) => Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    );
    void open(Widget page) => Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));
    Widget row(
      String id,
      String title,
      VoidCallback onTap, {
      String? subtitle,
    }) => ListTile(
      key: ValueKey(id),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
    return XplmHtmlPage(
      title: s.settings,
      child: ListView(
        key: const ValueKey('preferences-list'),
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        children: [
          section(s.isRu ? 'Уведомления' : 'Notifications'),
          XplmHtmlGlass(
            child: XplmPreferenceSwitch(
              key: const ValueKey('preferences-notifications'),
              title: s.isRu ? 'Подсказки в приложении' : 'In-app messages',
              subtitle: s.isRu
                  ? 'Показывать сообщения о состоянии приложения.'
                  : 'Show application status messages.',
              value: settings.notificationsEnabled,
              onChanged: (v) => c.updateAppSettings(
                settings.copyWith(notificationsEnabled: v),
              ),
            ),
          ),
          section(s.isRu ? 'Запуск и подключение' : 'Startup and connection'),
          XplmHtmlGlass(
            child: Column(
              children: [
                XplmPreferenceSwitch(
                  key: const ValueKey('preferences-launch'),
                  title: s.autoConnectLaunch,
                  value: settings.autoConnectOnLaunch,
                  onChanged: (v) => c.updateAppSettings(
                    settings.copyWith(autoConnectOnLaunch: v),
                  ),
                ),
                XplmPreferenceSwitch(
                  key: const ValueKey('preferences-country'),
                  title: s.rememberLastCountry,
                  value: settings.rememberLastCountry,
                  onChanged: (v) => c.updateAppSettings(
                    settings.copyWith(rememberLastCountry: v),
                  ),
                ),
              ],
            ),
          ),
          section(s.sectionConnection),
          XplmHtmlGlass(
            child: Column(
              children: [
                row(
                  'preferences-split',
                  s.splitTunneling,
                  () {
                    final platform = Theme.of(context).platform;
                    if (platform == TargetPlatform.windows) {
                      open(const WindowsSplitScreen());
                    } else if (platform == TargetPlatform.android) {
                      open(const SplitTunnelScreen());
                    } else {
                      showDialog<void>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(s.splitTunneling),
                          content: Text(
                            s.isRu
                                ? 'Раздельное подключение приложений в этой iOS-версии недоступно. VPN работает для всего устройства.'
                                : 'Per-app split tunneling is unavailable in this iOS version. VPN applies to the whole device.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text(s.gotIt),
                            ),
                          ],
                        ),
                      );
                    }
                  },
                  subtitle: s.splitSubtitle(switch (settings.splitTunnelMode) {
                    SplitTunnelMode.allApps => s.splitModeAll,
                    SplitTunnelMode.excludeSelected => s.splitModeExclude,
                    SplitTunnelMode.includeOnly => s.splitModeInclude,
                  }, settings.splitTunnelPackages.length),
                ),
                row(
                  'preferences-security',
                  s.isRu ? 'VPN и защита' : 'VPN and protection',
                  () => open(const XplmSecurityScreen()),
                ),
                row(
                  'preferences-device',
                  s.isRu ? 'Настройки устройства' : 'Device settings',
                  () => open(
                    XplmDeviceSettingsScreen(
                      onOpenAndroidVpn: onOpenAndroidVpn,
                      onQuit: onQuit,
                    ),
                  ),
                  subtitle: s.isRu
                      ? 'Автоподключение и системные функции'
                      : 'Auto-connect and system features',
                ),
              ],
            ),
          ),
          section(s.isRu ? 'Приложение' : 'Application'),
          XplmHtmlGlass(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Expanded(child: Text(s.language)),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<AppLanguage>(
                      key: const ValueKey('preferences-language'),
                      value: settings.language,
                      items: [
                        for (final language in AppLanguage.values)
                          DropdownMenuItem(
                            value: language,
                            child: Text(language.nativeName),
                          ),
                      ],
                      onChanged: (language) {
                        if (language != null) {
                          c.updateAppSettings(
                            settings.copyWith(language: language),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
