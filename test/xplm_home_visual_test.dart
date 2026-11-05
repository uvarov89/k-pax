import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pulse_vpn/app/brand/app_brand.dart';
import 'package:pulse_vpn/app/theme/xplm_colors.dart';
import 'package:pulse_vpn/features/home/widgets/xplm_home_layout.dart';
import 'package:pulse_vpn/features/locations/widgets/xplm_signal_widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('X-Plm home ref2 chrome widgets present', (tester) async {
    expect(AppBrand.current.isXplm, isTrue,
        reason: 'Run with --dart-define=BRAND=xplm');

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: XplmColors.paper,
          body: const Column(
            children: [
              XplmGlobeShield(connected: true, busy: false),
              Text('Подключено'),
              Text('Отключить'),
              XplmCountryFlag(countryCode: 'DE', size: 36),
              XplmPingBars(latencyMs: 28),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Подключено'), findsOneWidget);
    expect(find.text('Отключить'), findsOneWidget);
    expect(find.byType(XplmGlobeShield), findsOneWidget);
    expect(find.byType(XplmCountryFlag), findsOneWidget);
    expect(find.byType(XplmPingBars), findsOneWidget);
  });
}
