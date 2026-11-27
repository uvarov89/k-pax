import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_vpn/core/services/tunnel_connectivity.dart';

void main() {
  test('first successful endpoint completes the round', () async {
    final called = <String>[];
    await verifyTunnelConnectivity(
      settle: Duration.zero,
      attemptsPerEndpoint: 1,
      probe: (endpoint) async {
        called.add(endpoint.host);
        return endpoint.host == 'www.gstatic.com';
      },
    );
    expect(called, contains('www.gstatic.com'));
  });

  test('succeeds via Cloudflare when gstatic fails', () async {
    await verifyTunnelConnectivity(
      settle: Duration.zero,
      attemptsPerEndpoint: 1,
      probe: (endpoint) async {
        return endpoint.host == 'www.cloudflare.com';
      },
    );
  });

  test('succeeds via cp.cloudflare generate_204 when others fail', () async {
    await verifyTunnelConnectivity(
      settle: Duration.zero,
      attemptsPerEndpoint: 1,
      probe: (endpoint) async {
        return endpoint.host == 'cp.cloudflare.com';
      },
    );
  });

  test('retries a second round after all endpoints fail once', () async {
    var rounds = 0;
    await verifyTunnelConnectivity(
      settle: Duration.zero,
      attemptsPerEndpoint: 2,
      probe: (endpoint) async {
        if (endpoint.host == 'www.gstatic.com') {
          rounds++;
          return rounds >= 2;
        }
        return false;
      },
    );
    expect(rounds, greaterThanOrEqualTo(2));
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

  test('SoftProbe timeout stays fail-fast but above high-RTT floor', () {
    // VN→EU RTT can exceed 1s; 5s burned the hang budget on dead paths.
    expect(kSoftProbeTimeout.inMilliseconds, greaterThanOrEqualTo(2000));
    expect(kSoftProbeTimeout.inMilliseconds, lessThanOrEqualTo(3000));
  });
}
