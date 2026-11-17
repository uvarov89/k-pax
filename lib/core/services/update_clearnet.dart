import 'package:pulse_vpn/core/models/connection_models.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';

/// Brand updater + GitHub release CDN are already routed **direct** in
/// tunnel config. Prefer that path first.
///
/// Force-disconnecting for updates backfires when Android Always-on VPN /
/// "Block connections without VPN" leaves the device with no network after
/// [VpnController.disconnect] — check finds an update, download says offline.
Future<void> ensureClearnetForUpdate(VpnController controller) async {
  // Stay connected by default. Use [forceClearnetForUpdate] only on retry.
}

/// Last-resort: drop the tunnel so a fully blackholed VPN cannot block HTTPS.
Future<void> forceClearnetForUpdate(VpnController controller) async {
  final state = controller.connectionState;
  if (state == VpnConnectionState.disconnected ||
      state == VpnConnectionState.disconnecting) {
    return;
  }
  await controller.disconnect();
  // Always-on / Wintun teardown needs more than a blink before HttpClient.
  await Future<void>.delayed(const Duration(milliseconds: 1800));
}

/// Run [action] while the tunnel may stay up. On [failed], disconnect once and
/// retry — covers a broken proxy without Always-on blackhole on the first try.
Future<T> withUpdateNetworkRetry<T>(
  VpnController controller,
  Future<T> Function() action, {
  required bool Function(T value) failed,
}) async {
  final first = await action();
  if (!failed(first)) return first;
  if (controller.connectionState == VpnConnectionState.disconnected ||
      controller.connectionState == VpnConnectionState.disconnecting) {
    return first;
  }
  await forceClearnetForUpdate(controller);
  return action();
}
