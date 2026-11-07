import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pulse_vpn/core/services/server_latency_monitor.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';

/// Installed above Navigator so pushed server/account routes share the same pings.
class XplmPingScope extends StatefulWidget {
  const XplmPingScope({
    super.key,
    required this.controller,
    required this.child,
    this.createMonitor,
  });
  final VpnController controller;
  final Widget child;
  final ServerLatencyMonitor Function()? createMonitor;
  @override
  State<XplmPingScope> createState() => _XplmPingScopeState();
}

class _XplmPingScopeState extends State<XplmPingScope>
    with WidgetsBindingObserver {
  late final ServerLatencyMonitor _monitor;
  bool _queued = false;
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    _monitor = widget.createMonitor?.call() ?? ServerLatencyMonitor();
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_schedule);
    _schedule();
  }

  @override
  void didUpdateWidget(covariant XplmPingScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_schedule);
      widget.controller.addListener(_schedule);
      _schedule();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  void _schedule() {
    if (_queued) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (mounted) _sync();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _sync() {
    final c = widget.controller;
    final active = c.isConnected ? c.connectedNode : null;
    _monitor.configure(
      scope: c.profile,
      nodes: c.profile?.nodes ?? const [],
      enabled: _foreground && c.hasAccess && !c.isBusy,
      route: '${c.connectionState}|${active?.host}|${active?.port}',
      preferredCountry: active?.countryId ?? c.selectedLocation.id,
      connectedNode: active,
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_schedule);
    WidgetsBinding.instance.removeObserver(this);
    _monitor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ChangeNotifierProvider<ServerLatencyMonitor>.value(
        value: _monitor,
        child: widget.child,
      );
}
