import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pulse_vpn/core/services/tunnel_config.dart';

typedef TunnelProbe = Future<bool> Function(Uri endpoint);

/// Light post-connect check. 1.0.50 had none (Started == Connected).
/// Endpoints race in parallel (first success wins) so a blocked gstatic in RU
/// does not burn the hang budget before Cloudflare answers.
/// Settle must cover Android TUN/DNS lag after VPNStatus.STARTED — 300ms/1
/// attempt produced false [probe_fail] while panel TCP autotest stayed ok.
/// Two-hop RU front→EU needs extra settle (MSC field 2026-11-26); keep
/// fail-fast in probe timeouts, not by cutting settle below ~1.2s.
/// Pair with [assertClashSawProxyTraffic] so a clearnet leak cannot mark
/// Connected while TUN blackholes the rest of the device.
Future<void> verifyTunnelConnectivity({
  TunnelProbe? probe,
  Duration settle = const Duration(milliseconds: 1300),
  int attemptsPerEndpoint = 2,
}) async {
  final test = probe ?? _probeHttps;
  final endpoints = <Uri>[
    Uri.parse('https://www.gstatic.com/generate_204'),
    Uri.parse('https://cp.cloudflare.com/generate_204'),
    Uri.parse('https://www.cloudflare.com/cdn-cgi/trace'),
  ];
  if (settle > Duration.zero) {
    await Future<void>.delayed(settle);
  }
  final failures = <String>[];
  for (var attempt = 0; attempt < attemptsPerEndpoint; attempt++) {
    final round = await _raceProbes(endpoints, test);
    if (round.ok) return;
    failures
      ..clear()
      ..addAll(round.failures);
    if (attempt + 1 < attemptsPerEndpoint) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }
  throw StateError(
    'VPN-движок запущен, но доступ к интернету не подтверждён: '
    '${failures.join('; ')}',
  );
}

class _ProbeRound {
  const _ProbeRound({required this.ok, required this.failures});
  final bool ok;
  final List<String> failures;
}

/// First successful probe completes the round; others are cancelled by ignoring
/// late results. All must fail before the round is considered failed.
Future<_ProbeRound> _raceProbes(
  List<Uri> endpoints,
  TunnelProbe test,
) async {
  final done = Completer<_ProbeRound>();
  var remaining = endpoints.length;
  final failures = <String>[];

  for (final endpoint in endpoints) {
    unawaited(() async {
      try {
        if (await test(endpoint)) {
          if (!done.isCompleted) {
            done.complete(const _ProbeRound(ok: true, failures: []));
          }
          return;
        }
        failures.add('${endpoint.host}: unexpected response');
      } catch (error) {
        failures.add('${endpoint.host}: ${error.runtimeType}');
      } finally {
        remaining--;
        if (remaining == 0 && !done.isCompleted) {
          done.complete(
            _ProbeRound(ok: false, failures: List<String>.from(failures)),
          );
        }
      }
    }());
  }

  return done.future;
}

/// SoftProbe then prove the bytes went through Clash (not a clearnet leak).
/// If Clash API is unreachable (Android VPN-process isolation), SoftProbe alone
/// still gates connect — do not hard-fail the whole path.
/// Empty Clash counters right after SoftProbe are common; retry before failing
/// over (false [probe_fail] with healthy TCP was filling the admin feed).
/// SoftProbe already pushed bytes — first Clash poll can be quick (200ms).
Future<void> verifyTunnelConnectivityViaProxy({
  required String clashSecret,
  TunnelProbe? probe,
  int clashProofAttempts = 3,
}) async {
  await verifyTunnelConnectivity(probe: probe);
  Object? lastError;
  for (var attempt = 0; attempt < clashProofAttempts; attempt++) {
    await Future<void>.delayed(
      Duration(milliseconds: attempt == 0 ? 300 : 500),
    );
    try {
      await assertClashSawProxyTraffic(
        clashSecret,
        timeout: const Duration(seconds: 2),
      );
      return;
    } on StateError catch (error) {
      final message = error.message;
      if (message.contains('Clash API недоступен') ||
          message.contains('Clash secret отсутствует')) {
        return;
      }
      lastError = error;
    }
  }
  if (lastError != null) throw lastError;
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

bool _isGenerate204(Uri endpoint) {
  final path = endpoint.path;
  return path.endsWith('/generate_204') || path.endsWith('/gen_204');
}

/// Per-endpoint SoftProbe budget. Race of 3 means wall-clock ≈ this timeout on
/// full fail (not 3×). Two-hop front→relay→EU from RF often needs ~3s; dead
/// :443 still fails fast enough to hop.
const Duration kSoftProbeTimeout = Duration(milliseconds: 3000);

Future<bool> _probeHttps(Uri endpoint) async {
  final client = HttpClient()
    ..connectionTimeout = kSoftProbeTimeout
    ..idleTimeout = kSoftProbeTimeout;
  try {
    final request = await client.getUrl(endpoint).timeout(kSoftProbeTimeout);
    request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    final response = await request.close().timeout(kSoftProbeTimeout);
    if (_isGenerate204(endpoint)) {
      await response.drain<void>().timeout(kSoftProbeTimeout);
      // Some captive endpoints return 204; others 200 with empty body.
      return response.statusCode == HttpStatus.noContent ||
          response.statusCode == HttpStatus.ok;
    }
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>().timeout(kSoftProbeTimeout);
      return false;
    }
    final body = await response.transform(utf8.decoder).join().timeout(
      kSoftProbeTimeout,
    );
    return body.contains('ip=') && body.contains('loc=');
  } finally {
    client.close(force: true);
  }
}
