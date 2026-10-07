import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:pulse_vpn/core/models/app_settings.dart';
import 'package:pulse_vpn/core/models/connection_models.dart';
import 'package:pulse_vpn/features/paywall/paywall_screen.dart';
import 'package:pulse_vpn/features/settings/split_tunnel_screen.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';
import 'package:pulse_vpn/app/theme/nord_signal_theme.dart';

Future<void> showProSettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const ProSettingsSheet(),
  );
}

class ProSettingsSheet extends StatelessWidget {
  const ProSettingsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VpnController>();
    final settings = controller.proSettings;
    final s = controller.strings;
    final locked = !controller.canUseProNetworkTools;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? NordColors.bgBottom : NordColors.lightBgBottom;
    final border = isDark ? NordColors.border : NordColors.lightBorder;
    final muted = isDark ? NordColors.textMuted : NordColors.lightTextMuted;
    final secondary =
        isDark ? NordColors.textSecondary : NordColors.lightTextSecondary;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.78,
      ),
      decoration: BoxDecoration(
        color: sheetBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    s.proMode,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: Icon(Icons.close, color: secondary),
                ),
              ],
            ),
          ),
          if (locked)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Material(
                color: NordColors.surface.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    Navigator.of(context).pop();
                    openPaywall(context);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.lock_outline,
                          color: NordColors.connecting,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            s.proLockedHint,
                            style: TextStyle(color: muted, fontSize: 13),
                          ),
                        ),
                        Text(
                          s.subscription,
                          style: const TextStyle(
                            color: NordColors.accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Flexible(
            child: AbsorbPointer(
              absorbing: locked,
              child: Opacity(
                opacity: locked ? 0.45 : 1,
                child: ListView(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + bottom),
              shrinkWrap: true,
              children: [
                _SectionLabel(s.protocol),
                const SizedBox(height: 8),
                _SegmentedChoices<TunnelProtocol>(
                  values: TunnelProtocol.values,
                  selected: settings.protocol,
                  labelOf: (v) => v.labelRu,
                  onChanged: (v) => controller.updateProSettings(
                    settings.copyWith(protocol: v),
                  ),
                ),
                const SizedBox(height: 20),
                _SectionLabel(s.networkBypass),
                const SizedBox(height: 8),
                _SegmentedChoices<BypassMode>(
                  values: BypassMode.values,
                  selected: settings.bypassMode,
                  labelOf: (v) => v.labelRu,
                  onChanged: (v) => controller.updateProSettings(
                    settings.copyWith(bypassMode: v),
                  ),
                ),
                const SizedBox(height: 12),
                _SettingsTile(
                  title: s.dns,
                  subtitle: s.dnsAutomatic,
                  trailing: Switch(
                    value: settings.dnsAutomatic,
                    onChanged: (v) => controller.updateProSettings(
                      settings.copyWith(dnsAutomatic: v),
                    ),
                  ),
                ),
                _SettingsTile(
                  title: s.splitTunneling,
                  subtitle: s.splitSoon,
                  trailing: Icon(Icons.chevron_right, color: muted),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SplitTunnelScreen(),
                      ),
                    );
                  },
                ),
                _SettingsTile(
                  title: s.killSwitch,
                  subtitle: s.killSwitchHint,
                  trailing: Switch(
                    value: settings.killSwitch,
                    onChanged: (v) => controller.updateProSettings(
                      settings.copyWith(killSwitch: v),
                    ),
                  ),
                ),
                _SettingsTile(
                  title: s.protocolFallback,
                  subtitle: s.protocolFallbackHint,
                  trailing: Switch(
                    value: settings.protocolFallback,
                    onChanged: (v) => controller.updateProSettings(
                      settings.copyWith(protocolFallback: v),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _SectionLabel(s.ipv6),
                const SizedBox(height: 8),
                _SegmentedChoices<Ipv6Mode>(
                  values: Ipv6Mode.values,
                  selected: settings.ipv6Mode,
                  labelOf: (v) => v.label(controller.appSettings.language),
                  onChanged: (v) => controller.updateProSettings(
                    settings.copyWith(ipv6Mode: v),
                  ),
                ),
                const SizedBox(height: 16),
                _SectionLabel(s.reconnect),
                const SizedBox(height: 8),
                _SegmentedChoices<ReconnectPolicy>(
                  values: ReconnectPolicy.values,
                  selected: settings.reconnectPolicy,
                  labelOf: (v) => v.label(controller.appSettings.language),
                  onChanged: (v) => controller.updateProSettings(
                    settings.copyWith(reconnectPolicy: v),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: border),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: controller.isProbing
                        ? null
                        : () => controller.runNodeProbe(),
                    child: Text(
                      controller.isProbing ? s.testingNodes : s.testNodes,
                    ),
                  ),
                ),
                if (controller.lastProbeResults != null) ...[
                  const SizedBox(height: 12),
                  ...controller.lastProbeResults!.entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Text(
                            e.key.toUpperCase(),
                            style: TextStyle(color: secondary),
                          ),
                          const Spacer(),
                          Text(
                            '${e.value} ms',
                            style: const TextStyle(
                              color: NordColors.accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: isDark ? NordColors.textSecondary : NordColors.lightTextSecondary,
        letterSpacing: 0.3,
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: isDark ? NordColors.textMuted : NordColors.lightTextMuted,
          fontSize: 13,
        ),
      ),
      trailing: trailing,
    );
  }
}

class _SegmentedChoices<T> extends StatelessWidget {
  const _SegmentedChoices({
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
  });

  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: values.map((value) {
        final isSelected = value == selected;
        return ChoiceChip(
          label: Text(labelOf(value)),
          selected: isSelected,
          onSelected: (_) => onChanged(value),
          selectedColor: NordColors.accentDim,
          backgroundColor:
              isDark ? NordColors.surface : NordColors.lightSurfaceElevated,
          side: BorderSide(
            color: isSelected
                ? NordColors.accent
                : (isDark ? NordColors.border : NordColors.lightBorder),
          ),
          labelStyle: TextStyle(
            color: isSelected
                ? Colors.white
                : (isDark
                    ? NordColors.textSecondary
                    : NordColors.lightTextSecondary),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          showCheckmark: false,
        );
      }).toList(),
    );
  }
}
