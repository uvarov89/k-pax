import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:pulse_vpn/app/brand/app_brand.dart';
import 'package:pulse_vpn/app/theme/nord_signal_theme.dart';
import 'package:pulse_vpn/app/theme/xplm_colors.dart';
import 'package:pulse_vpn/core/models/connection_models.dart';
import 'package:pulse_vpn/core/models/server_location.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';
import 'package:pulse_vpn/features/xplm/widgets/xplm_codex_widgets.dart';

enum _RegionChip { all, europe, asia, northAmerica }

const _europe = {
  'DE', 'FI', 'BG', 'FR', 'NL', 'GB', 'UK', 'SE', 'PL', 'IT', 'ES', 'TR', 'RU',
  'AT', 'CH', 'CZ', 'RO', 'UA', 'LV', 'LT', 'EE', 'PT', 'IE', 'NO', 'DK', 'HU',
};
const _asia = {
  'SG', 'JP', 'KR', 'CN', 'MY', 'AU', 'IN', 'HK', 'TW', 'TH', 'VN', 'ID', 'PH',
};
const _northAmerica = {'US', 'CA', 'MX'};

class CountryPickerScreen extends StatefulWidget {
  const CountryPickerScreen({super.key, this.embeddedInShell = false});

  final bool embeddedInShell;

  @override
  State<CountryPickerScreen> createState() => _CountryPickerScreenState();
}

class _CountryPickerScreenState extends State<CountryPickerScreen> {
  _RegionChip _chip = _RegionChip.all;
  bool _searchOpen = false;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(ServerLocation server) {
    if (server.isAuto) return _chip == _RegionChip.all;
    final code = server.countryCode.toUpperCase();
    switch (_chip) {
      case _RegionChip.all:
        return true;
      case _RegionChip.europe:
        return _europe.contains(code);
      case _RegionChip.asia:
        return _asia.contains(code);
      case _RegionChip.northAmerica:
        return _northAmerica.contains(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VpnController>();
    final s = controller.strings;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final xplm = AppBrand.current.isXplm;
    final selectedId =
        controller.locationMode == LocationMode.auto ||
                controller.selectedLocation.isAuto
            ? ServerLocation.auto.id
            : controller.selectedLocation.id;

    final surface = xplm
        ? XplmColors.surface
        : (isDark ? NordColors.surface : NordColors.lightSurface);
    final elevated = xplm
        ? XplmColors.surfaceElevated
        : (isDark ? NordColors.surfaceElevated : NordColors.lightSurfaceElevated);
    final border = xplm
        ? XplmColors.line
        : (isDark ? NordColors.border : NordColors.lightBorder);
    final secondary = xplm
        ? XplmColors.ink2
        : (isDark ? NordColors.textSecondary : NordColors.lightTextSecondary);
    final muted = xplm
        ? XplmColors.ink3
        : (isDark ? NordColors.textMuted : NordColors.lightTextMuted);
    final barBg = xplm
        ? XplmColors.bgMid
        : (isDark ? NordColors.bgTop : NordColors.lightBgTop);
    final accent = xplm ? XplmColors.cyan : NordColors.accent;
    final accentFill = xplm ? XplmColors.accent : NordColors.accentDim;

    final q = _search.text.trim().toLowerCase();
    // Codex mock countries when subscription nodes are not loaded yet (UI parity).
    const demo = <ServerLocation>[
      ServerLocation(id: 'de', countryCode: 'DE', nameRu: 'Германия', latencyMs: 28),
      ServerLocation(id: 'fi', countryCode: 'FI', nameRu: 'Финляндия', latencyMs: 34),
      ServerLocation(id: 'bg', countryCode: 'BG', nameRu: 'Болгария', latencyMs: 42),
      ServerLocation(id: 'fr', countryCode: 'FR', nameRu: 'Франция', latencyMs: 48),
      ServerLocation(id: 'nl', countryCode: 'NL', nameRu: 'Нидерланды', latencyMs: 52),
      ServerLocation(id: 'us', countryCode: 'US', nameRu: 'США', latencyMs: 76),
      ServerLocation(id: 'gb', countryCode: 'GB', nameRu: 'Великобритания', latencyMs: 80),
      ServerLocation(id: 'sg', countryCode: 'SG', nameRu: 'Сингапур', latencyMs: 112),
    ];
    final source = xplm && controller.locations.length <= 1
        ? <ServerLocation>[ServerLocation.auto, ...demo]
        : controller.locations;
    final locations = (xplm ? source.where(_matches) : source).where((l) {
      if (q.isEmpty) return true;
      return l.nameRu.toLowerCase().contains(q) ||
          l.countryCode.toLowerCase().contains(q);
    }).toList();

    if (xplm) {
      final scaffold = Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Серверы'),
          automaticallyImplyLeading: !widget.embeddedInShell,
          leading: widget.embeddedInShell
              ? null
              : IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                  onPressed: () => Navigator.of(context).pop(),
                ),
          actions: [
            IconButton(
              tooltip: 'Поиск',
              onPressed: () => setState(() => _searchOpen = !_searchOpen),
              icon: const Text(
                '⌕',
                style: TextStyle(color: Color(0xFF96B3D1), fontSize: 20),
              ),
            ),
          ],
        ),
        body: Stack(
          children: [
            const Positioned(
              left: 0,
              right: 0,
              bottom: -40,
              height: 220,
              child: Opacity(
                opacity: 0.55,
                child: XplmEarthBackdrop(
                  width: 400,
                  height: 240,
                  rotate: -6,
                ),
              ),
            ),
            Column(
              children: [
                SizedBox(
                  height: 42,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                    children: [
                      for (final entry in [
                        (_RegionChip.all, 'Все страны'),
                        (_RegionChip.europe, 'Европа'),
                        (_RegionChip.asia, 'Азия'),
                        (_RegionChip.northAmerica, 'Северная Америка'),
                      ]) ...[
                        Padding(
                          padding: const EdgeInsets.only(right: 5),
                          child: _CodexChip(
                            label: entry.$2,
                            selected: _chip == entry.$1,
                            onTap: () => setState(() => _chip = entry.$1),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_searchOpen)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: TextField(
                      controller: _search,
                      autofocus: true,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Найти страну',
                        filled: true,
                        fillColor: const Color(0xFF06172D),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: Color(0xFF1B466B)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: locations.isEmpty
                      ? const Center(
                          child: Text(
                            'Страна не найдена',
                            style: TextStyle(color: XplmColors.ink3),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                          itemCount: locations.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 5),
                          itemBuilder: (context, index) {
                            final server = locations[index];
                            final selected = server.id == selectedId;
                            return _CodexServerRow(
                              server: server,
                              selected: selected,
                              autoLabel: s.auto,
                              onTap: () {
                                controller.selectLocation(server);
                                if (!widget.embeddedInShell &&
                                    Navigator.of(context).canPop()) {
                                  Navigator.of(context).pop();
                                }
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ],
        ),
      );
      if (widget.embeddedInShell) return scaffold;
      return NordBackground(child: scaffold);
    }

    final scaffold = Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(s.location),
        automaticallyImplyLeading: !widget.embeddedInShell,
        leading: widget.embeddedInShell
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                onPressed: () => Navigator.of(context).pop(),
              ),
      ),
      body: Column(
        children: [
          Expanded(
            child: locations.isEmpty
                ? Center(
                    child: Text(
                      'Нет серверов',
                      style: TextStyle(color: muted),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                    itemCount: locations.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final server = locations[index];
                      final selected = server.id == selectedId;
                      final radius = BorderRadius.circular(12);
                      return Material(
                        color: selected
                            ? elevated
                            : surface.withValues(alpha: 0.65),
                        borderRadius: radius,
                        child: InkWell(
                          borderRadius: radius,
                          onTap: () => controller.selectLocation(server),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: radius,
                              border: Border(
                                left: BorderSide(
                                  width: 3,
                                  color: selected
                                      ? accent
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        server.isAuto
                                            ? s.auto
                                            : server.nameRu,
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
                                      color: selected ? accent : secondary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                if (server.isAuto)
                                  Text(
                                    s.recommended,
                                    style: TextStyle(
                                      color: accent,
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
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
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
                      backgroundColor: accentFill,
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
                      if (!widget.embeddedInShell &&
                          Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      }
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
    );
    if (widget.embeddedInShell) return scaffold;
    return NordBackground(child: scaffold);
  }
}

class _CodexChip extends StatelessWidget {
  const _CodexChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: selected
                ? const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF02AAFF), Color(0xFF007EE6)],
                  )
                : const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF263C58), Color(0xFF111F35)],
                  ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: const Color(0xFF008BFF).withValues(alpha: 0.4),
                      blurRadius: 9,
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : const Color(0xFF9BABBE),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _CodexServerRow extends StatelessWidget {
  const _CodexServerRow({
    required this.server,
    required this.selected,
    required this.autoLabel,
    required this.onTap,
  });

  final ServerLocation server;
  final bool selected;
  final String autoLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? const Color(0xFF30BAFF) : Colors.transparent,
            ),
            gradient: selected
                ? const LinearGradient(
                    begin: Alignment(-0.8, 0),
                    end: Alignment(0.9, 0),
                    colors: [Color(0xFF06416A), Color(0xFF002345)],
                  )
                : LinearGradient(
                    begin: Alignment(-0.8, 0),
                    end: Alignment(0.9, 0),
                    colors: [
                      const Color(0xFF0C2441).withValues(alpha: 0.33),
                      const Color(0xFF020D1E).withValues(alpha: 0.33),
                    ],
                  ),
            boxShadow: selected
                ? [
                    const BoxShadow(
                      color: Color(0xFF009DFF),
                      blurRadius: 8,
                    ),
                    BoxShadow(
                      color: const Color(0xFF0088FF).withValues(alpha: 0.53),
                      blurRadius: 8,
                      spreadRadius: -2,
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              XplmFlagCircle(
                code: server.isAuto ? 'auto' : server.countryCode,
                size: 34,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      server.isAuto ? autoLabel : server.nameRu,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (!server.isAuto && server.latencyMs >= 0)
                      Text(
                        '${server.latencyMs} ms',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF91A5BF),
                        ),
                      ),
                  ],
                ),
              ),
              if (!server.isAuto && server.latencyMs >= 0)
                XplmSignalBars(latencyMs: server.latencyMs),
              const SizedBox(width: 8),
              if (selected)
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF06BAFF),
                    boxShadow: [
                      BoxShadow(color: Color(0xFF00BFFF), blurRadius: 8),
                    ],
                  ),
                  child: const Text(
                    '✓',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                )
              else
                const SizedBox(
                  width: 17,
                  child: Text(
                    '›',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF8AA4C2),
                      fontSize: 23,
                      height: 1,
                    ),
                  ),
                ),
            ],
          ),
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
