import 'package:pulse_vpn/core/models/connection_models.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';

/// Drop the tunnel before update check/download so a broken VPN cannot block
/// reaching the brand updater or GitHub release assets (catch-22).
Future<void> ensureClearnetForUpdate(VpnController controller) async {
  final state = controller.connectionState;
  if (state == VpnConnectionState.disconnected ||
      state == VpnConnectionState.disconnecting) {
    return;
  }
  await controller.disconnect();
  // Let OS/Wintun/VpnService tear down routes before HTTPS to the updater.
  await Future<void>.delayed(const Duration(milliseconds: 900));
}
