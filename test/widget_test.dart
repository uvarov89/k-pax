import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_vpn/app/pulse_app.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _germany =
    'vless://11111111-1111-1111-1111-111111111111@203.0.113.10:443?security=reality&sni=www.microsoft.com&pbk=pk&sid=ab&type=tcp#Germany';
const _finland =
    'vless://11111111-1111-1111-1111-111111111111@203.0.113.20:443?security=reality&sni=www.microsoft.com&pbk=pk&sid=ab&type=tcp#Finland';

Future<VpnController> _start(WidgetTester tester, Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  final controller = VpnController();
  // hydrate runs real processes (netsh on Windows) that never finish under the fake test clock.
  await tester.runAsync(controller.hydrate);
  await tester.pumpWidget(PulseApp(controller: controller));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.runAsync(() async {
    for (var i = 0; i < 60 && controller.linkState == SubscriptionLinkState.loading; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  });
  await _settle(tester);
  return controller;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('K-Pax home shows connect, profile and settings', (tester) async {
    await _start(tester, {});

    expect(find.text('K-Pax'), findsWidgets);
    expect(find.text('Подключить'), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.person_outline));
    await _settle(tester);
    expect(find.textContaining('Почта'), findsWidgets);
    expect(find.text('Продолжить'), findsOneWidget);
    expect(find.text('Мои подписки'), findsNothing);
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await _settle(tester);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await _settle(tester);
    expect(find.text('Настройки'), findsWidgets);
    expect(find.text('Подписка'), findsWidgets);
  });

  testWidgets('other providers: list, switch and no K-Pax payment', (tester) async {
    final controller = await _start(tester, {
      'subscription_url': _germany,
      'subscriptions': jsonEncode([
        {'url': _germany, 'name': 'My VPN'},
        {'url': _finland, 'name': 'Second VPN'},
      ]),
    });
    expect(controller.isKPaxSubscription, isFalse);
    expect(controller.hasAccess, isTrue);
    expect(controller.locations.map((item) => item.countryCode), contains('DE'));

    await tester.tap(find.byIcon(Icons.person_outline));
    await _settle(tester);
    expect(find.text('Мои подписки'), findsOneWidget);
    expect(find.text('My VPN'), findsWidgets);
    expect(find.text('Second VPN'), findsOneWidget);
    expect(find.textContaining('VPN'), findsWidgets);
    expect(find.text('Управление подпиской'), findsNothing);
    expect(find.text('15 дней за друга'), findsNothing);

    await tester.runAsync(() => controller.switchSubscription(_finland));
    await _settle(tester);
    expect(controller.subscriptionUrl, _finland);
    expect(controller.locations.map((item) => item.countryCode), contains('FI'));
    expect(controller.locations.map((item) => item.countryCode), isNot(contains('DE')));

    await tester.runAsync(() => controller.removeSubscription(_germany));
    await _settle(tester);
    expect(controller.subscriptions.map((item) => item.name), ['Second VPN']);
    expect(controller.subscriptionUrl, _finland);
  });
}
