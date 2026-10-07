import 'package:pulse_vpn/core/models/app_settings.dart';
import 'package:pulse_vpn/core/models/connection_models.dart';
import 'package:pulse_vpn/core/models/server_location.dart';
import 'package:pulse_vpn/core/models/tunnel_node.dart';

/// Contract for the future native tunnel (sing-box / VpnService / NE).
/// UI talks only to this interface — swap [MockVpnService] for a real engine later.
abstract class VpnService {
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
