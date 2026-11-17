import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_vpn/core/models/connection_models.dart';
import 'package:pulse_vpn/core/services/update_clearnet.dart';
import 'package:pulse_vpn/core/services/vpn_service.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';

void main() {
  test('withUpdateNetworkRetry keeps tunnel when first attempt works', () async {
    final controller = VpnController(service: MockVpnService());
    controller.connectionState = VpnConnectionState.connected;
    var calls = 0;
    final value = await withUpdateNetworkRetry(
      controller,
      () async {
        calls += 1;
        return 'ok';
      },
      failed: (v) => v != 'ok',
    );
    expect(value, 'ok');
    expect(calls, 1);
    expect(controller.connectionState, VpnConnectionState.connected);
  });
}
