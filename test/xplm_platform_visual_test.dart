import 'package:pulse_vpn/features/home/onboarding_screen.dart';
import 'package:pulse_vpn/features/settings/about_screen.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pulse_vpn/app/brand/app_brand.dart';
import 'package:pulse_vpn/app/pulse_app.dart';
import 'package:pulse_vpn/app/theme/nord_signal_theme.dart';
import 'package:pulse_vpn/core/models/connection_models.dart';
import 'package:pulse_vpn/core/models/subscription.dart';
import 'package:pulse_vpn/core/models/server_location.dart';
import 'package:pulse_vpn/core/services/vpn_service.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';
import 'package:pulse_vpn/features/home/widgets/xplm_home_layout.dart';
import 'package:pulse_vpn/features/locations/country_picker_screen.dart';
import 'package:pulse_vpn/features/paywall/paywall_screen.dart';
import 'package:pulse_vpn/features/account/account_screen.dart';
import 'package:pulse_vpn/features/settings/settings_screen.dart';
import 'package:pulse_vpn/features/settings/xplm_security_screen.dart';
import 'package:pulse_vpn/features/shell/xplm_shell.dart';
import 'package:pulse_vpn/features/xplm/widgets/xplm_html_widgets.dart';

class _VisualController extends VpnController {
  _VisualController() : super(service: MockVpnService()) {
    subscriptionUrl = 'https://sub.x-plm.online/s/test-token-1234567890';
    linkState = SubscriptionLinkState.ready;
    account = UserAccount.freshTrial().copyWith(
      accessExpiresAt: DateTime(2100, 12, 25),
    );
    selectedLocation = locations[1];
    locationMode = LocationMode.country;
    lastProbeResults = {'Германия': 28, 'Финляндия': 62, 'Болгария': 170};
  }
  @override
  bool get hasExpiry => true;
  @override
  ServerLocation get effectiveLocation => selectedLocation;
  @override
  List<ServerLocation> get locations => const [
    ServerLocation.auto,
    ServerLocation(
      id: 'de',
      countryCode: 'DE',
      nameRu: 'Германия',
      latencyMs: 28,
    ),
    ServerLocation(
      id: 'fi',
      countryCode: 'FI',
      nameRu: 'Финляндия',
      latencyMs: 34,
    ),
    ServerLocation(
      id: 'bg',
      countryCode: 'BG',
      nameRu: 'Болгария',
      latencyMs: 42,
    ),
    ServerLocation(
      id: 'fr',
      countryCode: 'FR',
      nameRu: 'Франция',
      latencyMs: 48,
    ),
    ServerLocation(
      id: 'nl',
      countryCode: 'NL',
      nameRu: 'Нидерланды',
      latencyMs: 52,
    ),
    ServerLocation(id: 'us', countryCode: 'US', nameRu: 'США', latencyMs: 76),
    ServerLocation(
      id: 'gb',
      countryCode: 'GB',
      nameRu: 'Великобритания',
      latencyMs: 80,
    ),
    ServerLocation(
      id: 'sg',
      countryCode: 'SG',
      nameRu: 'Сингапур',
      latencyMs: 112,
    ),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await AppBrand.init();
    await (FontLoader('XplmArial')
          ..addFont(rootBundle.load('assets/fonts/Arimo-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Arimo-Italic.ttf')))
        .load();
    final loader = FontLoader('Manrope');
    for (final weight in [
      'Regular',
      'Medium',
      'SemiBold',
      'Bold',
      'ExtraBold',
    ]) {
      loader.addFont(rootBundle.load('assets/fonts/Manrope-$weight.ttf'));
    }
    await loader.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final buildVersion = RegExp(
      r'^version:\s*([^+\r\n]+)\+(\d+)',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync())!;
    PackageInfo.setMockInitialValues(
      appName: 'X-Plm',
      packageName: 'online.xplm.app',
      version: buildVersion[1]!,
      buildNumber: buildVersion[2]!,
      buildSignature: '',
    );
  });
  testWidgets('render identical common screens for Android and Windows', (
    tester,
  ) async {
    const output = String.fromEnvironment('XPLM_VISUAL_DIR');
    final previousShadows = debugDisableShadows;
    debugDisableShadows = false;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      debugDisableShadows = previousShadows;
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final platform in [
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.windows,
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      for (final name in [
        'intro',
        'home',
        'connecting',
        'connected',
        'servers',
        'subscription',
        'profile',
        'account',
        'settings',
        'security',
        'about',
      ]) {
        SharedPreferences.setMockInitialValues({'onboarding_seen': true});
        final c = _VisualController();
        if (name == 'connecting') {
          c.connectionState = VpnConnectionState.connecting;
        }
        if (name == 'connected') {
          c.connectionState = VpnConnectionState.connected;
        }
        final key = GlobalKey();
        final page = switch (name) {
          'intro' => const OnboardingScreen(),
          'home' || 'connecting' || 'connected' => XplmHomeLayout(
            onConnectPressed: () async {},
            onOpenProfile: () {},
          ),
          'servers' => const CountryPickerScreen(embeddedInShell: true),
          'subscription' => const PaywallScreen(embeddedInShell: true),
          'profile' => const AccountScreen(embeddedInShell: true),
          'account' => const AccountScreen(
            accountDetails: true,
            embeddedInShell: true,
          ),
          'settings' => const SettingsScreen(),
          'about' => const AboutScreen(),
          _ => const XplmSecurityScreen(),
        };
        final tab = switch (name) {
          'servers' => 1,
          'subscription' => 2,
          'profile' || 'account' || 'settings' || 'security' || 'about' => 3,
          _ => 0,
        };
        await tester.pumpWidget(
          ChangeNotifierProvider<VpnController>.value(
            value: c,
            child: MaterialApp(
              theme: NordSignalTheme.xplmLight.copyWith(platform: platform),
              scrollBehavior: const XplmScrollBehavior(),
              home: MediaQuery(
                data: const MediaQueryData(
                  size: Size(390, 844),
                  disableAnimations: true,
                  padding: EdgeInsets.only(top: 44),
                ),
                child: RepaintBoundary(
                  key: key,
                  child: TickerMode(
                    enabled: false,
                    child: Scaffold(
                      body: XplmTabNavigation(select: (_) {}, child: page),
                      bottomNavigationBar: XplmBottomNav(
                        index: tab,
                        onChanged: (_) {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        for (final asset in [
          'xplm_home_earth.png',
          'xplm_home_shield.png',
          'xplm_servers_earth.png',
          'xplm_subscription_earth.png',
          'xplm_gift.png',
          'xplm_profile_logo.png',
          'xplm_logo.png',
          'xplm_flags/de.png',
          'xplm_flags/fi.png',
          'xplm_flags/bg.png',
          'xplm_flags/fr.png',
          'xplm_flags/nl.png',
          'xplm_flags/us.png',
          'xplm_flags/gb.png',
          'xplm_flags/sg.png',
        ]) {
          await tester.runAsync(
            () => precacheImage(
              AssetImage('assets/brand/$asset'),
              key.currentContext!,
            ),
          );
        }
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          tester.takeException(),
          isNull,
          reason: '${platform.name}/$name',
        );
        if (output.isNotEmpty) {
          await tester.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '$output/${platform.name}-$name.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
      }
    }
    debugDefaultTargetPlatformOverride = null;
    debugDisableShadows = previousShadows;
  });
}
