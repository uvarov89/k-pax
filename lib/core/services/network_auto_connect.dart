import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';

/// Connects when Wi‑Fi / mobile prefs are on and a matching network appears.
class NetworkAutoConnect {
  NetworkAutoConnect(this._controller);

  final VpnController _controller;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _busy = false;

  Future<void> start() async {
    if (kIsWeb) return;
    try {
      _sub = Connectivity().onConnectivityChanged.listen((results) {
        unawaited(_maybeConnect(results));
      });
      await _maybeConnect(await Connectivity().checkConnectivity());
    } catch (_) {
      // Missing plugin in unit tests / unsupported platforms.
    }
  }

  Future<void> _maybeConnect(List<ConnectivityResult> results) async {
    if (_busy) return;
    final settings = _controller.appSettings;
    final wifiOk =
        settings.autoConnectOnWifi && results.contains(ConnectivityResult.wifi);
    final mobileOk = settings.autoConnectOnMobile &&
        results.contains(ConnectivityResult.mobile);
    if (!wifiOk && !mobileOk) return;
    if (!_controller.hasAccess) return;
    if (_controller.isConnected || _controller.isBusy) return;
    _busy = true;
    try {
      await _controller.connect(userInitiated: false);
    } finally {
      _busy = false;
    }
  }

  Future<void> dispose() async {
    try {
      await _sub?.cancel();
    } catch (_) {}
    _sub = null;
  }
}
