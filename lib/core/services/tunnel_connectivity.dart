import 'dart:convert';
import 'dart:io';

typedef TunnelProbe = Future<bool> Function(Uri endpoint);

/// Post-connect data-plane check. Verifies that a real HTTPS request works
/// through platform networking after TUN start; does not independently prove
/// the requested VPN exit IP (that needs device-level leak testing).
Future<void> verifyTunnelConnectivity({
  TunnelProbe? probe,
  Duration settle = const Duration(milliseconds: 900),
  int attemptsPerEndpoint = 2,
}) async {
  final test = probe ?? _probeHttps;
  // Require a DNS-resolved HTTPS endpoint: IP-only probes can hide broken DNS.
  final endpoints = <Uri>[
    Uri.parse('https://www.gstatic.com/generate_204'),
    Uri.parse('https://www.cloudflare.com/cdn-cgi/trace'),
  ];
  if (settle > Duration.zero) {
    await Future<void>.delayed(settle);
  }
  final failures = <String>[];
  for (final endpoint in endpoints) {
    for (var attempt = 0; attempt < attemptsPerEndpoint; attempt++) {
      try {
        if (await test(endpoint)) return;
        if (attempt + 1 < attemptsPerEndpoint) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          continue;
        }
        failures.add('${endpoint.host}: unexpected response');
      } catch (error) {
        // Keep tokens, keys, link contents and credentials out of diagnostics.
        if (attempt + 1 < attemptsPerEndpoint) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          continue;
        }
        failures.add('${endpoint.host}: ${error.runtimeType}');
      }
    }
  }
  throw StateError(
    'VPN-движок запущен, но доступ к интернету не подтверждён: '
    '${failures.join('; ')}',
  );
}

Future<bool> _probeHttps(Uri endpoint) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5)
    ..idleTimeout = const Duration(seconds: 5);
  try {
    final request = await client.getUrl(endpoint).timeout(
      const Duration(seconds: 6),
    );
    request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    final response = await request.close().timeout(
      const Duration(seconds: 6),
    );
    if (endpoint.host == 'www.gstatic.com') {
      await response.drain<void>().timeout(const Duration(seconds: 5));
      return response.statusCode == HttpStatus.noContent;
    }
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>().timeout(const Duration(seconds: 5));
      return false;
    }
    final body = await response.transform(utf8.decoder).join().timeout(
      const Duration(seconds: 5),
    );
    return body.contains('ip=') && body.contains('loc=');
  } finally {
    client.close(force: true);
  }
}
