import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';
import 'package:pulse_vpn/features/xplm/widgets/xplm_html_widgets.dart';

class XplmDeviceSettingsScreen extends StatelessWidget {
  const XplmDeviceSettingsScreen({
    super.key,
    this.onOpenAndroidVpn,
    this.onQuit,
  });
  final Future<void> Function()? onOpenAndroidVpn;
  final Future<void> Function()? onQuit;
  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final c = context.watch<VpnController>();
    final s = c.strings;
    final settings = c.appSettings;
    final ios = platform == TargetPlatform.iOS;
    final windows = platform == TargetPlatform.windows;
    return XplmHtmlPage(
      title: s.isRu ? 'Настройки устройства' : 'Device settings',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        children: [
          Text(
            s.isRu
                ? 'Эти функции зависят от операционной системы.'
                : 'These features depend on the operating system.',
          ),
          const SizedBox(height: 16),
          XplmHtmlGlass(
            child: Column(
              children: [
                XplmPreferenceSwitch(
                  key: const ValueKey('device-wifi'),
                  title: s.autoConnectWifi,
                  subtitle: ios
                      ? (s.isRu
                            ? 'Системное On Demand после первого подключения VPN'
                            : 'System On Demand after the first VPN connection')
                      : null,
                  value: settings.autoConnectOnWifi,
                  onChanged: (v) => c.updateAppSettings(
                    settings.copyWith(autoConnectOnWifi: v),
                  ),
                ),
                if (!windows)
                  XplmPreferenceSwitch(
                    key: const ValueKey('device-mobile'),
                    title: s.autoConnectMobile,
                    subtitle: ios
                        ? (s.isRu
                              ? 'Системное On Demand после первого подключения VPN'
                              : 'System On Demand after the first VPN connection')
                        : null,
                    value: settings.autoConnectOnMobile,
                    onChanged: (v) => c.updateAppSettings(
                      settings.copyWith(autoConnectOnMobile: v),
                    ),
                  ),
                if (windows)
                  XplmPreferenceSwitch(
                    key: const ValueKey('device-autostart'),
                    title: s.launchWithWindows,
                    value: settings.launchAtLogin,
                    onChanged: (v) => c.updateAppSettings(
                      settings.copyWith(launchAtLogin: v),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (windows)
            XplmHtmlGlass(
              child: XplmPreferenceSwitch(
                key: const ValueKey('device-kill-switch'),
                title: s.killSwitch,
                subtitle: s.killSwitchHint,
                value: c.proSettings.killSwitch,
                onChanged: c.canUseProNetworkTools
                    ? (v) => c.updateProSettings(
                        c.proSettings.copyWith(killSwitch: v),
                      )
                    : null,
              ),
            ),
          if (platform == TargetPlatform.android)
            XplmHtmlGlass(
              child: ListTile(
                key: const ValueKey('device-system-vpn'),
                title: Text(s.alwaysOnVpn),
                subtitle: Text(s.alwaysOnVpnHint),
                trailing: const Icon(Icons.open_in_new_rounded),
                onTap: onOpenAndroidVpn,
              ),
            ),
          if (windows) ...[
            const SizedBox(height: 24),
            OutlinedButton(
              key: const ValueKey('device-quit'),
              onPressed: onQuit,
              child: Text(s.quitApp),
            ),
          ],
        ],
      ),
    );
  }
}

/// Saves through the real controller and prevents repeated taps during a write.
class XplmPreferenceSwitch extends StatefulWidget {
  const XplmPreferenceSwitch({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final bool value;
  final Future<void> Function(bool)? onChanged;
  @override
  State<XplmPreferenceSwitch> createState() => _XplmPreferenceSwitchState();
}

class _XplmPreferenceSwitchState extends State<XplmPreferenceSwitch> {
  bool saving = false;
  Future<void> save(bool value) async {
    setState(() => saving = true);
    try {
      await widget.onChanged!(value);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось сохранить настройку')),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SwitchListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    title: Text(widget.title),
    subtitle: widget.subtitle == null ? null : Text(widget.subtitle!),
    value: widget.value,
    onChanged: saving || widget.onChanged == null ? null : save,
  );
}
