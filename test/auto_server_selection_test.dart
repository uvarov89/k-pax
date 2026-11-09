import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
  final c = VpnController(
    service: service,
    tcpProbe: (_, __) async => null,
  );
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
  });

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
      reason: 'manual DE must not try FI',
    );
  });
}
