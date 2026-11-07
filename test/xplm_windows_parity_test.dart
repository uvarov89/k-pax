import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulse_vpn/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:pulse_vpn/app/brand/app_brand.dart';
import 'package:pulse_vpn/app/theme/nord_signal_theme.dart';
import 'package:pulse_vpn/core/services/vpn_service.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';
import 'package:pulse_vpn/features/shell/xplm_shell.dart';

void main() {
  setUpAll(() async {
    PackageInfo.setMockInitialValues(
      appName: 'X-Plm',
      packageName: 'online.xplm.app',
      version: '1.0.46',
      buildNumber: '48',
      buildSignature: '',
    );
    await AppBrand.init();
    expect(AppBrand.current.isXplm, isTrue);
  });

  testWidgets(
    'Windows exposes and saves the same Wi-Fi auto-connect setting',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final controller = VpnController(service: MockVpnService());
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: controller,
          child: MaterialApp(
            theme: NordSignalTheme.xplmLight.copyWith(platform: TargetPlatform.windows),
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pump();
      final wifi = find.text(controller.strings.autoConnectWifi);
      expect(wifi, findsOneWidget);
      expect(find.text(controller.strings.autoConnectMobile), findsNothing);
      await tester.ensureVisible(wifi);
      await tester.tap(wifi);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(controller.appSettings.autoConnectOnWifi, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !Platform.isWindows,
  );

  testWidgets('Windows tabs stay aligned with Android width when maximized', (
    tester,
  ) async {
    final controller = VpnController(service: MockVpnService());
    addTearDown(controller.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    expect(NordSignalTheme.xplmLight.visualDensity, VisualDensity.standard);
    expect(
      NordSignalTheme.xplmLight.materialTapTargetSize,
      MaterialTapTargetSize.padded,
    );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          theme: NordSignalTheme.xplmLight.copyWith(
            platform: TargetPlatform.windows,
          ),
          home: const XplmShell(),
        ),
      ),
    );
    await tester.pump();
    expect(tester.getSize(find.byType(XplmBottomNav)).width, 440);
    expect(tester.getRect(find.byType(XplmBottomNav)).center.dx, 640);
    await tester.tap(find.text('Профиль').last);
    await tester.pump();
    expect(tester.getSize(find.byType(XplmBottomNav)).width, 440);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
