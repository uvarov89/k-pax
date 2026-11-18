import 'dart:convert';
import 'dart:io';

import 'package:pulse_vpn/core/services/tunnel_config.dart';

typedef TunnelProbe = Future<bool> Function(Uri endpoint);

/// Light post-connect check. 1.0.50 had none (Started == Connected).
/// Keep a short settle + first-success HTTPS probe for failover only.
/// Pair with [assertClashSawProxyTraffic] so a clearnet leak cannot mark
/// Connected while TUN blackholes the rest of the device.
Future<void> verifyTunnelConnectivity({
  TunnelProbe? probe,
  Duration settle = const Duration(milliseconds: 300),
  int attemptsPerEndpoint = 1,
}) async {
  final test = probe ?? _probeHttps;
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
          await Future<void>.delayed(const Duration(milliseconds: 200));
          continue;
        }
        failures.add('${endpoint.host}: unexpected response');
      } catch (error) {
        if (attempt + 1 < attemptsPerEndpoint) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
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

/// SoftProbe then prove the bytes went through Clash (not a clearnet leak).
/// If Clash API is unreachable (Android VPN-process isolation), SoftProbe alone
/// still gates connect — do not hard-fail the whole path.
Future<void> verifyTunnelConnectivityViaProxy({
  required String clashSecret,
  TunnelProbe? probe,
}) async {
  await verifyTunnelConnectivity(probe: probe);
  // Give Clash a tick to record the SoftProbe connection.
  await Future<void>.delayed(const Duration(milliseconds: 250));
  try {
    await assertClashSawProxyTraffic(
      clashSecret,
      timeout: const Duration(seconds: 3),
    );
  } on StateError catch (error) {
    final message = error.message;
    if (message.contains('Clash API недоступен') ||
        message.contains('Clash secret отсутствует')) {
      return;
    }
    rethrow;
  }
}

/// Optional Clash proof for diagnostics / Windows traffic UI — not a connect gate.
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
    final body = await response.transform(utf8.decoder).join().timeout(timeout);
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
    final hasConn = connections is List && connections.isNotEmpty;
    if (downloadTotal > 0 || uploadTotal > 0 || hasConn) return;
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
    ..connectionTimeout = const Duration(seconds: 3)
    ..idleTimeout = const Duration(seconds: 3);
  try {
    final request = await client.getUrl(endpoint).timeout(
      const Duration(seconds: 4),
    );
    request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    final response = await request.close().timeout(
      const Duration(seconds: 4),
    );
    if (endpoint.host == 'www.gstatic.com') {
      await response.drain<void>().timeout(const Duration(seconds: 3));
      return response.statusCode == HttpStatus.noContent;
    }
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>().timeout(const Duration(seconds: 3));
      return false;
    }
    final body = await response.transform(utf8.decoder).join().timeout(
      const Duration(seconds: 3),
    );
    return body.contains('ip=') && body.contains('loc=');
  } finally {
    client.close(force: true);
  }
}
