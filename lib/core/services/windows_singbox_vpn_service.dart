import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:pulse_vpn/app/brand/app_brand.dart';
import 'package:pulse_vpn/core/models/app_settings.dart';
import 'package:pulse_vpn/core/models/connection_models.dart';
import 'package:pulse_vpn/core/models/server_location.dart';
import 'package:pulse_vpn/core/models/tunnel_node.dart';
import 'package:pulse_vpn/core/services/tunnel_config.dart';
import 'package:pulse_vpn/core/services/tunnel_connectivity.dart';
import 'package:pulse_vpn/core/services/vpn_service.dart';
import 'package:pulse_vpn/core/services/windows_platform.dart';

/// Windows tunnel: sing-box.exe beside the app, with wintun.dll.
class WindowsSingboxVpnService implements VpnService, TunnelConnectivityVerifier {
  Process? _process;
  HttpClient? _trafficClient;
  final StreamController<String> _status = StreamController<String>.broadcast();
  final StreamController<TunnelSpeed> _traffic = StreamController<TunnelSpeed>.broadcast();
  String _current = 'Stopped';
  String? _clashSecret;
  File? _activeConfig;

  @override
  Stream<String> get statusStream => _status.stream;

  @override
  Stream<TunnelSpeed> get trafficStream => _traffic.stream;

  Directory get _appDir => File(Platform.resolvedExecutable).parent;

  File get _exe => File('${_appDir.path}\\sing-box.exe');

  Directory get _stateDir {
    final base = Platform.environment['LOCALAPPDATA'];
    final root = base ?? Directory.systemTemp.path;
    return Directory('$root\\${AppBrand.current.appName}');
  }

  File get _pidFile => File('${_stateDir.path}\\sing-box.pid');

  String _newClashSecret() {
    final rand = Random.secure();
    final bytes = List<int>.generate(24, (_) => rand.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  void _set(String value) {
    if (_current == value) return;
    _current = value;
    if (!_status.isClosed) _status.add(value);
  }

  Future<void> _wipeConfigFile(File? file) async {
    if (file == null) return;
    try {
      if (await file.exists()) {
        await file.writeAsString('{}');
        await file.delete();
      }
    } catch (_) {}
  }

  /// Restrict tunnel JSON to the current user (removes inherited Everyone read).
  Future<void> _restrictConfigAcl(File file) async {
    final user = Platform.environment['USERNAME'] ??
        Platform.environment['USER'] ??
        '';
    if (user.isEmpty) return;
    try {
      await Process.run('icacls', [
        file.path,
        '/inheritance:r',
        '/grant:r',
        '$user:(R,W)',
      ]).timeout(const Duration(seconds: 3));
    } catch (_) {
      // Best-effort: missing icacls / sandbox must not block connect.
    }
  }

  @override
  Future<void> connect({
    required ServerLocation location,
    required ProSettings settings,
    required AppSettings appSettings,
    required TunnelNode node,
  }) async {
    if (!_exe.existsSync()) {
      throw StateError('sing-box.exe не найден рядом с приложением');
    }
    await disconnect();
    // Remove leftovers from previous releases before starting the engine.
    // If elevation is required, users can run the bundled repair script.
    await WindowsFirewall.clear();
    final dir = _stateDir;
    await dir.create(recursive: true);
    // Prefer wiping leftover plaintext configs from older builds.
    await _wipeConfigFile(File('${dir.path}\\config.json'));
    _clashSecret = _newClashSecret();
    final configId = List<int>.generate(
      8,
      (_) => Random.secure().nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final config = File('${dir.path}\\config-$configId.json');
    _activeConfig = config;
    await config.writeAsString(
      buildTunnelConfig(
        node,
        settings,
        appSettings: appSettings,
        enableStats: true,
        clashSecret: _clashSecret,
      ),
    );
    await _restrictConfigAcl(config);
    _set('Starting');
    final process = await Process.start(
      _exe.path,
      ['run', '-c', config.path, '--directory', dir.path, '--disable-color'],
      workingDirectory: _appDir.path,
    );
    _process = process;
    final stderr = StringBuffer();
    final stderrDone = Completer<void>();
    process.stderr.transform(utf8.decoder).listen(
      stderr.write,
      onDone: () {
        if (!stderrDone.isCompleted) stderrDone.complete();
      },
      onError: (_) {
        if (!stderrDone.isCompleted) stderrDone.complete();
      },
    );
    await _pidFile.writeAsString('${process.pid}');
    final exited = Completer<int>();
    process.exitCode.then((code) {
      if (!exited.isCompleted) exited.complete(code);
      if (identical(_process, process)) {
        _process = null;
        unawaited(_wipeConfigFile(_activeConfig));
        _activeConfig = null;
        _clashSecret = null;
        _set('Stopped');
      }
    });
    try {
      await _waitUntilClashReady(
        process: process,
        exited: exited,
        secret: _clashSecret!,
        stderr: stderr,
        stderrDone: stderrDone,
      );
    } catch (_) {
      if (identical(_process, process)) {
        process.kill();
        _process = null;
      }
      await _wipeConfigFile(_activeConfig);
      _activeConfig = null;
      _clashSecret = null;
      _set('Stopped');
      rethrow;
    }
    if (!identical(_process, process)) return;
    _set('Started');
    unawaited(_pumpTraffic());
  }

  /// Wait until clash API answers so TUN/inbound setup has finished before
  /// [Started] and the post-connect HTTPS probe (avoids "alive 2s" races).
  Future<void> _waitUntilClashReady({
    required Process process,
    required Completer<int> exited,
    required String secret,
    required StringBuffer stderr,
    required Completer<void> stderrDone,
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    final client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 500)
      ..idleTimeout = const Duration(seconds: 2);
    try {
      while (DateTime.now().isBefore(deadline)) {
        if (!identical(_process, process)) return;
        if (exited.isCompleted) {
          await stderrDone.future.timeout(
            const Duration(milliseconds: 400),
            onTimeout: () {},
          );
          final detail =
              stderr.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
          throw StateError(
            detail.isEmpty ? 'Туннель не запустился' : detail,
          );
        }
        try {
          final request = await client
              .getUrl(Uri.parse('http://127.0.0.1:$kClashPort/version'))
              .timeout(const Duration(milliseconds: 800));
          request.headers.set(
            HttpHeaders.authorizationHeader,
            'Bearer $secret',
          );
          final response = await request.close().timeout(
            const Duration(milliseconds: 800),
          );
          await response.drain<void>().timeout(
            const Duration(milliseconds: 800),
            onTimeout: () {},
          );
          if (response.statusCode == HttpStatus.ok) return;
        } catch (_) {
          // Clash API not listening yet (TUN still coming up).
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      throw StateError('Туннель не поднял Clash API за отведённое время');
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _pumpTraffic() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final tracker = TunnelSpeedTracker();
    var sessionUp = 0;
    var sessionDown = 0;
    // Retry while the tunnel lives — a single failed /traffic open used to
    // leave the UI at 0 B/s for the whole session.
    while (_process != null) {
      final secret = _clashSecret;
      if (secret == null || secret.isEmpty) return;
      final client = HttpClient();
      _trafficClient = client;
      try {
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:$kClashPort/traffic'),
        );
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          await response.drain<void>().catchError((_) {});
          throw StateError('clash traffic ${response.statusCode}');
        }
        var buffer = '';
        await for (final chunk in response.transform(utf8.decoder)) {
          if (_process == null) break;
          buffer += chunk;
          while (true) {
            final nl = buffer.indexOf('\n');
            final end = nl >= 0 ? nl : buffer.indexOf('}');
            if (end < 0) break;
            final piece = nl >= 0
                ? buffer.substring(0, nl).trim()
                : buffer.substring(0, end + 1).trim();
            buffer = buffer.substring(end + 1);
            if (piece.isEmpty) continue;
            try {
              final decoded = jsonDecode(piece);
              if (decoded is! Map || _traffic.isClosed) continue;
              final up = (decoded['up'] as num?)?.toInt() ?? 0;
              final down = (decoded['down'] as num?)?.toInt() ?? 0;
              sessionUp += up < 0 ? 0 : up;
              sessionDown += down < 0 ? 0 : down;
              _traffic.add(
                tracker.ingest(
                  upRate: up,
                  downRate: down,
                  upTotal: sessionUp,
                  downTotal: sessionDown,
                ),
              );
            } catch (_) {}
          }
        }
      } catch (_) {
        // Fall through to brief backoff + reconnect.
      } finally {
        client.close(force: true);
        if (identical(_trafficClient, client)) _trafficClient = null;
      }
      if (_process == null) return;
      await Future<void>.delayed(const Duration(milliseconds: 800));
    }
  }

  @override
  Future<void> verifyConnectivity() => verifyTunnelConnectivity();

  @override
  Future<void> disconnect() async {
    _trafficClient?.close(force: true);
    _trafficClient = null;
    final process = _process;
    _process = null;
    if (process != null) {
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
    await _stopRecordedProcess();
    await _wipeConfigFile(_activeConfig);
    _activeConfig = null;
    _clashSecret = null;
    // Legacy fixed path from older builds.
    await _wipeConfigFile(File('${_stateDir.path}\\config.json'));
    _set('Stopped');
  }

  Future<void> _stopRecordedProcess() async {
    if (!_pidFile.existsSync()) return;
    final pid = int.tryParse((await _pidFile.readAsString()).trim());
    try {
      await _pidFile.delete();
    } catch (_) {}
    if (pid == null || pid <= 0) return;
    final listed = await Process.run('tasklist', ['/FI', 'PID eq $pid', '/FO', 'CSV', '/NH']);
    final text = '${listed.stdout}'.toLowerCase();
    if (!text.contains('sing-box.exe')) return;
    await Process.run('taskkill', ['/PID', '$pid', '/F']);
  }

  @override
  Future<Map<String, int>> probeNodes() async => const {};
}
