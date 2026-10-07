enum TunnelKind { reality, grpc, hy2 }

class TunnelNode {
  const TunnelNode({
    required this.countryId,
    required this.countryCode,
    required this.countryName,
    required this.kind,
    required this.host,
    required this.port,
    required this.outbound,
  });

  final String countryId;
  final String countryCode;
  final String countryName;
  final TunnelKind kind;
  final String host;
  final int port;
  final Map<String, Object?> outbound;
}

class SubscriptionProfile {
  const SubscriptionProfile({
    required this.nodes,
    this.expiresAt,
  });

  final List<TunnelNode> nodes;
  final DateTime? expiresAt;

  bool get isExpired =>
      expiresAt != null && !expiresAt!.isAfter(DateTime.now());
}
