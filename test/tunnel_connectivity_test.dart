import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_vpn/core/services/tunnel_connectivity.dart';

void main() {
  test('both endpoints must succeed — first alone is not enough', () async {
    final called = <String>[];
    await expectLater(
      verifyTunnelConnectivity(
        settle: Duration.zero,
        attemptsPerEndpoint: 1,
        probe: (endpoint) async {
          called.add(endpoint.host);
          return endpoint.host == 'www.gstatic.com';
        },
      ),
      throwsA(isA<StateError>()),
    );
    expect(called, ['www.gstatic.com', 'www.cloudflare.com']);
  });

  test('both endpoints succeeding marks connectivity ok', () async {
    final called = <String>[];
    await verifyTunnelConnectivity(
      settle: Duration.zero,
      attemptsPerEndpoint: 1,
      probe: (endpoint) async {
        called.add(endpoint.host);
        return true;
      },
    );
    expect(called, ['www.gstatic.com', 'www.cloudflare.com']);
  });

  test('retries flaky first attempt before failing endpoint', () async {
    final called = <String>[];
    await verifyTunnelConnectivity(
      settle: Duration.zero,
      attemptsPerEndpoint: 2,
      probe: (endpoint) async {
        called.add(endpoint.host);
        // Fail first gstatic attempt, then succeed both hosts.
        if (endpoint.host == 'www.gstatic.com' &&
            called.where((h) => h == 'www.gstatic.com').length == 1) {
          return false;
        }
        return true;
      },
    );
    expect(
      called,
      ['www.gstatic.com', 'www.gstatic.com', 'www.cloudflare.com'],
    );
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
