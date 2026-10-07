enum SplitTunnelMode {
  /// All apps go through VPN.
  allApps,

  /// Selected apps bypass VPN (typical for banks / RU services).
  excludeSelected,

  /// Only selected apps use VPN; everything else bypasses.
  includeOnly,
}

extension SplitTunnelModeX on SplitTunnelMode {
  static SplitTunnelMode fromIndex(int? index) {
    if (index == null || index < 0 || index >= SplitTunnelMode.values.length) {
      return SplitTunnelMode.allApps;
    }
    return SplitTunnelMode.values[index];
  }
}
