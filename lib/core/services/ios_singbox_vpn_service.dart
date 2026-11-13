import 'dart:async';

import 'package:flutter/services.dart';
import 'package:pulse_vpn/core/models/app_settings.dart';
import 'package:pulse_vpn/core/models/connection_models.dart';
import 'package:pulse_vpn/core/models/server_location.dart';
import 'package:pulse_vpn/core/models/tunnel_node.dart';
import 'package:pulse_vpn/core/services/tunnel_config.dart';
import 'package:pulse_vpn/core/services/vpn_service.dart';
import 'package:sing_box/sing_box.dart';

/// iOS VPN via Packet Tunnel + Libbox (vendored [sing_box] plugin).
class IosSingboxVpnService implements VpnService, VpnSettingsService {
  IosSingboxVpnService({SingBox? singBox})
    : _singBox = singBox ?? SingBox.instance;

  final SingBox _singBox;
  static const _channel = MethodChannel('sing_box');
  bool _ready = false;

  Future<void> _ensureReady() async {
    if (_ready) return;
    try {
      final ok = await _singBox.initialize();
      if (!ok) {
        throw StateError(
          '[INIT_FAILED] Не удалось инициализировать iOS VPN (Network Extension)',
        );
      }
    } on PlatformException catch (e) {
      throw StateError(_platformErrorText(e));
    }
    _ready = true;
  }

  static String _platformErrorText(PlatformException e) {
    final code = e.code.trim();
    final message = (e.message ?? '').trim();
    if (code.isEmpty && message.isEmpty) {
      return 'Ошибка VPN (без кода)';
    }
    if (message.isEmpty) return '[$code]';
    if (code.isEmpty) return message;
    return '[$code] $message';
  }

  @override
  Future<void> applyAppSettings(AppSettings settings) async {
    await _ensureReady();
    await _channel.invokeMethod<void>('configureOnDemand', {
      'wifi': settings.autoConnectOnWifi,
      'cellular': settings.autoConnectOnMobile,
    });
  }

  @override
  Future<void> clearSavedAccess() async {
    await _ensureReady();
    await _channel.invokeMethod<void>('clearSavedAccess');
  }

  @override
  Stream<String> get statusStream =>
      _singBox.watchSingBoxConnectionStatus().map((s) => s.name);

  @override
  Stream<TunnelSpeed> get trafficStream =>
      _singBox.watchSingBoxConnectionStats().map(
        (stats) => TunnelSpeed(
          upBytesPerSec: stats.uploadSpeed,
          downBytesPerSec: stats.downloadSpeed,
        ),
      );

  @override
  Future<void> connect({
    required ServerLocation location,
    required ProSettings settings,
    required AppSettings appSettings,
    required TunnelNode node,
  }) async {
    await _ensureReady();
    await applyAppSettings(appSettings);
    // Per-app split tunnel is not available on iOS; config is full-tunnel.
    final config = buildTunnelConfig(node, settings, appSettings: appSettings);
    final bool started;
    try {
      // startVPNTunnel should return quickly; long hangs = system/extension issue.
      started = await _singBox
          .connect(config)
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      try {
        await _singBox.disconnect();
      } catch (_) {}
      throw StateError('[CONNECT_TIMEOUT] Туннель не ответил при запуске');
    } on PlatformException catch (e) {
      throw StateError(_platformErrorText(e));
    }
    if (!started) {
      throw StateError(
        '[CONNECT_FALSE] Разрешение VPN не выдано или расширение недоступно',
      );
    }
    await _waitUntilConnected();
  }

  Future<void> _waitUntilConnected() async {
    // Keep short: controller failover must not sit ~1min per node (felt like "nothing").
    // Permission sheet: user usually answers in a few seconds; 25s total is enough.
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    final noProgressDeadline = DateTime.now().add(const Duration(seconds: 8));
    var sawConnecting = false;
    while (DateTime.now().isBefore(deadline)) {
      final status = await _singBox.getConnectionStatus();
      if (status == SingBoxConnectionStatus.connected) return;
      if (status == SingBoxConnectionStatus.connecting) {
        sawConnecting = true;
      }
      if (sawConnecting &&
          (status == SingBoxConnectionStatus.disconnected ||
              status == SingBoxConnectionStatus.error ||
              status == SingBoxConnectionStatus.connectionLost)) {
        final detail = await _lastTunnelStopReason();
        throw StateError(
          detail == null
              ? '[TUNNEL_STOPPED] Туннель остановился при запуске'
              : '[TUNNEL_STOPPED] $detail',
        );
      }
      if (!sawConnecting && DateTime.now().isAfter(noProgressDeadline)) {
        final detail = await _lastTunnelStopReason();
        throw StateError(
          detail == null
              ? '[NO_PROGRESS] VPN не перешёл в Connecting (профиль/расширение?)'
              : '[NO_PROGRESS] $detail',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    final detail = await _lastTunnelStopReason();
    throw StateError(
      detail == null
          ? '[CONNECT_TIMEOUT] Туннель не поднялся за отведённое время'
          : '[CONNECT_TIMEOUT] $detail',
    );
  }

  /// Best-effort stop reason from Network Extension (no config/keys).
  Future<String?> _lastTunnelStopReason() async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('getLastTunnelError');
      if (raw is String && raw.trim().isNotEmpty) return raw.trim();
      if (raw is Map) {
        final code = '${raw['code'] ?? ''}'.trim();
        final message = '${raw['message'] ?? ''}'.trim();
        if (code.isEmpty && message.isEmpty) return null;
        if (message.isEmpty) return code;
        if (code.isEmpty) return message;
        return '$code: $message';
      }
    } on PlatformException catch (e) {
      final text = _platformErrorText(e);
      if (text.isNotEmpty) return text;
    } catch (_) {}
    return null;
  }

  @override
  Future<void> disconnect() async {
    await _ensureReady();
    try {
      final stopped = await _singBox
          .disconnect()
          .timeout(const Duration(seconds: 8));
      if (!stopped) {
        throw StateError('[DISCONNECT_FALSE] Не удалось остановить VPN');
      }
    } on TimeoutException {
      throw StateError('[DISCONNECT_TIMEOUT] Остановка VPN не ответила');
    } on PlatformException catch (e) {
      throw StateError(_platformErrorText(e));
    }
  }

  @override
  Future<Map<String, int>> probeNodes() {
    return MockVpnService().probeNodes();
  }
}
