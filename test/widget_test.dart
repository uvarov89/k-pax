import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_vpn/app/pulse_app.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('K-Pax home shows connect, plan and settings', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = VpnController();
    await controller.hydrate();

    await tester.pumpWidget(PulseApp(controller: controller));
    await tester.pumpAndSettle();

    // Dismiss trial welcome if shown.
    if (find.text('Продолжить').evaluate().isNotEmpty) {
      await tester.tap(find.text('Продолжить'));
      await tester.pumpAndSettle();
    }

    expect(find.text('K-Pax'), findsWidgets);
    expect(find.text('Подключить'), findsOneWidget);
    expect(find.text('Подробно'), findsNothing);
    expect(find.text('Почта, ник или ссылка'), findsNothing);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    expect(find.byIcon(Icons.person_outline), findsOneWidget);

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    expect(find.text('Почта, ник или ссылка'), findsOneWidget);
    expect(find.text('Получить доступ'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Настройки'), findsWidgets);
    expect(find.text('Подписка'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('Пользовательское соглашение'),
      200,
    );
    await tester.tap(find.text('Пользовательское соглашение'));
    await tester.pumpAndSettle();
    expect(find.textContaining('14 дней'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Политика приватности'), 200);
    await tester.tap(find.text('Политика приватности'));
    await tester.pumpAndSettle();
    expect(find.textContaining('не продаём'), findsOneWidget);
  });
}
