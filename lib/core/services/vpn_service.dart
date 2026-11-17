import 'package:pulse_vpn/core/models/app_settings.dart';
import 'package:pulse_vpn/core/models/connection_models.dart';
import 'package:pulse_vpn/core/models/server_location.dart';
import 'package:pulse_vpn/core/models/tunnel_node.dart';

/// Post-connect data-plane check. Mock stays without it; Android/Windows/iOS implement.
abstract interface class TunnelConnectivityVerifier {
  Future<void> verifyConnectivity();
}

/// Optional native settings support, separate from the tunnel contract.
abstract interface class VpnSettingsService {
  Future<void> applyAppSettings(AppSettings settings);
  Future<void> clearSavedAccess();
}

class TunnelSpeed {
  const TunnelSpeed({
    required this.upBytesPerSec,
    required this.downBytesPerSec,
    this.upBytesTotal = 0,
    this.downBytesTotal = 0,
  });

  final int upBytesPerSec;
  final int downBytesPerSec;
  final int upBytesTotal;
  final int downBytesTotal;
}

/// Libbox often reports zero instant rates while totals still move.
/// Derive B/s from cumulative counters when platform speeds stay at 0.
class TunnelSpeedTracker {
  int _lastUpTotal = 0;
  int _lastDownTotal = 0;
  DateTime? _lastAt;

  TunnelSpeed ingest({
    required int upRate,
    required int downRate,
    int upTotal = 0,
    int downTotal = 0,
  }) {
    var up = upRate < 0 ? 0 : upRate;
    var down = downRate < 0 ? 0 : downRate;
    final now = DateTime.now();
    final prevAt = _lastAt;
    if (up == 0 &&
        down == 0 &&
        prevAt != null &&
        (upTotal > _lastUpTotal || downTotal > _lastDownTotal)) {
      final dtMs = now.difference(prevAt).inMilliseconds;
      if (dtMs > 0) {
        final dUp = upTotal - _lastUpTotal;
        final dDown = downTotal - _lastDownTotal;
        if (dUp > 0) up = ((dUp * 1000) / dtMs).round();
        if (dDown > 0) down = ((dDown * 1000) / dtMs).round();
      }
    }
    if (upTotal >= _lastUpTotal) _lastUpTotal = upTotal;
    if (downTotal >= _lastDownTotal) _lastDownTotal = downTotal;
    _lastAt = now;
    return TunnelSpeed(
      upBytesPerSec: up,
      downBytesPerSec: down,
      upBytesTotal: upTotal,
      downBytesTotal: downTotal,
    );
  }

  void reset() {
    _lastUpTotal = 0;
    _lastDownTotal = 0;
    _lastAt = null;
  }
}

/// Contract for the future native tunnel (sing-box / VpnService / NE).
/// UI talks only to this interface — swap [MockVpnService] for a real engine later.
abstract class VpnService {
  Stream<String> get statusStream => const Stream.empty();

  Stream<TunnelSpeed> get trafficStream => const Stream<TunnelSpeed>.empty();

  Future<void> connect({
    required ServerLocation location,
    required ProSettings settings,
    required AppSettings appSettings,
    required TunnelNode node,
  });

  Future<void> disconnect();

  /// Optional node probe for Pro diagnostics.
  Future<Map<String, int>> probeNodes();
}

/// Simulated tunnel until servers and libbox are integrated.
class MockVpnService implements VpnService {
  @override
  Stream<String> get statusStream => const Stream.empty();

  @override
  Stream<TunnelSpeed> get trafficStream => const Stream<TunnelSpeed>.empty();

  @override
  Future<void> connect({
    required ServerLocation location,
    required ProSettings settings,
    required AppSettings appSettings,
    required TunnelNode node,
  }) async {
    // appSettings.splitTunnelMode / packages will drive
    // VpnService.Builder addAllowed/DisallowedApplication later.
    await Future<void>.delayed(const Duration(milliseconds: 1400));
  }

  @override
  Future<void> disconnect() async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }

  @override
  Future<Map<String, int>> probeNodes() async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    return {
      for (final server in ServerLocation.catalog.where((s) => !s.isAuto))
        server.id: server.latencyMs + (server.id.hashCode % 7),
    };
  }
}
