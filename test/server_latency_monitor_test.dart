import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pulse_vpn/app/theme/nord_signal_theme.dart';
import 'package:pulse_vpn/core/models/connection_models.dart';
import 'package:pulse_vpn/core/models/server_location.dart';
import 'package:pulse_vpn/core/models/subscription.dart';
import 'package:pulse_vpn/core/models/tunnel_node.dart';
import 'package:pulse_vpn/core/services/server_latency_monitor.dart';
import 'package:pulse_vpn/core/services/vpn_service.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';
import 'package:pulse_vpn/features/home/widgets/xplm_home_layout.dart';
import 'package:pulse_vpn/features/xplm/widgets/xplm_codex_widgets.dart';
import 'package:pulse_vpn/features/xplm/widgets/xplm_ping_scope.dart';

const _de = TunnelNode(
  countryId: 'de',
  countryCode: 'DE',
  countryName: 'Германия',
  kind: TunnelKind.reality,
  host: 'de.invalid',
  port: 443,
  outbound: {},
);
const _fi = TunnelNode(
  countryId: 'fi',
  countryCode: 'FI',
  countryName: 'Финляндия',
  kind: TunnelKind.reality,
  host: 'fi.invalid',
  port: 443,
  outbound: {},
);
const _activeFi = TunnelNode(
  countryId: 'fi',
  countryCode: 'FI',
  countryName: 'Финляндия',
  kind: TunnelKind.reality,
  host: 'fi-active.invalid',
  port: 8443,
  outbound: {},
);

class _Controller extends VpnController {
  _Controller() : super(service: MockVpnService());
  void publish() => notifyListeners();
}

void main() {
  test('real TCP connection produces a measured value', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final accepted = server.listen((socket) => socket.destroy());
    final monitor = ServerLatencyMonitor();
    try {
      monitor.configure(
        scope: Object(),
        enabled: true,
        nodes: [
          TunnelNode(
            countryId: 'local',
            countryCode: 'DE',
            countryName: 'Local',
            kind: TunnelKind.reality,
            host: server.address.address,
            port: server.port,
            outbound: const {},
          ),
        ],
      );
      await monitor.refresh();
      expect(monitor.pingFor('local'), isNotNull);
      expect(monitor.pingFor('local'), greaterThanOrEqualTo(0));
      expect(monitor.isMeasuring, isFalse);
    } finally {
      monitor.dispose();
      await accepted.cancel();
      await server.close();
    }
  });
  test('late results from old subscription and route are discarded', () async {
    final calls = <Completer<int?>>[];
    final monitor = ServerLatencyMonitor(
      probe: (host, port) {
        final pending = Completer<int?>();
        calls.add(pending);
        return pending.future;
      },
    );
    final scope = Object();
    monitor.configure(scope: Object(), enabled: true, nodes: const [_fi]);
    monitor.configure(
      scope: scope,
      route: 'connected',
      enabled: true,
      nodes: const [_fi],
      connectedNode: _activeFi,
    );
    expect(calls.length, 2);
    calls[1].complete(195);
    await monitor.refresh();
    calls[0].complete(8);
    await Future<void>.delayed(Duration.zero);
    expect(monitor.pingFor('fi'), 195);
    monitor.configure(
      scope: scope,
      route: 'disconnected',
      enabled: true,
      nodes: const [_fi],
    );
    expect(monitor.pingFor('fi'), isNull);
    calls[2].complete(42);
    await monitor.refresh();
    expect(monitor.pingFor('fi'), 42);
    monitor.dispose();
  });
  test(
    'active endpoint and selected country are prioritized; rounds do not overlap',
    () async {
      final hosts = <String>[];
      final pending = <Completer<int?>>[];
      final monitor = ServerLatencyMonitor(
        probe: (host, port) {
          hosts.add('$host:$port');
          final value = Completer<int?>();
          pending.add(value);
          return value.future;
        },
      );
      monitor.configure(
        scope: Object(),
        enabled: true,
        nodes: const [_de, _fi],
        preferredCountry: 'fi',
        connectedNode: _activeFi,
      );
      final round = monitor.refresh();
      monitor.refresh();
      expect(hosts, ['fi-active.invalid:8443']);
      pending[0].complete(90);
      await Future<void>.delayed(Duration.zero);
      expect(hosts, ['fi-active.invalid:8443', 'de.invalid:443']);
      pending[1].complete(null);
      await round;
      expect(monitor.pingFor('fi'), 90);
      expect(monitor.pingFor('de'), -1);
      expect(monitor.bestPing, 90);
      monitor.dispose();
    },
  );
  testWidgets(
    'periodic measurements stop in background/disabled and after disposal',
    (tester) async {
      var calls = 0;
      final scope = Object();
      final monitor = ServerLatencyMonitor(
        probe: (host, port) async => ++calls,
      );
      monitor.configure(scope: scope, enabled: true, nodes: const [_de]);
      await tester.pump();
      expect(calls, 1);
      await tester.pump(const Duration(seconds: 30));
      expect(calls, 2);
      monitor.configure(scope: scope, enabled: false, nodes: const [_de]);
      await tester.pump(const Duration(seconds: 60));
      expect(calls, 2);
      monitor.configure(scope: scope, enabled: true, nodes: const [_de]);
      await tester.pump();
      expect(calls, 3);
      monitor.dispose();
      await tester.pump(const Duration(seconds: 60));
      expect(calls, 3);
    },
  );
  test('disposing a pending measurement cannot notify later', () async {
    final pending = Completer<int?>();
    var updates = 0;
    final monitor = ServerLatencyMonitor(probe: (_, _) => pending.future)
      ..addListener(() => updates++);
    monitor.configure(scope: Object(), enabled: true, nodes: const [_de]);
    final round = monitor.refresh();
    final before = updates;
    monitor.dispose();
    pending.complete(1);
    await round;
    expect(updates, before);
  });
  testWidgets(
    'all latency boundaries render the requested number and color of bars',
    (tester) async {
      const green = Color(0xFF33CF8F),
          yellow = Color(0xFFFFC24A),
          orange = Color(0xFFFF922E),
          red = Color(0xFFFF5A6A);
      for (final entry in <(int, int, Color)>[
        (0, 4, green),
        (80, 4, green),
        (81, 3, yellow),
        (150, 3, yellow),
        (151, 2, orange),
        (250, 2, orange),
        (251, 1, red),
        (900, 1, red),
        (-1, 0, green),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: XplmSignalBars(latencyMs: entry.$1)),
          ),
        );
        final colors = tester
            .widgetList<Container>(find.byType(Container))
            .map((c) => (c.decoration! as BoxDecoration).color)
            .toList();
        expect(colors.length, 4);
        expect(
          colors.where((c) => c == entry.$3).length,
          entry.$2,
          reason: '${entry.$1}ms',
        );
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'automatic scope updates home for selected and actual connected servers',
    (tester) async {
      final c = _Controller()
        ..profile = const SubscriptionProfile(nodes: [_de, _fi])
        ..linkState = SubscriptionLinkState.ready
        ..account = UserAccount.freshTrial()
        ..selectedLocation = const ServerLocation(
          id: 'de',
          countryCode: 'DE',
          nameRu: 'Германия',
        );
      final requests = <(String, Completer<int?>)>[];
      final monitor = ServerLatencyMonitor(
        probe: (host, port) {
          final value = Completer<int?>();
          requests.add((host, value));
          return value.future;
        },
      );
      addTearDown(c.dispose);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        ChangeNotifierProvider<VpnController>.value(
          value: c,
          child: XplmPingScope(
            controller: c,
            createMonitor: () => monitor,
            child: MaterialApp(
              theme: NordSignalTheme.xplmLight,
              home: Scaffold(
                body: XplmHomeLayout(
                  onConnectPressed: () async {},
                  onOpenProfile: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(requests.first.$1, 'de.invalid');
      expect(find.text('Пинг: …'), findsOneWidget);
      requests[0].$2.complete(195);
      await tester.pump();
      await tester.pump();
      expect(find.text('Пинг: 195 ms'), findsOneWidget);
      expect(
        tester.widget<XplmSignalBars>(find.byType(XplmSignalBars)).latencyMs,
        195,
      );
      requests[1].$2.complete(12);
      await tester.pump();
      c.connectionState = VpnConnectionState.connected;
      c.connectedNode = _activeFi;
      c.publish();
      await tester.pump();
      await tester.pump();
      expect(requests[2].$1, 'fi-active.invalid');
      expect(find.text('Пинг: …'), findsOneWidget);
      requests[2].$2.complete(53);
      await tester.pump();
      await tester.pump();
      expect(find.text('Пинг: 53 ms'), findsOneWidget);
      expect(find.text('Пинг: 195 ms'), findsNothing);
      for (final request in requests) {
        if (!request.$2.isCompleted) request.$2.complete(null);
      }
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
