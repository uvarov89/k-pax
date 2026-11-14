import 'package:pulse_vpn/core/models/app_settings.dart';

enum VpnConnectionState {
  disconnected,
  connecting,
  connected,
  disconnecting,
  error,
}

enum AppUserMode { simple, pro }

enum LocationMode { auto, country }

enum TunnelProtocol { auto, vlessReality, hysteria2, grpc, tuic, message }

enum BypassMode { auto, tcpOnly, udpPrefer }

extension TunnelProtocolLabel on TunnelProtocol {
  String get labelRu => switch (this) {
        TunnelProtocol.auto => 'Авто',
        TunnelProtocol.vlessReality => 'VLESS',
        TunnelProtocol.hysteria2 => 'Hysteria2',
        TunnelProtocol.grpc => 'Запасной',
        TunnelProtocol.tuic => 'TUIC',
        TunnelProtocol.message => 'Сообщения',
      };
}

extension BypassModeLabel on BypassMode {
  String get labelRu => switch (this) {
        BypassMode.auto => 'Авто',
        BypassMode.tcpOnly => 'Только TCP',
        BypassMode.udpPrefer => 'Сначала UDP',
      };
}

class ProSettings {
  const ProSettings({
    this.protocol = TunnelProtocol.auto,
    this.bypassMode = BypassMode.auto,
    this.dnsAutomatic = true,
    this.killSwitch = true,
    // Disabled by default: IPv4-only TUN + reject IPv6 so apps use IPv4 via
    // the proxy (avoids clearnet IPv6 leak / Telegram "Connecting…").
    this.ipv6Mode = Ipv6Mode.disabled,
    this.protocolFallback = true,
    this.reconnectPolicy = ReconnectPolicy.normal,
  });

  final TunnelProtocol protocol;
  final BypassMode bypassMode;
  final bool dnsAutomatic;
  final bool killSwitch;
  final Ipv6Mode ipv6Mode;
  final bool protocolFallback;
  final ReconnectPolicy reconnectPolicy;

  ProSettings copyWith({
    TunnelProtocol? protocol,
    BypassMode? bypassMode,
    bool? dnsAutomatic,
    bool? killSwitch,
    Ipv6Mode? ipv6Mode,
    bool? protocolFallback,
    ReconnectPolicy? reconnectPolicy,
  }) {
    return ProSettings(
      protocol: protocol ?? this.protocol,
      bypassMode: bypassMode ?? this.bypassMode,
      dnsAutomatic: dnsAutomatic ?? this.dnsAutomatic,
      killSwitch: killSwitch ?? this.killSwitch,
      ipv6Mode: ipv6Mode ?? this.ipv6Mode,
      protocolFallback: protocolFallback ?? this.protocolFallback,
      reconnectPolicy: reconnectPolicy ?? this.reconnectPolicy,
    );
  }
}
