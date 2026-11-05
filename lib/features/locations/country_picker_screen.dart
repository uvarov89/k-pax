import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:pulse_vpn/app/brand/app_brand.dart';
import 'package:pulse_vpn/app/theme/nord_signal_theme.dart';
import 'package:pulse_vpn/app/theme/xplm_colors.dart';
import 'package:pulse_vpn/core/models/connection_models.dart';
import 'package:pulse_vpn/core/models/server_location.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';
import 'package:pulse_vpn/features/xplm/widgets/xplm_codex_widgets.dart';
import 'package:pulse_vpn/features/xplm/widgets/xplm_html_widgets.dart';
import 'package:pulse_vpn/features/account/account_screen.dart';

enum _RegionChip { all, europe, asia, northAmerica }

const _europe = {
  'DE',
  'FI',
  'BG',
  'FR',
  'NL',
  'GB',
  'UK',
  'SE',
  'PL',
  'IT',
  'ES',
  'TR',
  'RU',
  'AT',
  'CH',
  'CZ',
  'RO',
  'UA',
  'LV',
  'LT',
  'EE',
  'PT',
  'IE',
  'NO',
  'DK',
  'HU',
};
const _asia = {
  'SG',
  'JP',
  'KR',
  'CN',
  'MY',
  'AU',
  'IN',
  'HK',
  'TW',
  'TH',
  'VN',
  'ID',
  'PH',
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
        : (isDark
              ? NordColors.surfaceElevated
              : NordColors.lightSurfaceElevated);
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
    final source = controller.locations;
    final locations =
        (xplm ? source.where((l) => !l.isAuto && _matches(l)) : source).where((
          l,
        ) {
          if (q.isEmpty) return true;
          return l.nameRu.toLowerCase().contains(q) ||
              l.countryCode.toLowerCase().contains(q);
        }).toList();

    if (xplm) {
      return XplmHtmlPage(
        title: 'Серверы',
        action: XplmHtmlIconButton(
          icon: Icons.search_rounded,
          tooltip: 'Поиск серверов',
          onPressed: () => setState(() {
            _searchOpen = !_searchOpen;
            if (!_searchOpen) _search.clear();
          }),
        ),
        child: Stack(
          children: [
            const Positioned.fill(child: XplmHtmlEarth(screen: 'servers')),
            Column(
              children: [
                SizedBox(
                  height:
                      60 +
                      (MediaQuery.textScalerOf(context).scale(12) - 12).clamp(
                        0,
                        30,
                      ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(0, 12, 0, 18),
                      children: [
                        for (final entry in [
                          (_RegionChip.all, 'Все страны'),
                          (_RegionChip.europe, 'Европа'),
                          (_RegionChip.asia, 'Азия'),
                          (_RegionChip.northAmerica, 'Северная Америка'),
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 7),
                            child: _CodexChip(
                              label: entry.$2,
                              selected: _chip == entry.$1,
                              onTap: () => setState(() => _chip = entry.$1),
                            ),
                          ),
                        _CodexChip(
                          label: s.auto,
                          selected: selectedId == ServerLocation.auto.id,
                          onTap: () =>
                              controller.selectLocation(ServerLocation.auto),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_searchOpen)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                    child: TextField(
                      controller: _search,
                      autofocus: true,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(
                        fontFamily: 'XplmArial',
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Найти страну',
                        filled: true,
                        fillColor: const Color(0xFF0B2540),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.all(10),
                      ),
                    ),
                  ),
                Expanded(
                  child: locations.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (controller.isRefreshingServers)
                                  const CircularProgressIndicator()
                                else
                                  Text(
                                    source.where((l) => !l.isAuto).isEmpty
                                        ? 'Добавьте подписку в профиле, чтобы загрузить серверы'
                                        : 'Страна не найдена',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: XplmColors.ink3,
                                    ),
                                  ),
                                if (source.where((l) => !l.isAuto).isEmpty &&
                                    !controller.isRefreshingServers)
                                  TextButton(
                                    onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => const AccountScreen(
                                          accountDetails: true,
                                        ),
                                      ),
                                    ),
                                    child: const Text('Добавить подписку'),
                                  ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                          itemCount: locations.length,
                          separatorBuilder: (_, index) => SizedBox(
                            height: locations[index].id == selectedId ? 5 : 0,
                          ),
                          itemBuilder: (context, index) {
                            final server = locations[index];
                            return _CodexServerRow(
                              server: server,
                              selected: server.id == selectedId,
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
                    child: Text('Нет серверов', style: TextStyle(color: muted)),
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
                                  color: selected ? accent : Colors.transparent,
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
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
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
              fontSize: 12,
              fontWeight: FontWeight.w400,
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
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      border: selected
          ? Border.all(color: const Color(0xFF30BAFF))
          : const Border(bottom: BorderSide(color: Color(0xFF152A42))),
      gradient: LinearGradient(
        begin: const Alignment(-.8, 0),
        end: const Alignment(.9, 0),
        colors: selected
            ? const [Color(0xFF06416A), Color(0xFF002345)]
            : const [Color(0x550C2441), Color(0x55020D1E)],
      ),
      boxShadow: selected
          ? const [BoxShadow(color: Color(0xFF009DFF), blurRadius: 8)]
          : null,
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: selected ? 63 : 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            child: Row(
              children: [
                XplmHtmlFlag(code: server.countryCode),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        server.isAuto ? autoLabel : server.nameRu,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      if (!server.isAuto && server.latencyMs >= 0) ...[
                        const SizedBox(height: 3),
                        Text(
                          '${server.latencyMs} ms',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF91A5BF),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (server.latencyMs >= 0)
                  XplmSignalBars(latencyMs: server.latencyMs),
                const SizedBox(width: 12),
                if (selected)
                  Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF06BAFF),
                      boxShadow: [
                        BoxShadow(color: Color(0xFF00BFFF), blurRadius: 8),
                      ],
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                  )
                else
                  const SizedBox(
                    width: 17,
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 21,
                      color: Color(0xFF8AA4C2),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
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
