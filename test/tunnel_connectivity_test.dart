import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_vpn/core/services/tunnel_connectivity.dart';

void main() {
  test('successful first HTTPS check skips the backup', () async {
    final called = <String>[];
    await verifyTunnelConnectivity(
      settle: Duration.zero,
      attemptsPerEndpoint: 1,
      probe: (endpoint) async {
        called.add(endpoint.host);
        return true;
      },
    );
    expect(called, ['www.gstatic.com']);
  });

  test('backup DNS endpoint is checked if first fails', () async {
    final called = <String>[];
    await verifyTunnelConnectivity(
      settle: Duration.zero,
      attemptsPerEndpoint: 1,
      probe: (endpoint) async {
        called.add(endpoint.host);
        return endpoint.host == 'www.cloudflare.com';
      },
    );
    expect(called, ['www.gstatic.com', 'www.cloudflare.com']);
  });

  test('retries flaky first attempt before failing over', () async {
    final called = <String>[];
    await verifyTunnelConnectivity(
      settle: Duration.zero,
      attemptsPerEndpoint: 2,
      probe: (endpoint) async {
        called.add(endpoint.host);
        return called.length >= 2;
      },
    );
    expect(called, ['www.gstatic.com', 'www.gstatic.com']);
  });

  test('no traffic does not produce a false connected result', () async {
    await expectLater(
      verifyTunnelConnectivity(
        settle: Duration.zero,
        attemptsPerEndpoint: 1,
        probe: (_) async => false,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('assertClashSawProxyTraffic rejects empty secret', () async {
    await expectLater(
      assertClashSawProxyTraffic(''),
      throwsA(isA<StateError>()),
    );
  });
}
