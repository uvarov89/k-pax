import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:pulse_vpn/app/theme/xplm_colors.dart';
import 'package:pulse_vpn/core/models/app_settings.dart';
import 'package:pulse_vpn/core/models/connection_models.dart';
import 'package:pulse_vpn/core/services/server_latency_monitor.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';
import 'package:pulse_vpn/features/paywall/paywall_screen.dart';
import 'package:pulse_vpn/features/xplm/widgets/xplm_html_widgets.dart';

class XplmSecurityScreen extends StatelessWidget {
  const XplmSecurityScreen({super.key});
  Future<void> _save(
    BuildContext context,
    Future<void> Function() change,
  ) async {
    try {
      await change();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось сохранить настройки. Повторите попытку.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<VpnController>();
    final monitor = context.watch<ServerLatencyMonitor?>();
    final s = c.strings;
    final p = c.proSettings;
    final allowed = c.canUseProNetworkTools;
    final android =
        !kIsWeb && Theme.of(context).platform == TargetPlatform.android;
    final windows =
        !kIsWeb && Theme.of(context).platform == TargetPlatform.windows;
    Widget section(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(0, 22, 0, 10),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: XplmColors.ink2,
        ),
      ),
    );
    return XplmHtmlPage(
      title: s.isRu ? 'VPN и защита' : 'VPN and protection',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        children: [
          XplmHtmlGlass(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(
                  Icons.shield_outlined,
                  color: XplmColors.cyan,
                  size: 30,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    s.isRu
                        ? 'Изменения протокола и DNS применятся при следующем подключении.'
                        : 'Protocol and DNS changes apply on the next connection.',
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: XplmColors.ink2,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!allowed) ...[
            const SizedBox(height: 12),
            Text(
              s.proLockedHint,
              style: const TextStyle(color: XplmColors.ink2),
            ),
            const SizedBox(height: 10),
            XplmHtmlButton(
              label: s.subscription,
              onPressed: () => openPaywall(context),
            ),
          ],
          section(s.protocol),
          XplmHtmlGlass(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<TunnelProtocol>(
                key: const ValueKey('security-protocol'),
                value: p.protocol,
                isExpanded: true,
                dropdownColor: XplmColors.surface,
                items: [
                  for (final value in TunnelProtocol.values)
                    DropdownMenuItem(
                      value: value,
                      child: Text(s.protocolLabel(value)),
                    ),
                ],
                onChanged: !allowed
                    ? null
                    : (value) {
                        if (value != null) {
                          _save(
                            context,
                            () => c.updateProSettings(
                              c.proSettings.copyWith(protocol: value),
                            ),
                          );
                        }
                      },
              ),
            ),
          ),
          section(s.networkBypass),
          XplmHtmlGlass(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonHideUnderline(
                  child: DropdownButton<BypassMode>(
                    value: p.bypassMode,
                    isExpanded: true,
                    dropdownColor: XplmColors.surface,
                    items: [
                      for (final value in BypassMode.values)
                        DropdownMenuItem(
                          value: value,
                          child: Text(s.bypassLabel(value)),
                        ),
                    ],
                    onChanged: !allowed
                        ? null
                        : (value) {
                            if (value != null) {
                              _save(
                                context,
                                () => c.updateProSettings(
                                  c.proSettings.copyWith(bypassMode: value),
                                ),
                              );
                            }
                          },
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  s.bypassHint(p.bypassMode),
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: XplmColors.ink2,
                  ),
                ),
              ],
            ),
          ),
          section(s.dns),
          XplmHtmlGlass(
            child: Column(
              children: [
                SwitchListTile(
                  title: Text(s.dns),
                  subtitle: Text(
                    p.dnsAutomatic ? s.dnsThroughTunnel : s.dnsComputer,
                  ),
                  value: p.dnsAutomatic,
                  onChanged: !allowed
                      ? null
                      : (value) => _save(
                          context,
                          () => c.updateProSettings(
                            c.proSettings.copyWith(dnsAutomatic: value),
                          ),
                        ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: Text(s.protocolFallback),
                  subtitle: Text(s.protocolFallbackHint),
                  value: p.protocolFallback,
                  onChanged: !allowed
                      ? null
                      : (value) => _save(
                          context,
                          () => c.updateProSettings(
                            c.proSettings.copyWith(protocolFallback: value),
                          ),
                        ),
                ),
              ],
            ),
          ),
          section(s.ipv6),
          XplmHtmlGlass(
            child: ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: Text(
                s.isRu
                    ? 'IPv6 блокируется туннелем'
                    : 'IPv6 is blocked by the tunnel',
              ),
              subtitle: Text(
                s.isRu
                    ? 'Текущая конфигурация работает через IPv4. Переключение режима IPv6 не поддерживается.'
                    : 'The current tunnel uses IPv4. Switching IPv6 modes is not supported.',
              ),
            ),
          ),
          section(s.reconnect),
          XplmHtmlGlass(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<ReconnectPolicy>(
                value: p.reconnectPolicy,
                isExpanded: true,
                dropdownColor: XplmColors.surface,
                items: [
                  for (final value in ReconnectPolicy.values)
                    DropdownMenuItem(
                      value: value,
                      child: Text(value.label(c.appSettings.language)),
                    ),
                ],
                onChanged: !allowed
                    ? null
                    : (value) {
                        if (value != null) {
                          _save(
                            context,
                            () => c.updateProSettings(
                              c.proSettings.copyWith(reconnectPolicy: value),
                            ),
                          );
                        }
                      },
              ),
            ),
          ),
          if (windows) ...[
            const SizedBox(height: 12),
            XplmHtmlGlass(
              child: SwitchListTile(
                title: Text(s.killSwitch),
                subtitle: Text(s.killSwitchHint),
                value: p.killSwitch,
                onChanged: !allowed
                    ? null
                    : (value) => _save(
                        context,
                        () => c.updateProSettings(
                          c.proSettings.copyWith(killSwitch: value),
                        ),
                      ),
              ),
            ),
          ],
          if (android) ...[
            const SizedBox(height: 12),
            XplmHtmlGlass(
              child: ListTile(
                title: Text(s.alwaysOnVpn),
                subtitle: Text(s.alwaysOnVpnHint),
                trailing: const Icon(Icons.open_in_new_rounded),
                onTap: () async {
                  try {
                    await const MethodChannel(
                      'kpax/android',
                    ).invokeMethod<bool>('openVpnSettings');
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(s.alwaysOnHelpBody)),
                      );
                    }
                  }
                },
              ),
            ),
          ],
          section(s.isRu ? 'Диагностика соединения' : 'Connection diagnostics'),
          XplmHtmlGlass(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                XplmHtmlButton(
                  label: (monitor?.isMeasuring ?? c.isProbing)
                      ? s.testingNodes
                      : s.testNodes,
                  busy: monitor?.isMeasuring ?? c.isProbing,
                  onPressed: !allowed
                      ? null
                      : () => monitor != null
                            ? monitor.refresh()
                            : c.runNodeProbe(),
                ),
                for (final location in c.locations.where((l) => !l.isAuto))
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      children: [
                        Expanded(child: Text(location.nameRu)),
                        Text(
                          (monitor?.pingFor(location.id) ??
                                      location.latencyMs) <
                                  0
                              ? s.probeNoAnswer
                              : '${monitor?.pingFor(location.id) ?? location.latencyMs} ms',
                          style: const TextStyle(color: XplmColors.ink2),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
