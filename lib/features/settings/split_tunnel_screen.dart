import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pulse_vpn/app/theme/nord_signal_theme.dart';
import 'package:pulse_vpn/core/models/split_tunnel.dart';
import 'package:pulse_vpn/core/services/installed_apps_catalog.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';
import 'dart:typed_data';

class SplitTunnelScreen extends StatefulWidget {
  const SplitTunnelScreen({super.key});

  @override
  State<SplitTunnelScreen> createState() => _SplitTunnelScreenState();
}

class _SplitTunnelScreenState extends State<SplitTunnelScreen> {
  final _catalog = InstalledAppsCatalog();
  final _search = TextEditingController();

  List<InstalledAppItem> _apps = [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadApps();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadApps() async {
    setState(() => _loading = true);
    final apps = await _catalog.load(withIcons: true);
    if (!mounted) return;
    setState(() {
      _apps = apps;
      _loading = false;
    });
  }

  List<InstalledAppItem> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _apps;
    return _apps
        .where(
          (app) =>
              app.name.toLowerCase().contains(q) ||
              app.packageName.toLowerCase().contains(q),
        )
        .toList();
  }

  Future<void> _setMode(SplitTunnelMode mode) async {
    final controller = context.read<VpnController>();
    final settings = controller.appSettings;
    await controller.updateAppSettings(settings.copyWith(splitTunnelMode: mode));
  }

  Future<void> _togglePackage(String packageName) async {
    final controller = context.read<VpnController>();
    final settings = controller.appSettings;
    final selected = [...settings.splitTunnelPackages];
    if (selected.contains(packageName)) {
      selected.remove(packageName);
    } else {
      selected.add(packageName);
    }
    await controller.updateAppSettings(
      settings.copyWith(splitTunnelPackages: selected),
    );
  }

  Future<void> _addSuggested() async {
    final controller = context.read<VpnController>();
    final settings = controller.appSettings;
    final installed = _apps.map((e) => e.packageName).toSet();
    final next = {...settings.splitTunnelPackages};
    for (final pkg in suggestedBypassPackages) {
      if (installed.contains(pkg)) next.add(pkg);
    }
    await controller.updateAppSettings(
      settings.copyWith(
        splitTunnelMode: SplitTunnelMode.excludeSelected,
        splitTunnelPackages: next.toList()..sort(),
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(controller.strings.splitSuggestedAdded)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VpnController>();
    final s = controller.strings;
    final settings = controller.appSettings;
    final mode = settings.splitTunnelMode;
    final selected = settings.splitTunnelPackages.toSet();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? NordColors.textMuted : NordColors.lightTextMuted;
    final surface =
        isDark ? NordColors.surface : NordColors.lightSurface;
    final border = isDark ? NordColors.border : NordColors.lightBorder;
    final secondary =
        isDark ? NordColors.textSecondary : NordColors.lightTextSecondary;

    return NordBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(s.splitTunneling),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.splitTunnelHint,
                    style: TextStyle(color: muted, height: 1.35),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: surface.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: border),
                    ),
                    child: Column(
                      children: [
                        _ModeTile(
                          title: s.splitModeAll,
                          subtitle: s.splitModeAllHint,
                          selected: mode == SplitTunnelMode.allApps,
                          onTap: () => _setMode(SplitTunnelMode.allApps),
                        ),
                        const Divider(height: 1),
                        _ModeTile(
                          title: s.splitModeExclude,
                          subtitle: s.splitModeExcludeHint,
                          selected: mode == SplitTunnelMode.excludeSelected,
                          onTap: () =>
                              _setMode(SplitTunnelMode.excludeSelected),
                        ),
                        const Divider(height: 1),
                        _ModeTile(
                          title: s.splitModeInclude,
                          subtitle: s.splitModeIncludeHint,
                          selected: mode == SplitTunnelMode.includeOnly,
                          onTap: () => _setMode(SplitTunnelMode.includeOnly),
                        ),
                      ],
                    ),
                  ),
                  if (mode != SplitTunnelMode.allApps) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text(
                          s.splitSelectedCount(selected.length),
                          style: TextStyle(
                            color: secondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: _loading ? null : _addSuggested,
                          child: Text(s.splitAddSuggested),
                        ),
                      ],
                    ),
                    TextField(
                      controller: _search,
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        hintText: s.splitSearchHint,
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: surface.withValues(alpha: 0.9),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: border),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (mode == SplitTunnelMode.allApps)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      s.splitAllSelectedHint,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: muted),
                    ),
                  ),
                ),
              )
            else if (_loading)
              const Expanded(
                child: Center(child: CircularProgressIndicator()),
              )
            else
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: _filtered.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final app = _filtered[index];
                    final isSelected = selected.contains(app.packageName);
                    return Material(
                      color: surface.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(12),
                      child: CheckboxListTile(
                        value: isSelected,
                        onChanged: (_) => _togglePackage(app.packageName),
                        secondary: _AppIcon(bytes: app.icon),
                        title: Text(
                          app.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          app.packageName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                        activeColor: NordColors.accentDim,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isSelected ? NordColors.accent : border,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  s.splitAppliesNote,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      onTap: onTap,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: selected ? NordColors.accent : NordColors.textMuted,
      ),
    );
  }
}

class _AppIcon extends StatelessWidget {
  const _AppIcon({this.bytes});

  final Uint8List? bytes;

  @override
  Widget build(BuildContext context) {
    if (bytes == null || bytes!.isEmpty) {
      return const CircleAvatar(
        radius: 18,
        backgroundColor: NordColors.surfaceElevated,
        child: Icon(Icons.android, size: 18),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.memory(
        bytes!,
        width: 36,
        height: 36,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => const CircleAvatar(
          radius: 18,
          child: Icon(Icons.android, size: 18),
        ),
      ),
    );
  }
}
