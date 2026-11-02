import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:pulse_vpn/core/models/app_settings.dart';
import 'package:pulse_vpn/core/models/connection_models.dart';
import 'package:pulse_vpn/core/models/server_location.dart';
import 'package:pulse_vpn/core/models/tunnel_node.dart';
import 'package:pulse_vpn/core/services/tunnel_config.dart';
import 'package:pulse_vpn/core/services/vpn_service.dart';

/// Windows tunnel: sing-box.exe beside the app, with wintun.dll.
class WindowsSingboxVpnService implements VpnService {
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
    return Directory('${base ?? Directory.systemTemp.path}\\K-Pax');
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
    final dir = _stateDir;
    await dir.create(recursive: true);
    // Prefer wiping leftover plaintext configs from older builds.
    await _wipeConfigFile(File('${dir.path}\\config.json'));
    _clashSecret = _newClashSecret();
    final config = File('${dir.path}\\config-${_clashSecret!.substring(0, 8)}.json');
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
    final code = await Future.any<int?>([
      exited.future,
      Future<int?>.delayed(const Duration(seconds: 2)),
    ]);
    if (!identical(_process, process)) return;
    if (code != null) {
      _process = null;
      await _wipeConfigFile(_activeConfig);
      _activeConfig = null;
      _clashSecret = null;
      _set('Stopped');
      await stderrDone.future.timeout(
        const Duration(milliseconds: 400),
        onTimeout: () {},
      );
      final detail = stderr.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
      throw StateError(detail.isEmpty ? 'Туннель не запустился' : detail);
    }
    _set('Started');
    unawaited(_pumpTraffic());
  }

  Future<void> _pumpTraffic() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (_process == null) return;
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
      var buffer = '';
      await for (final chunk in response.transform(utf8.decoder)) {
        if (_process == null) break;
        buffer += chunk;
        while (true) {
          final end = buffer.indexOf('}');
          if (end < 0) break;
          final piece = buffer.substring(0, end + 1);
          buffer = buffer.substring(end + 1);
          try {
            final decoded = jsonDecode(piece);
            if (decoded is! Map || _traffic.isClosed) continue;
            _traffic.add(
              TunnelSpeed(
                upBytesPerSec: (decoded['up'] as num?)?.toInt() ?? 0,
                downBytesPerSec: (decoded['down'] as num?)?.toInt() ?? 0,
              ),
            );
          } catch (_) {}
        }
      }
    } catch (_) {
    } finally {
      client.close(force: true);
      if (identical(_trafficClient, client)) _trafficClient = null;
    }
  }

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
