import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_vpn/core/services/tunnel_connectivity.dart';

void main() {
  test('successful DNS HTTPS check skips the backup', () async {
    final called = <String>[];
    await verifyTunnelConnectivity(probe: (endpoint) async {
      called.add(endpoint.host);
      return true;
    });
    expect(called, ['www.gstatic.com']);
  });

  test('backup DNS endpoint is checked if first fails', () async {
    final called = <String>[];
    await verifyTunnelConnectivity(probe: (endpoint) async {
      called.add(endpoint.host);
      return endpoint.host == 'www.cloudflare.com';
    });
    expect(called, ['www.gstatic.com', 'www.cloudflare.com']);
  });

  test('no traffic does not produce a false connected result', () async {
    await expectLater(
      verifyTunnelConnectivity(probe: (_) async => false),
      throwsA(isA<StateError>()),
    );
  });
}
