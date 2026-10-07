import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:pulse_vpn/core/models/connection_models.dart';
import 'package:pulse_vpn/core/models/server_location.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';
import 'package:pulse_vpn/app/theme/nord_signal_theme.dart';

class CountryPickerScreen extends StatelessWidget {
  const CountryPickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VpnController>();
    final s = controller.strings;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedId =
        controller.locationMode == LocationMode.auto ||
                controller.selectedLocation.isAuto
            ? ServerLocation.auto.id
            : controller.selectedLocation.id;

    final surface =
        isDark ? NordColors.surface : NordColors.lightSurface;
    final elevated =
        isDark ? NordColors.surfaceElevated : NordColors.lightSurfaceElevated;
    final border = isDark ? NordColors.border : NordColors.lightBorder;
    final secondary =
        isDark ? NordColors.textSecondary : NordColors.lightTextSecondary;
    final muted = isDark ? NordColors.textMuted : NordColors.lightTextMuted;
    final barBg = isDark ? NordColors.bgTop : NordColors.lightBgTop;

    return NordBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(s.location),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                itemCount: controller.locations.length,
                separatorBuilder: (context, index) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final server = controller.locations[index];
                  final selected = server.id == selectedId;
                  return Material(
                    color: selected
                        ? elevated
                        : surface.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => controller.selectLocation(server),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border(
                            left: BorderSide(
                              width: 3,
                              color: selected
                                  ? NordColors.accent
                                  : Colors.transparent,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            _FlagMark(code: server.countryCode),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    server.isAuto ? s.auto : server.nameRu,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                  ),
                                  if (server.isAuto)
                                    Text(
                                      s.bestSpeedAuto,
                                      style: TextStyle(
                                        color: muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (!server.isAuto && server.latencyMs >= 0)
                              Text(
                                '${server.latencyMs} ms',
                                style: TextStyle(
                                  color: selected
                                      ? NordColors.accent
                                      : secondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            if (server.isAuto)
                              Text(
                                s.recommended,
                                style: const TextStyle(
                                  color: NordColors.accent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                decoration: BoxDecoration(
                  color: barBg.withValues(alpha: 0.92),
                  border: Border(top: BorderSide(color: border)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        controller.selectedLocation.isAuto
                            ? s.auto
                            : controller.selectedLocation.nameRu,
                        style: TextStyle(
                          color: secondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: NordColors.accentDim,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        if (!controller.isConnected && !controller.isBusy) {
                          controller.connect();
                        }
                      },
                      child: Text(s.connect),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlagMark extends StatelessWidget {
  const _FlagMark({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isDark
            ? NordColors.surfaceElevated
            : NordColors.lightSurfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? NordColors.border : NordColors.lightBorder,
        ),
      ),
      child: Text(
        code == 'AUTO' ? 'AUTO' : code,
        style: TextStyle(
          fontSize: code == 'AUTO' ? 8 : 11,
          fontWeight: FontWeight.w700,
          color: isDark
              ? NordColors.textSecondary
              : NordColors.lightTextSecondary,
        ),
      ),
    );
  }
}
