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
  bool _ready = false;

  Future<void> _ensureReady() async {
    if (_ready) return;
    final ok = await _singBox.initialize();
    if (!ok) {
      throw StateError(
        'Не удалось инициализировать iOS VPN (Network Extension)',
      );
    }
    _ready = true;
  }

  @override
  Future<void> applyAppSettings(AppSettings settings) async {
    await _ensureReady();
    await const MethodChannel('sing_box').invokeMethod<void>(
      'configureOnDemand',
      {
        'wifi': settings.autoConnectOnWifi,
        'cellular': settings.autoConnectOnMobile,
      },
    );
  }

  @override
  Future<void> clearSavedAccess() async {
    await _ensureReady();
    await const MethodChannel(
      'sing_box',
    ).invokeMethod<void>('clearSavedAccess');
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
    final started = await _singBox.connect(config);
    if (!started) {
      throw StateError('Разрешение VPN не выдано или расширение недоступно');
    }
    await _waitUntilConnected();
  }

  Future<void> _waitUntilConnected() async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
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
        throw StateError('Туннель остановился при запуске');
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    throw StateError('Туннель не поднялся за отведённое время');
  }

  @override
  Future<void> disconnect() async {
    await _ensureReady();
    final stopped = await _singBox.disconnect();
    if (!stopped) {
      throw StateError('Не удалось остановить VPN');
    }
  }

  @override
  Future<Map<String, int>> probeNodes() {
    return MockVpnService().probeNodes();
  }
}
