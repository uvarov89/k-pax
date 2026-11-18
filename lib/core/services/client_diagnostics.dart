import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pulse_vpn/app/brand/app_brand.dart';
import 'package:pulse_vpn/core/models/tunnel_node.dart';

/// Max events kept locally while offline / rate-limited.
const kDiagnosticsQueueCap = 200;

/// Prefs key for unsent event batch (plain JSON list — no secrets).
const kDiagnosticsQueuePrefsKey = 'diagnostics_queue_v1';

/// Settings / AppSettings key — default ON.
const kDiagnosticsEnabledPrefsKey = 'diagnostics_enabled';

const kDiagnosticsMaxErrorLen = 200;
const kDiagnosticsMaxBatch = 50;

/// Connecting longer than this without [logConnectOk] / final [logConnectFail]
/// triggers a one-shot `connect_hang` event (see VpnController watchdog).
const kConnectHangTimeout = Duration(seconds: 45);

/// Strip subscription URLs, UUIDs, Reality keys, VLESS links, Clash secrets.
String redactDiagnosticsError(Object? error, {int maxLen = kDiagnosticsMaxErrorLen}) {
  var text = '$error';
  text = text.replaceAll(
    RegExp(r'vless://[^\s]+', caseSensitive: false),
    '[vless]',
  );
  text = text.replaceAll(
    RegExp(r'hy2://[^\s]+', caseSensitive: false),
    '[hy2]',
  );
  text = text.replaceAll(
    RegExp(r'tuic://[^\s]+', caseSensitive: false),
    '[tuic]',
  );
  text = text.replaceAll(
    RegExp(r'trojan://[^\s]+', caseSensitive: false),
    '[trojan]',
  );
  text = text.replaceAll(
    RegExp(
      r'https?://[^\s]*sub\.[^\s/]+/s/[A-Za-z0-9_-]+',
      caseSensitive: false,
    ),
    '[sub]',
  );
  text = text.replaceAll(
    RegExp(
      r'\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b',
      caseSensitive: false,
    ),
    '[uuid]',
  );
  text = text.replaceAllMapped(
    RegExp(
      r'\b(?:pbk|sid|fp|password|passwd|secret|token)=[^\s&,;]+',
      caseSensitive: false,
    ),
    (m) {
      final key = m.group(0)!.split('=').first;
      return '$key=[redacted]';
    },
  );
  text = text.replaceAll(
    RegExp(r'\bBearer\s+[A-Za-z0-9._\-]+', caseSensitive: false),
    'Bearer [redacted]',
  );
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.length > maxLen) {
    text = '${text.substring(0, maxLen)}…';
  }
  return text;
}

/// Panel POST body shape: `{token, session_id, events:[...]}`.
Map<String, Object?> encodeClientEventsBatch({
  required String token,
  required String sessionId,
  required List<Map<String, Object?>> events,
}) {
  return {
    'token': token,
    'session_id': sessionId,
    'events': events,
  };
}

Map<String, Object?> buildDiagnosticsEvent({
  required String event,
  required String sessionId,
  required String brand,
  required String appVersion,
  required String platform,
  String? countryId,
  String? kind,
  int? port,
  String? host,
  String? errorCode,
  String? error,
  int? attempt,
  int? connectedMs,
  int? upTotal,
  int? downTotal,
  DateTime? ts,
}) {
  final map = <String, Object?>{
    'ts': (ts ?? DateTime.now().toUtc()).toIso8601String(),
    'brand': brand,
    'app_version': appVersion,
    'platform': platform,
    'session_id': sessionId,
    'event': event,
  };
  if (countryId != null && countryId.isNotEmpty) map['country_id'] = countryId;
  if (kind != null && kind.isNotEmpty) map['kind'] = kind;
  if (port != null && port > 0) map['port'] = port;
  if (host != null && host.isNotEmpty) map['host'] = host;
  if (errorCode != null && errorCode.isNotEmpty) map['error_code'] = errorCode;
  if (error != null && error.isNotEmpty) {
    map['error'] = redactDiagnosticsError(error);
  }
  if (attempt != null) map['attempt'] = attempt;
  if (connectedMs != null) map['connected_ms'] = connectedMs;
  if (upTotal != null) map['up_total'] = upTotal;
  if (downTotal != null) map['down_total'] = downTotal;
  return map;
}

String diagnosticsPlatformLabel() {
  if (kIsWeb) return 'web';
  if (Platform.isAndroid) return 'android';
  if (Platform.isIOS) return 'ios';
  if (Platform.isWindows) return 'windows';
  if (Platform.isMacOS) return 'macos';
  if (Platform.isLinux) return 'linux';
  return 'unknown';
}

String _newSessionId() {
  final r = Random.secure();
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Local queue + batched POST to `/app/client-events`. Never blocks the UI.
class ClientDiagnostics with WidgetsBindingObserver {
  ClientDiagnostics({
    required Future<String?> Function() tokenProvider,
    bool enabled = true,
    HttpClient Function()? httpClientFactory,
    Future<SharedPreferences> Function()? prefsFactory,
    Future<String> Function()? appVersionLoader,
  })  : _tokenProvider = tokenProvider,
        _enabled = enabled,
        _httpClientFactory = httpClientFactory ?? HttpClient.new,
        _prefsFactory = prefsFactory ?? SharedPreferences.getInstance,
        _appVersionLoader = appVersionLoader ?? _defaultAppVersion;

  final Future<String?> Function() _tokenProvider;
  final HttpClient Function() _httpClientFactory;
  final Future<SharedPreferences> Function() _prefsFactory;
  final Future<String> Function() _appVersionLoader;

  final String sessionId = _newSessionId();
  final List<Map<String, Object?>> _queue = [];

  bool _enabled;
  bool _started = false;
  bool _flushing = false;
  bool _observerAttached = false;
  Timer? _flushTimer;
  String _appVersion = '0';
  Future<void> _persistChain = Future<void>.value();

  bool get enabled => _enabled;
  String get appVersion => _appVersion;
  int get queuedCount => _queue.length;

  @visibleForTesting
  List<Map<String, Object?>> get debugQueue =>
      List<Map<String, Object?>>.unmodifiable(_queue);

  static Future<String> _defaultAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (_) {
      return '0';
    }
  }

  Future<void> start({bool? enabled}) async {
    if (enabled != null) _enabled = enabled;
    if (_started) return;
    _started = true;
    _appVersion = await _appVersionLoader();
    await _loadQueue();
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(flush());
    });
    if (!_observerAttached) {
      try {
        WidgetsBinding.instance.addObserver(this);
        _observerAttached = true;
      } catch (_) {
        // Tests without a binding — flush timer still runs.
      }
    }
    if (_enabled) {
      logEvent(event: 'app_start');
    }
  }

  void setEnabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (!value) return;
    unawaited(flush());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      unawaited(flush(urgent: true));
    }
  }

  void dispose() {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_observerAttached) {
      try {
        WidgetsBinding.instance.removeObserver(this);
      } catch (_) {}
      _observerAttached = false;
    }
    unawaited(flush(urgent: true));
  }

  void logEvent({
    required String event,
    TunnelNode? node,
    String? countryId,
    String? kind,
    int? port,
    String? host,
    String? errorCode,
    Object? error,
    int? attempt,
    int? connectedMs,
    int? upTotal,
    int? downTotal,
    bool flushNow = false,
  }) {
    if (!_enabled) return;
    final resolvedHost = host ?? node?.host;
    final resolvedPort = port ?? (node == null ? null : (node.port == 0 ? 443 : node.port));
    final payload = buildDiagnosticsEvent(
      event: event,
      sessionId: sessionId,
      brand: AppBrand.current.id,
      appVersion: _appVersion,
      platform: diagnosticsPlatformLabel(),
      countryId: countryId ?? node?.countryId,
      kind: kind ?? node?.kind.name,
      port: resolvedPort,
      host: resolvedHost,
      errorCode: errorCode,
      error: error == null ? null : redactDiagnosticsError(error),
      attempt: attempt,
      connectedMs: connectedMs,
      upTotal: upTotal,
      downTotal: downTotal,
    );
    _enqueue(payload);
    if (flushNow ||
        event == 'connect_fail' ||
        event == 'connect_hang' ||
        event == 'tunnel_drop' ||
        event == 'probe_fail' ||
        event == 'update_fail') {
      unawaited(flush(urgent: true));
    }
  }

  void logConnectStart(TunnelNode node, {int attempt = 1}) {
    logEvent(event: 'connect_start', node: node, attempt: attempt);
  }

  void logConnectOk(TunnelNode node, {required int attempt, int? connectedMs}) {
    logEvent(
      event: 'connect_ok',
      node: node,
      attempt: attempt,
      connectedMs: connectedMs,
    );
  }

  void logConnectFail({
    TunnelNode? node,
    Object? error,
    String errorCode = 'connect',
    int? attempt,
  }) {
    logEvent(
      event: 'connect_fail',
      node: node,
      error: error,
      errorCode: errorCode,
      attempt: attempt,
      flushNow: true,
    );
  }

  /// Connecting stuck past [kConnectHangTimeout] with no connect_ok / final fail.
  void logConnectHang({
    TunnelNode? node,
    Object? error,
    int? attempt,
  }) {
    logEvent(
      event: 'connect_hang',
      node: node,
      error: error ?? 'connecting >${kConnectHangTimeout.inSeconds}s',
      errorCode: 'hang',
      attempt: attempt,
      flushNow: true,
    );
  }

  void logFailoverTry(TunnelNode node, {required int attempt}) {
    logEvent(event: 'failover_try', node: node, attempt: attempt);
  }

  void logProbeFail(TunnelNode node, Object error, {int? attempt}) {
    logEvent(
      event: 'probe_fail',
      node: node,
      error: error,
      errorCode: 'probe',
      attempt: attempt,
      flushNow: true,
    );
  }

  void logTunnelDrop({
    TunnelNode? node,
    int? connectedMs,
    int? upTotal,
    int? downTotal,
    String? errorCode,
  }) {
    logEvent(
      event: 'tunnel_drop',
      node: node,
      connectedMs: connectedMs,
      upTotal: upTotal,
      downTotal: downTotal,
      errorCode: errorCode ?? 'drop',
      flushNow: true,
    );
  }

  void logDisconnect({
    TunnelNode? node,
    int? connectedMs,
    int? upTotal,
    int? downTotal,
  }) {
    logEvent(
      event: 'disconnect',
      node: node,
      connectedMs: connectedMs,
      upTotal: upTotal,
      downTotal: downTotal,
    );
  }

  void logUpdateFail({String errorCode = 'update', Object? error}) {
    logEvent(
      event: 'update_fail',
      errorCode: errorCode,
      error: error,
      flushNow: true,
    );
  }

  void _enqueue(Map<String, Object?> event) {
    _queue.add(event);
    while (_queue.length > kDiagnosticsQueueCap) {
      _queue.removeAt(0);
    }
    _schedulePersist();
  }

  void _schedulePersist() {
    _persistChain = _persistChain.catchError((_) {}).then((_) => _persistQueue());
  }

  Future<void> _loadQueue() async {
    try {
      final prefs = await _prefsFactory();
      final raw = prefs.getString(kDiagnosticsQueuePrefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      for (final item in decoded) {
        if (item is Map) {
          _queue.add(Map<String, Object?>.from(item));
        }
      }
      while (_queue.length > kDiagnosticsQueueCap) {
        _queue.removeAt(0);
      }
    } catch (_) {}
  }

  Future<void> _persistQueue() async {
    try {
      final prefs = await _prefsFactory();
      if (_queue.isEmpty) {
        await prefs.remove(kDiagnosticsQueuePrefsKey);
        return;
      }
      await prefs.setString(kDiagnosticsQueuePrefsKey, jsonEncode(_queue));
    } catch (_) {}
  }

  /// Fire-and-forget batch upload. Failures leave events queued.
  Future<void> flush({bool urgent = false}) async {
    if (_flushing) return;
    if (_queue.isEmpty) return;
    final token = await _tokenProvider();
    if (token == null || token.isEmpty) return;

    _flushing = true;
    try {
      while (_queue.isNotEmpty) {
        final batch = _queue.take(kDiagnosticsMaxBatch).toList(growable: false);
        final ok = await _postBatch(token: token, events: batch);
        if (!ok) break;
        _queue.removeRange(0, batch.length);
        _schedulePersist();
        // Periodic flush sends one batch; urgent drains the queue.
        if (!urgent) break;
      }
    } finally {
      _flushing = false;
    }
  }

  Future<bool> _postBatch({
    required String token,
    required List<Map<String, Object?>> events,
  }) async {
    final client = _httpClientFactory();
    try {
      final payload = encodeClientEventsBatch(
        token: token,
        sessionId: sessionId,
        events: events,
      );
      final bytes = utf8.encode(jsonEncode(payload));
      final request = await client
          .postUrl(AppBrand.current.appClientEvents())
          .timeout(const Duration(seconds: 12));
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/json; charset=utf-8',
      );
      request.headers.set(
        HttpHeaders.userAgentHeader,
        AppBrand.current.appName,
      );
      request.contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close().timeout(const Duration(seconds: 20));
      // Drain body so the connection can close cleanly.
      await response.drain<void>().timeout(const Duration(seconds: 10));
      if (response.statusCode == 429) return false;
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }
}
