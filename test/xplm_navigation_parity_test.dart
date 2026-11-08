import 'package:pulse_vpn/features/settings/about_screen.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pulse_vpn/app/brand/app_brand.dart';
import 'package:pulse_vpn/app/theme/nord_signal_theme.dart';
import 'package:pulse_vpn/core/models/subscription.dart';
import 'package:pulse_vpn/core/services/vpn_service.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';
import 'package:pulse_vpn/features/account/account_screen.dart';
import 'package:pulse_vpn/features/account/widgets/xplm_account_details.dart';
import 'package:pulse_vpn/features/settings/settings_screen.dart';
import 'package:pulse_vpn/features/settings/xplm_security_screen.dart';
import 'package:pulse_vpn/features/settings/xplm_device_settings_screen.dart';
import 'package:pulse_vpn/features/settings/split_tunnel_screen.dart';
import 'package:pulse_vpn/features/settings/windows_split_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    PackageInfo.setMockInitialValues(
      appName: 'X-Plm',
      packageName: 'online.xplm.app',
      version: '1.0.48',
      buildNumber: '50',
      buildSignature: '',
    );
    await AppBrand.init();
    expect(
      AppBrand.current.isXplm,
      isTrue,
      reason: 'Run with --dart-define=BRAND=xplm',
    );
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  VpnController fixture() => VpnController(service: MockVpnService())
    ..subscriptionUrl = 'https://sub.x-plm.online/s/test-token-1234567890'
    ..linkState = SubscriptionLinkState.ready
    ..account = UserAccount.freshTrial().copyWith(
      accessExpiresAt: DateTime(2100),
    );
  Future<void> mount(
    WidgetTester tester,
    VpnController c,
    Widget page,
    TargetPlatform platform,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpWidget(
      ChangeNotifierProvider<VpnController>.value(
        value: c,
        child: MaterialApp(
          theme: NordSignalTheme.xplmLight.copyWith(platform: platform),
          home: page,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  Future<void> visible(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) await tester.scrollUntilVisible(finder, 150);
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets(
    'profile settings and security keep common button coordinates on three platforms',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final baselines = <String, Rect>{};
      final report = <String, Object?>{};
      final pages = <String, (Widget, List<String>)>{
        'profile': (
          const AccountScreen(embeddedInShell: true),
          [
            'profile-settings',
            'profile-notifications',
            'profile-security',
            'profile-traffic',
            'profile-support',
            'profile-about',
            'profile-logout',
            'profile-account',
          ],
        ),
        'settings': (
          const SettingsScreen(),
          [
            'preferences-notifications',
            'preferences-launch',
            'preferences-country',
            'preferences-split',
            'preferences-security',
            'preferences-device',
            'preferences-language',
          ],
        ),
        'account': (
          const AccountScreen(accountDetails: true),
          [
            'account-manage',
            'account-devices',
            'account-refresh',
            'account-add',
            'account-logout',
          ],
        ),
        'about': (
          const AboutScreen(),
          [
            'about-update',
            'about-site',
            'about-terms',
            'about-privacy',
            'about-support',
          ],
        ),
        'security': (
          const XplmSecurityScreen(),
          [
            'security-protocol',
            'security-dns',
            'security-fallback',
            'security-reconnect',
            'security-probe',
          ],
        ),
      };
      for (final platform in [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.windows,
      ]) {
        final c = fixture();
        expect(c.isKPaxSubscription, isTrue);
        for (final entry in pages.entries) {
          await mount(tester, c, entry.value.$1, platform);
          for (final id in entry.value.$2) {
            final finder = find.byKey(ValueKey(id));
            await visible(tester, finder);
            final rect = tester.getRect(finder);
            final offset =
                Scrollable.maybeOf(tester.element(finder))?.position.pixels ??
                0;
            final contentRect = rect.shift(Offset(0, offset));
            final key = '${entry.key}/$id';
            final baseline = baselines.putIfAbsent(key, () => contentRect);
            expect(
              contentRect.left,
              closeTo(baseline.left, .01),
              reason: '${platform.name}: $key x',
            );
            expect(
              contentRect.top,
              closeTo(baseline.top, .01),
              reason: '${platform.name}: $key y',
            );
            expect(
              contentRect.width,
              closeTo(baseline.width, .01),
              reason: '${platform.name}: $key width',
            );
            expect(
              contentRect.height,
              closeTo(baseline.height, .01),
              reason: '${platform.name}: $key height',
            );
            report['${platform.name}/$key'] = [
              contentRect.left,
              contentRect.top,
              contentRect.width,
              contentRect.height,
            ];
          }
          await tester.pumpWidget(const SizedBox.shrink());
        }
        c.dispose();
      }
      const output = String.fromEnvironment('XPLM_PARITY_REPORT');
      if (output.isNotEmpty) {
        await tester.runAsync(
          () => File(output).writeAsString(jsonEncode(report)),
        );
      }
    },
  );
  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.windows,
  ]) {
    testWidgets(
      '${platform.name}: profile routes open the same settings security and account screens',
      (tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final c = fixture();
        addTearDown(c.dispose);
        await mount(
          tester,
          c,
          const AccountScreen(embeddedInShell: true),
          platform,
        );
        final context = tester.element(find.byType(AccountScreen));
        await tester.tap(find.byKey(const ValueKey('profile-settings')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.byKey(const ValueKey('preferences-list')), findsOneWidget);
        await visible(
          tester,
          find.byKey(const ValueKey('preferences-security')),
        );
        await tester.tap(find.byKey(const ValueKey('preferences-security')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.byType(XplmSecurityScreen), findsOneWidget);
        Navigator.of(context).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        await visible(tester, find.byKey(const ValueKey('preferences-device')));
        await tester.tap(find.byKey(const ValueKey('preferences-device')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.byType(XplmDeviceSettingsScreen), findsOneWidget);
        Navigator.of(context).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        Navigator.of(context).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        await visible(tester, find.byKey(const ValueKey('profile-account')));
        await tester.tap(find.byKey(const ValueKey('profile-account')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.byType(XplmAccountDetails), findsOneWidget);
        Navigator.of(context).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        await visible(tester, find.byKey(const ValueKey('profile-logout')));
        await tester.tap(find.byKey(const ValueKey('profile-logout')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(find.text(c.strings.cancel));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(c.subscriptionUrl, isNotNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
    testWidgets(
      '${platform.name}: split entry stays in place and handles the platform honestly',
      (tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final c = fixture();
        addTearDown(c.dispose);
        await mount(tester, c, const SettingsScreen(), platform);
        final split = find.byKey(const ValueKey('preferences-split'));
        await visible(tester, split);
        await tester.tap(split);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        if (platform == TargetPlatform.iOS) {
          expect(find.byType(AlertDialog), findsOneWidget);
        } else if (platform == TargetPlatform.windows) {
          expect(find.byType(WindowsSplitScreen), findsOneWidget);
        } else {
          expect(find.byType(SplitTunnelScreen), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
