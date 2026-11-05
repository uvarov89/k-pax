import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulse_vpn/app/brand/app_brand.dart';
import 'package:pulse_vpn/app/theme/nord_signal_theme.dart';
import 'package:pulse_vpn/core/services/vpn_service.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';
import 'package:pulse_vpn/features/account/account_screen.dart';
import 'package:pulse_vpn/features/locations/country_picker_screen.dart';
import 'package:pulse_vpn/features/paywall/paywall_screen.dart';
import 'package:pulse_vpn/features/xplm/widgets/xplm_html_widgets.dart';

void main() {
  testWidgets('K-Pax keeps its original server, payment and account screens', (
    tester,
  ) async {
    expect(
      AppBrand.current.isKpax,
      isTrue,
      reason: 'Run with --dart-define=BRAND=kpax',
    );
    SharedPreferences.setMockInitialValues({});
    final controller = VpnController(service: MockVpnService());
    addTearDown(controller.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final entry in <(Widget, String)>[
      (const CountryPickerScreen(), controller.strings.auto),
      (const PaywallScreen(), controller.strings.buyOnSite),
      (
        const AccountScreen(accountDetails: true),
        controller.strings.pasteLinkTitle,
      ),
    ]) {
      await tester.pumpWidget(
        ChangeNotifierProvider<VpnController>.value(
          value: controller,
          child: MaterialApp(theme: NordSignalTheme.dark, home: entry.$1),
        ),
      );
      await tester.pump();
      expect(find.text(entry.$2), findsWidgets);
      expect(find.byType(XplmHtmlPage), findsNothing);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });
}
