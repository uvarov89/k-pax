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

enum TunnelProtocol { auto, vlessReality, hysteria2 }

enum BypassMode { auto, tcpOnly, udpPrefer }

extension TunnelProtocolLabel on TunnelProtocol {
  String get labelRu => switch (this) {
        TunnelProtocol.auto => 'Auto',
        TunnelProtocol.vlessReality => 'VLESS+REALITY',
        TunnelProtocol.hysteria2 => 'Hysteria2',
      };
}

extension BypassModeLabel on BypassMode {
  String get labelRu => switch (this) {
        BypassMode.auto => 'Auto',
        BypassMode.tcpOnly => 'TCP only',
        BypassMode.udpPrefer => 'UDP prefer',
      };
}

class ProSettings {
  const ProSettings({
    this.protocol = TunnelProtocol.auto,
    this.bypassMode = BypassMode.auto,
    this.dnsAutomatic = true,
    this.killSwitch = false,
    this.ipv6Mode = Ipv6Mode.enabled,
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
