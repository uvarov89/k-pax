import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulse_vpn/app/brand/app_brand.dart';
import 'package:pulse_vpn/app/theme/nord_signal_theme.dart';
import 'package:pulse_vpn/core/models/app_settings.dart';
import 'package:pulse_vpn/core/models/connection_models.dart';
import 'package:pulse_vpn/core/models/server_location.dart';
import 'package:pulse_vpn/core/models/subscription.dart';
import 'package:pulse_vpn/core/models/tunnel_node.dart';
import 'package:pulse_vpn/core/services/vpn_service.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';
import 'package:pulse_vpn/features/locations/country_picker_screen.dart';
import 'package:pulse_vpn/features/xplm/widgets/xplm_html_widgets.dart';

const _dePrimary = TunnelNode(
  countryId: 'de',
  countryCode: 'DE',
  countryName: 'Германия',
  kind: TunnelKind.reality,
  host: 'de-primary.invalid',
  port: 443,
  outbound: {},
);
const _deSpare = TunnelNode(
  countryId: 'de',
  countryCode: 'DE',
  countryName: 'Германия',
  kind: TunnelKind.reality,
  host: 'de-spare.invalid',
  port: 2443,
  outbound: {},
);
const _fiPrimary = TunnelNode(
  countryId: 'fi',
  countryCode: 'FI',
  countryName: 'Финляндия',
  kind: TunnelKind.reality,
  host: 'fi-primary.invalid',
  port: 443,
  outbound: {},
);
const _fiSpare = TunnelNode(
  countryId: 'fi',
  countryCode: 'FI',
  countryName: 'Финляндия',
  kind: TunnelKind.reality,
  host: 'fi-spare.invalid',
  port: 2443,
  outbound: {},
);

class _ScriptedVpnService implements VpnService {
  _ScriptedVpnService({required this.failHosts});

  final Set<String> failHosts;
  final List<String> startedHosts = [];

  @override
  Stream<String> get statusStream => const Stream.empty();

  @override
  Stream<TunnelSpeed> get trafficStream => const Stream.empty();

  @override
  Future<void> connect({
    required ServerLocation location,
    required ProSettings settings,
    required AppSettings appSettings,
    required TunnelNode node,
  }) async {
    startedHosts.add(node.host);
    if (failHosts.contains(node.host)) {
      throw StateError('fail ${node.host}');
    }
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<Map<String, int>> probeNodes() async => {};
}

VpnController _readyController(_ScriptedVpnService service) {
  final c = VpnController(service: service);
  c.subscriptionUrl = 'https://sub.example/s/test';
  c.linkState = SubscriptionLinkState.ready;
  c.profile = const SubscriptionProfile(
    nodes: [_dePrimary, _deSpare, _fiPrimary, _fiSpare],
  );
  c.account = UserAccount.freshTrial();
  c.locationMode = LocationMode.auto;
  c.selectedLocation = ServerLocation.auto;
  c.proSettings = const ProSettings(protocolFallback: true);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Auto is the first server row and selecting it keeps Auto mode', (
    tester,
  ) async {
    PackageInfo.setMockInitialValues(
      appName: 'K-Pax',
      packageName: 'space.kpax.app',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    await AppBrand.init();
    final controller = VpnController(service: MockVpnService());
    addTearDown(controller.dispose);
    controller.linkState = SubscriptionLinkState.ready;
    controller.account = UserAccount.freshTrial();
    controller.selectedLocation = const ServerLocation(
      id: 'de',
      countryCode: 'DE',
      nameRu: 'Германия',
      latencyMs: 28,
    );
    controller.locationMode = LocationMode.country;

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ChangeNotifierProvider<VpnController>.value(
        value: controller,
        child: MaterialApp(
          theme: NordSignalTheme.dark,
          home: const CountryPickerScreen(embeddedInShell: true),
        ),
      ),
    );
    await tester.pump();

    final autoText = find.text(controller.strings.auto);
    expect(autoText, findsWidgets);
    expect(
      find.text(controller.strings.bestServerAuto),
      findsWidgets,
      reason: 'Auto row shows the smart-path subtitle',
    );

    // First list entry should be Auto (pinned on X-Plm, catalog order on K-Pax).
    final autoRow = find.byKey(const ValueKey('server-auto'));
    if (AppBrand.current.isXplm) {
      expect(autoRow, findsOneWidget);
      expect(find.byType(XplmHtmlPage), findsOneWidget);
    }

    await tester.tap(autoText.first);
    await tester.pump();
    expect(controller.selectedLocation.isAuto, isTrue);
    expect(controller.locationMode, LocationMode.auto);
    await tester.pumpWidget(const SizedBox());
  }, skip: Platform.isLinux);

  test('Auto connect fails over to another country after same-country spare', () async {
    final service = _ScriptedVpnService(
      failHosts: {'de-primary.invalid', 'de-spare.invalid'},
    );
    final c = _readyController(service);
    addTearDown(c.dispose);

    final ok = await c.connect();
    expect(ok, isTrue);
    expect(c.isConnected, isTrue);
    expect(c.connectedNode?.countryId, 'fi');
    // :443 first, then RU front spare, then Auto jumps to FI :443.
    expect(service.startedHosts, [
      'de-primary.invalid',
      'de-spare.invalid',
      'fi-primary.invalid',
    ]);
  });

  test('manual country does not jump to another country after spare failure', () async {
    final service = _ScriptedVpnService(
      failHosts: {
        'de-primary.invalid',
        'de-spare.invalid',
        'fi-primary.invalid',
        'fi-spare.invalid',
      },
    );
    final c = _readyController(service);
    addTearDown(c.dispose);
    c.locationMode = LocationMode.country;
    c.selectedLocation = const ServerLocation(
      id: 'de',
      countryCode: 'DE',
      nameRu: 'Германия',
    );

    await c.connect();
    expect(c.isConnected, isFalse);
    expect(c.connectionState, VpnConnectionState.error);
    expect(
      service.startedHosts,
      ['de-primary.invalid', 'de-spare.invalid'],
      reason: 'manual DE must not try FI; :443 then front spare',
    );
  });

  test('Auto prefers direct :443 over RU front for sticky pick', () async {
    final service = _ScriptedVpnService(failHosts: {});
    final c = _readyController(service);
    addTearDown(c.dispose);

    final ok = await c.connect();
    expect(ok, isTrue);
    expect(c.connectedNode?.port, 443);
    expect(service.startedHosts.first, 'de-primary.invalid');
  });

  test('manual country prefers direct :443 over RU front', () async {
    final service = _ScriptedVpnService(failHosts: {});
    final c = _readyController(service);
    addTearDown(c.dispose);
    c.locationMode = LocationMode.country;
    c.selectedLocation = const ServerLocation(
      id: 'fi',
      countryCode: 'FI',
      nameRu: 'Финляндия',
    );

    final ok = await c.connect();
    expect(ok, isTrue);
    expect(c.connectedNode?.countryId, 'fi');
    expect(service.startedHosts.first, 'fi-primary.invalid');
    expect(c.connectedNode?.port, 443);
  });

  test('Auto prefers last SoftProbe-OK country on next connect', () async {
    SharedPreferences.setMockInitialValues({
      'last_good_auto_country': 'fi',
    });
    final service = _ScriptedVpnService(failHosts: {});
    final c = _readyController(service);
    addTearDown(c.dispose);

    final ok = await c.connect();
    expect(ok, isTrue);
    expect(c.connectedNode?.countryId, 'fi');
    expect(service.startedHosts.first, 'fi-primary.invalid');
  });

  test('Reconnect prefers last SoftProbe-OK Reality endpoint over :443', () async {
    // Measured sticky: DE :443 SoftProbe fails, front works.
    // Next connect must start on the proven front — not re-fail :443 every time.
    SharedPreferences.setMockInitialValues({
      'last_good_endpoint': 'de|de-spare.invalid|2443',
    });
    final service = _ScriptedVpnService(failHosts: {});
    final c = _readyController(service);
    addTearDown(c.dispose);

    final ok = await c.connect();
    expect(ok, isTrue);
    expect(service.startedHosts.first, 'de-spare.invalid');
    expect(c.connectedNode?.port, 2443);
  });

  test('Auto skips gRPC spare and hops country after Reality fails', () async {
    const deGrpc = TunnelNode(
      countryId: 'de',
      countryCode: 'DE',
      countryName: 'Германия',
      kind: TunnelKind.grpc,
      host: 'de-grpc.invalid',
      port: 8443,
      outbound: {},
    );
    final service = _ScriptedVpnService(
      failHosts: {'de-primary.invalid', 'de-spare.invalid', 'de-grpc.invalid'},
    );
    final c = _readyController(service);
    addTearDown(c.dispose);
    c.profile = const SubscriptionProfile(
      nodes: [_dePrimary, _deSpare, deGrpc, _fiPrimary, _fiSpare],
    );

    final ok = await c.connect();
    expect(ok, isTrue);
    expect(c.connectedNode?.countryId, 'fi');
    expect(service.startedHosts, isNot(contains('de-grpc.invalid')));
    expect(service.startedHosts, [
      'de-primary.invalid',
      'de-spare.invalid',
      'fi-primary.invalid',
    ]);
  });

  test('Auto tries CDN/message before hopping country after Reality fails', () async {
    const deMessage = TunnelNode(
      countryId: 'de',
      countryCode: 'DE',
      countryName: 'Германия',
      kind: TunnelKind.message,
      host: 'cdn.example.invalid',
      port: 443,
      outbound: {},
    );
    final service = _ScriptedVpnService(
      failHosts: {'de-primary.invalid', 'de-spare.invalid'},
    );
    final c = _readyController(service);
    addTearDown(c.dispose);
    c.profile = const SubscriptionProfile(
      nodes: [_dePrimary, _deSpare, deMessage, _fiPrimary, _fiSpare],
    );

    final ok = await c.connect();
    expect(ok, isTrue);
    expect(c.connectedNode?.kind, TunnelKind.message);
    expect(service.startedHosts, [
      'de-primary.invalid',
      'de-spare.invalid',
      'cdn.example.invalid',
    ]);
    expect(service.startedHosts, isNot(contains('fi-primary.invalid')));
  });

  test('selectLocation while connected reconnects to the new country', () async {
    final service = _ScriptedVpnService(failHosts: {});
    final c = _readyController(service);
    addTearDown(c.dispose);
    c.locationMode = LocationMode.country;
    c.selectedLocation = const ServerLocation(
      id: 'de',
      countryCode: 'DE',
      nameRu: 'Германия',
    );

    expect(await c.connect(), isTrue);
    expect(c.connectedNode?.countryId, 'de');
    final hostsBefore = List<String>.from(service.startedHosts);

    await c.selectLocation(
      const ServerLocation(
        id: 'fi',
        countryCode: 'FI',
        nameRu: 'Финляндия',
      ),
    );
    // Soft reconnect is async; allow connect() to finish.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    for (var i = 0; i < 40 && c.isBusy; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    expect(c.selectedLocation.id, 'fi');
    expect(c.isConnected, isTrue);
    expect(c.connectedNode?.countryId, 'fi');
    expect(service.startedHosts.length, greaterThan(hostsBefore.length));
    expect(service.startedHosts.last, 'fi-primary.invalid');
  });

  test('selectLocation while disconnected only updates preference', () async {
    final service = _ScriptedVpnService(failHosts: {});
    final c = _readyController(service);
    addTearDown(c.dispose);

    await c.selectLocation(
      const ServerLocation(
        id: 'fi',
        countryCode: 'FI',
        nameRu: 'Финляндия',
      ),
    );
    expect(c.selectedLocation.id, 'fi');
    expect(c.isConnected, isFalse);
    expect(service.startedHosts, isEmpty);
  });

  test('trafficStatsLabel shows live rates only', () {
    final c = _readyController(_ScriptedVpnService(failHosts: {}));
    addTearDown(c.dispose);
    expect(
      c.trafficStatsLabel,
      '↓ 0 Б/с   ↑ 0 Б/с',
    );
    c.downloadBytesPerSec = 10 * 1024;
    c.uploadBytesPerSec = 4 * 1024;
    expect(
      c.trafficStatsLabel,
      '↓ 10 КБ/с   ↑ 4 КБ/с',
    );
  });
}
