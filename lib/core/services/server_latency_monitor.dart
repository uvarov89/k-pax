import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:pulse_vpn/core/models/tunnel_node.dart';
import 'package:pulse_vpn/core/services/tunnel_config.dart';

typedef LatencyProbe = Future<int?> Function(String host, int port);

/// Measures server TCP reachability independently of tunnel connect/disconnect.
/// Results belong to a subscription and routing context, never to a display name.
class ServerLatencyMonitor extends ChangeNotifier {
  ServerLatencyMonitor({
    LatencyProbe? probe,
    this.refreshInterval = const Duration(seconds: 30),
  }) : _probe = probe ?? measureTcp;
  final LatencyProbe _probe;
  final Duration refreshInterval;
  final Map<String, int> _results = {};
  final Set<String> _pending = {};
  List<TunnelNode> _targets = const [];
  Object? _scope;
  String _route = '';
  String? _preferred;
  bool _enabled = false;
  bool _disposed = false;
  int _revision = 0;
  Timer? _timer;
  Future<void>? _inFlight;

  int? pingFor(String countryId) => _results[countryId];
  bool isPending(String countryId) => _pending.contains(countryId);
  int? get bestPing {
    final available = _results.values.where((ms) => ms >= 0);
    return available.isEmpty ? null : available.reduce((a, b) => a < b ? a : b);
  }

  bool get isMeasuring => _pending.isNotEmpty;

  static int _rank(TunnelKind kind) => switch (kind) {
    TunnelKind.reality => 0,
    TunnelKind.grpc => 1,
    TunnelKind.hy2 => 2,
    TunnelKind.tuic => 3,
    TunnelKind.message => 4,
  };
  static String _key(TunnelNode node) =>
      '${node.countryId}|${node.kind}|${node.host}|${node.port}';

  void configure({
    required Object? scope,
    required List<TunnelNode> nodes,
    required bool enabled,
    String route = '',
    String? preferredCountry,
    TunnelNode? connectedNode,
  }) {
    if (_disposed) return;
    final byCountry = <String, TunnelNode>{};
    for (final node in nodes) {
      if (node.kind == TunnelKind.message) continue;
      final current = byCountry[node.countryId];
      if (current == null || _rank(node.kind) < _rank(current.kind)) {
        byCountry[node.countryId] = node;
      }
    }
    if (connectedNode != null && connectedNode.kind != TunnelKind.message) {
      byCountry[connectedNode.countryId] = connectedNode;
    }
    final targets = byCountry.values.toList();
    final changed =
        !identical(scope, _scope) ||
        route != _route ||
        enabled != _enabled ||
        !listEquals(targets.map(_key).toList(), _targets.map(_key).toList());
    final selectionChanged = preferredCountry != _preferred;
    _preferred = preferredCountry;
    _targets = targets;
    if (!changed) {
      if (selectionChanged && enabled) {
        unawaited(refresh(countryId: preferredCountry));
      }
      return;
    }
    _scope = scope;
    _route = route;
    _enabled = enabled;
    _revision++;
    _inFlight = null;
    _timer?.cancel();
    _results.clear();
    _pending.clear();
    notifyListeners();
    if (!enabled || targets.isEmpty) return;
    unawaited(refresh());
    _timer = Timer.periodic(refreshInterval, (_) => unawaited(refresh()));
  }

  Future<void> refresh({String? countryId}) {
    if (_disposed || !_enabled || _targets.isEmpty) return Future<void>.value();
    if (countryId != null) _preferred = countryId;
    if (_inFlight != null) return _inFlight!;
    final revision = _revision;
    return _inFlight = _run(revision).whenComplete(() {
      if (!_disposed && revision == _revision) _inFlight = null;
    });
  }

  bool _current(int revision) =>
      !_disposed && _enabled && revision == _revision;
  Future<void> _run(int revision) async {
    final remaining = _targets.toList();
    _pending.addAll(remaining.map((n) => n.countryId));
    notifyListeners();
    while (remaining.isNotEmpty && _current(revision)) {
      var index = remaining.indexWhere((n) => n.countryId == _preferred);
      if (index < 0) index = 0;
      final node = remaining.removeAt(index);
      int? value;
      try {
        value = await _probe(
          node.host,
          node.port == 0 ? 443 : node.port,
        ).timeout(const Duration(seconds: 4), onTimeout: () => null);
      } catch (_) {
        value = null;
      }
      if (!_current(revision)) return;
      _results[node.countryId] = value != null && value >= 0 ? value : -1;
      _pending.remove(node.countryId);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    _timer?.cancel();
    _pending.clear();
    super.dispose();
  }
}
