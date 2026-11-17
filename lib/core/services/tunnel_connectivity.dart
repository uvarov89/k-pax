import 'dart:convert';
import 'dart:io';

import 'package:pulse_vpn/core/services/tunnel_config.dart';

typedef TunnelProbe = Future<bool> Function(Uri endpoint);

/// Post-connect data-plane check. Verifies that a real HTTPS request works
/// through platform networking after TUN start; does not independently prove
/// the requested VPN exit IP (that needs device-level leak testing).
///
/// Both endpoints must succeed — a single clearnet hit must not mark Connected.
Future<void> verifyTunnelConnectivity({
  TunnelProbe? probe,
  // TUN/Wintun routes lag Clash/VPN "Started". Short settles caused false
  // Connected while Telegram/DNS still blackholed (Hiddify waits longer).
  Duration settle = const Duration(seconds: 2),
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
    var ok = false;
    for (var attempt = 0; attempt < attemptsPerEndpoint; attempt++) {
      try {
        if (await test(endpoint)) {
          ok = true;
          break;
        }
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
    if (!ok && !failures.any((f) => f.startsWith('${endpoint.host}:'))) {
      failures.add('${endpoint.host}: unexpected response');
    }
  }
  if (failures.isNotEmpty) {
    throw StateError(
      'VPN-движок запущен, но доступ к интернету не подтверждён: '
      '${failures.join('; ')}',
    );
  }
}

/// Fail-closed proof that Clash saw bytes (or a live connection) after HTTPS.
/// Host HttpClient can succeed on clearnet while TUN/proxy is empty.
Future<void> assertClashSawProxyTraffic(
  String secret, {
  int port = kClashPort,
  Duration timeout = const Duration(seconds: 2),
}) async {
  if (secret.isEmpty) {
    throw StateError(
      'Туннель поднят, но Clash secret отсутствует — proxy не проверен',
    );
  }
  final client = HttpClient()
    ..connectionTimeout = timeout
    ..idleTimeout = timeout;
  try {
    final request = await client
        .getUrl(Uri.parse('http://127.0.0.1:$port/connections'))
        .timeout(timeout);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
    final response = await request.close().timeout(timeout);
    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(timeout);
    if (response.statusCode != HttpStatus.ok) {
      throw StateError(
        'Clash API недоступен (${response.statusCode}) — proxy не проверен',
      );
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw StateError('Clash /connections: неожиданный ответ');
    }
    final downloadTotal = (decoded['downloadTotal'] as num?)?.toInt() ?? 0;
    final uploadTotal = (decoded['uploadTotal'] as num?)?.toInt() ?? 0;
    final connections = decoded['connections'];
    final hasProxyConn = connections is List &&
        connections.any((c) {
          if (c is! Map) return false;
          final chains = c['chains'];
          if (chains is List) {
            return chains.any((x) => '$x' == 'proxy');
          }
          final chain = '${c['chain'] ?? ''}';
          return chain.contains('proxy');
        });
    final hasConn = connections is List && connections.isNotEmpty;
    if (downloadTotal > 0 || uploadTotal > 0 || hasProxyConn || hasConn) {
      return;
    }
    throw StateError(
      'Туннель поднят, но трафик через proxy не зафиксирован (проверьте узел)',
    );
  } on StateError {
    rethrow;
  } catch (error) {
    throw StateError(
      'Clash API недоступен (${error.runtimeType}) — proxy не проверен',
    );
  } finally {
    client.close(force: true);
  }
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
