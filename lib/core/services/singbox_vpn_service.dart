import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_singbox_vpn/flutter_singbox.dart';
import 'package:pulse_vpn/app/brand/app_brand.dart';
import 'package:pulse_vpn/core/models/app_settings.dart';
import 'package:pulse_vpn/core/models/connection_models.dart';
import 'package:pulse_vpn/core/models/server_location.dart';
import 'package:pulse_vpn/core/models/split_tunnel.dart';
import 'package:pulse_vpn/core/models/tunnel_node.dart';
import 'package:pulse_vpn/core/services/tunnel_config.dart';
import 'package:pulse_vpn/core/services/tunnel_connectivity.dart';
import 'package:pulse_vpn/core/services/vpn_service.dart';
import 'package:pulse_vpn/core/services/ios_singbox_vpn_service.dart';
import 'package:pulse_vpn/core/services/windows_singbox_vpn_service.dart';

/// Android / Windows / iOS use sing-box. Other platforms keep [MockVpnService].
VpnService defaultVpnService() {
  if (kIsWeb) return MockVpnService();
  if (Platform.isAndroid) return SingboxVpnService();
  if (Platform.isWindows) return WindowsSingboxVpnService();
  if (Platform.isIOS) return IosSingboxVpnService();
  return MockVpnService();
}

class SingboxVpnService
    implements VpnService, TunnelConnectivityVerifier, VpnSettingsService {
  SingboxVpnService({FlutterSingbox? singbox})
    : _singbox = singbox ?? FlutterSingbox();

  final FlutterSingbox _singbox;
  final TunnelSpeedTracker _speedTracker = TunnelSpeedTracker();
  String? _clashSecret;

  static String _newClashSecret() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  @override
  Stream<String> get statusStream =>
      _singbox.onStatusChanged.map((event) => '${event['status'] ?? ''}');

  @override
  Stream<TunnelSpeed> get trafficStream => _singbox.onTrafficUpdate.map((event) {
        int asInt(Object? value) {
          if (value is int) return value;
          if (value is num) return value.toInt();
          return int.tryParse('$value') ?? 0;
        }

        // Prefer session counters (reset on connect). Lifetime totals can sit
        // still after a StatusClient reconnect and leave the UI at 0 B/s.
        return _speedTracker.ingest(
          upRate: asInt(event['uplinkSpeed'] ?? event['uplink']),
          downRate: asInt(event['downlinkSpeed'] ?? event['downlink']),
          upTotal: asInt(event['sessionUplink'] ?? event['uplinkTotal']),
          downTotal: asInt(event['sessionDownlink'] ?? event['downlinkTotal']),
        );
      });

  @override
  Future<void> connect({
    required ServerLocation location,
    required ProSettings settings,
    required AppSettings appSettings,
    required TunnelNode node,
  }) async {
    _speedTracker.reset();
    // Clash API enables Libbox traffic counters used by StatusClient.
    _clashSecret = _newClashSecret();
    final config = buildTunnelConfig(
      node,
      settings,
      appSettings: appSettings,
      enableStats: true,
      clashSecret: _clashSecret,
    );
    final saved = await _singbox.saveConfig(config);
    if (!saved) {
      _clashSecret = null;
      throw StateError('Не удалось сохранить конфигурацию туннеля');
    }

    await _singbox.setNotificationTitle(AppBrand.current.appName);
    await _singbox.setNotificationDescription('Защищённое подключение');
    await _applySplitTunnel(appSettings);

    final started = await _singbox.startVPN();
    if (!started) {
      _clashSecret = null;
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
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('Туннель не поднялся за отведённое время');
  }

  @override
  Future<void> verifyConnectivity() {
    final secret = _clashSecret;
    if (secret == null || secret.isEmpty) {
      return verifyTunnelConnectivity();
    }
    return verifyTunnelConnectivityViaProxy(clashSecret: secret);
  }

  @override
  Future<void> applyAppSettings(AppSettings settings) async {
    await _applySplitTunnel(settings);
  }

  @override
  Future<void> clearSavedAccess() async {
    try {
      await _singbox.stopVPN();
    } catch (_) {}
    _clashSecret = null;
    // Wipe last tunnel JSON so a forgotten subscription cannot reconnect.
    await _singbox.saveConfig('{}');
  }

  @override
  Future<void> disconnect() async {
    final stopped = await _singbox.stopVPN();
    _clashSecret = null;
    if (!stopped) {
      throw StateError('Не удалось остановить VPN');
    }
  }

  @override
  Future<Map<String, int>> probeNodes() {
    return MockVpnService().probeNodes();
  }
}
