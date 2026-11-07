import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:pulse_vpn/app/theme/nord_signal_theme.dart';
import 'package:pulse_vpn/app/brand/app_brand.dart';
import 'package:pulse_vpn/features/xplm/widgets/xplm_html_widgets.dart';
import 'package:pulse_vpn/core/models/split_tunnel.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';

class WindowsSplitScreen extends StatelessWidget {
  const WindowsSplitScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VpnController>();
    final settings = controller.appSettings;
    final s = controller.strings;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? NordColors.textMuted : NordColors.lightTextMuted;
    final names = settings.splitTunnelPackages;

    final modes = RadioGroup<SplitTunnelMode>(
      groupValue: settings.splitTunnelMode,
      onChanged: (value) {
        if (value != null) {
          controller.updateAppSettings(
            controller.appSettings.copyWith(splitTunnelMode: value),
          );
        }
      },
      child: Column(
        children: [
          for (final mode in SplitTunnelMode.values)
            RadioListTile<SplitTunnelMode>(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              value: mode,
              title: Text(switch (mode) {
                SplitTunnelMode.allApps => s.splitModeAll,
                SplitTunnelMode.excludeSelected => s.splitModeExclude,
                SplitTunnelMode.includeOnly => s.splitModeInclude,
              }),
            ),
        ],
      ),
    );
    final scaffold = Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(s.splitTunneling),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text(
            s.splitWindowsNote,
            style: TextStyle(color: muted, height: 1.35),
          ),
          const SizedBox(height: 8),
          AppBrand.current.isXplm ? XplmHtmlGlass(child: modes) : modes,
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => _addProgram(context),
            child: Text(s.splitAddProgram),
          ),
          for (final name in names)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: Text(name),
              trailing: IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close),
                onPressed: () {
                  final next = [...names]..remove(name);
                  controller.updateAppSettings(
                    settings.copyWith(splitTunnelPackages: next),
                  );
                },
              ),
            ),
        ],
      ),
    );
    if (AppBrand.current.isXplm) {
      return XplmHtmlPage(title: s.splitTunneling, child: scaffold.body!);
    }
    return NordBackground(child: scaffold);
  }

  Future<void> _addProgram(BuildContext context) async {
    final controller = context.read<VpnController>();
    final picked = await const MethodChannel(
      'kpax/window',
    ).invokeMethod<String>('pickExe');
    if (picked == null || picked.isEmpty) return;
    final name = picked.split(RegExp(r'[\\/]')).last.trim().toLowerCase();
    if (!name.endsWith('.exe')) return;
    final settings = controller.appSettings;
    if (settings.splitTunnelPackages.contains(name)) return;
    await controller.updateAppSettings(
      settings.copyWith(
        splitTunnelPackages: [...settings.splitTunnelPackages, name],
      ),
    );
  }
}
