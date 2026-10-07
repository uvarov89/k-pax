/// Native tunnel bridge (Sprint 2).
/// UI talks to [VpnEngine]; Android VpnService + libbox plug in here later.
abstract class VpnEngine {
  Future<void> prepare();
  Future<void> start(Map<String, dynamic> config);
  Future<void> stop();
  Stream<String> get status;
}

/// Placeholder until MethodChannel + VpnService are wired.
class StubVpnEngine implements VpnEngine {
  @override
  Future<void> prepare() async {}

  @override
  Future<void> start(Map<String, dynamic> config) async {}

  @override
  Future<void> stop() async {}

  @override
  Stream<String> get status => const Stream.empty();
}
