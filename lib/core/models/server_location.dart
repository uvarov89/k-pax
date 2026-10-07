class ServerLocation {
  const ServerLocation({
    required this.id,
    required this.countryCode,
    required this.nameRu,
    this.latencyMs = -1,
    this.isAuto = false,
  });

  final String id;
  final String countryCode;
  final String nameRu;
  final int latencyMs;
  final bool isAuto;

  static const auto = ServerLocation(
    id: 'auto',
    countryCode: 'AUTO',
    nameRu: 'Авто',
    latencyMs: 0,
    isAuto: true,
  );

  static const catalog = <ServerLocation>[auto];
}
