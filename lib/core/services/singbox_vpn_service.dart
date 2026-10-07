import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_singbox_vpn/flutter_singbox.dart';
import 'package:pulse_vpn/core/models/app_settings.dart';
import 'package:pulse_vpn/core/models/connection_models.dart';
import 'package:pulse_vpn/core/models/server_location.dart';
import 'package:pulse_vpn/core/models/split_tunnel.dart';
import 'package:pulse_vpn/core/models/tunnel_node.dart';
import 'package:pulse_vpn/core/services/tunnel_config.dart';
import 'package:pulse_vpn/core/services/vpn_service.dart';

/// Android tunnel via sing-box. Other platforms keep [MockVpnService].
VpnService defaultVpnService() {
  if (!kIsWeb && Platform.isAndroid) {
    return SingboxVpnService();
  }
  return MockVpnService();
}

class SingboxVpnService implements VpnService {
  SingboxVpnService({FlutterSingbox? singbox}) : _singbox = singbox ?? FlutterSingbox();

  final FlutterSingbox _singbox;

  @override
  Future<void> connect({
    required ServerLocation location,
    required ProSettings settings,
    required AppSettings appSettings,
    required TunnelNode node,
  }) async {
    final config = buildTunnelConfig(node, settings);
    final saved = await _singbox.saveConfig(config);
    if (!saved) {
      throw StateError('Не удалось сохранить конфигурацию туннеля');
    }

    await _singbox.setNotificationTitle('K-Pax');
    await _singbox.setNotificationDescription('Защищённое подключение');
    await _applySplitTunnel(appSettings);

    final started = await _singbox.startVPN();
    if (!started) {
      throw StateError('Разрешение VPN не выдано');
    }
    await _waitUntilStarted();
  }

  Future<void> _applySplitTunnel(AppSettings appSettings) async {
    final mode = switch (appSettings.splitTunnelMode) {
      SplitTunnelMode.allApps => ProxyMode.OFF,
      SplitTunnelMode.excludeSelected => ProxyMode.EXCLUDE,
      SplitTunnelMode.includeOnly => ProxyMode.INCLUDE,
    };
    await _singbox.setPerAppProxyMode(mode);
    if (mode == ProxyMode.OFF) {
      await _singbox.setPerAppProxyList(const []);
      return;
    }
    await _singbox.setPerAppProxyList(appSettings.splitTunnelPackages);
  }

  Future<void> _waitUntilStarted() async {
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    var sawStarting = false;
    while (DateTime.now().isBefore(deadline)) {
      final status = await _singbox.getVPNStatus();
      if (status == VPNStatus.STARTED) return;
      if (status == VPNStatus.STARTING || status == VPNStatus.STOPPING) {
        sawStarting = true;
      }
      if (sawStarting && status == VPNStatus.STOPPED) {
        throw StateError('Туннель остановился при запуске');
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    throw StateError('Туннель не поднялся за отведённое время');
  }

  @override
  Future<void> disconnect() async {
    final stopped = await _singbox.stopVPN();
    if (!stopped) {
      throw StateError('Не удалось остановить VPN');
    }
  }

  @override
  Future<Map<String, int>> probeNodes() {
    return MockVpnService().probeNodes();
  }
}
