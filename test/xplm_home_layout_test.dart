import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pulse_vpn/app/theme/nord_signal_theme.dart';
import 'package:pulse_vpn/core/models/connection_models.dart';
import 'package:pulse_vpn/core/models/server_location.dart';
import 'package:pulse_vpn/core/models/subscription.dart';
import 'package:pulse_vpn/core/services/vpn_service.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';
import 'package:pulse_vpn/features/home/widgets/xplm_home_layout.dart';
import 'package:pulse_vpn/features/shell/xplm_shell.dart';

class _VisualController extends VpnController {
  _VisualController() : super(service: MockVpnService());
  @override
  ServerLocation get effectiveLocation => selectedLocation;
  @override
  bool get hasExpiry => true;
}

void main() {
  setUpAll(() async {
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
  });
  testWidgets('home adapts and preserves connection actions and busy state', (
    tester,
  ) async {
    final controller = _VisualController()
      ..linkState = SubscriptionLinkState.ready
      ..account = UserAccount.freshTrial().copyWith(
        accessExpiresAt: DateTime(2100, 12, 25),
      )
      ..selectedLocation = const ServerLocation(
        id: 'de',
        countryCode: 'DE',
        nameRu: 'Германия',
        latencyMs: 28,
      );
    addTearDown(controller.dispose);
    var taps = 0;
    final capture = GlobalKey();
    Future<void> show(
      Size size, {
      double textScale = 1,
      bool reduce = false,
    }) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        ChangeNotifierProvider<VpnController>.value(
          value: controller,
          child: MaterialApp(
            theme: NordSignalTheme.xplmLight,
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                disableAnimations: reduce,
                padding: const EdgeInsets.only(top: 44),
                textScaler: TextScaler.linear(textScale),
              ),
              child: RepaintBoundary(
                key: capture,
                child: Scaffold(
                  body: XplmHomeLayout(
                    onConnectPressed: () async {
                      taps++;
                    },
                    onOpenProfile: () {},
                  ),
                  bottomNavigationBar: XplmBottomNav(
                    index: 0,
                    onChanged: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await show(const Size(390, 844));
    for (final asset in ['xplm_home_earth.png', 'xplm_home_shield.png']) {
      await tester.runAsync(
        () => precacheImage(
          AssetImage('assets/brand/$asset'),
          tester.element(find.byType(XplmHomeLayout)),
        ),
      );
    }
    await tester.pump();
    await tester.tap(find.text(controller.strings.connect));
    expect(taps, 1);
    controller.lastProbeResults = {'Германия': 66, 'Финляндия': 10};
    await show(const Size(390, 844));
    expect(find.text('Пинг: 66 ms'), findsOneWidget);
    controller.lastProbeResults = {'Германия': -1, 'Финляндия': 10};
    await show(const Size(390, 844));
    expect(find.text('Пинг: —'), findsOneWidget);
    controller.lastProbeResults = null;
    controller.connectionState = VpnConnectionState.connecting;
    await show(const Size(390, 844));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    const animationDir = String.fromEnvironment('XPLM_ANIMATION_DIR');
    if (animationDir.isNotEmpty) {
      for (var frame = 0; frame < 16; frame++) {
        await tester.pump(const Duration(milliseconds: 125));
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '$animationDir/frame-${frame.toString().padLeft(2, '0')}.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
    await tester.tap(find.byType(CircularProgressIndicator));
    expect(taps, 1);
    controller.connectionState = VpnConnectionState.connected;
    await show(const Size(390, 844));
    expect(find.text('Ваш интернет защищён'), findsOneWidget);
    await tester.tap(find.text(controller.strings.disconnect));
    expect(taps, 2);
    controller.connectionState = VpnConnectionState.disconnecting;
    await show(const Size(390, 844));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text(controller.strings.disconnecting), findsOneWidget);
    await tester.tap(find.byType(CircularProgressIndicator));
    expect(taps, 2);
    controller.connectionState = VpnConnectionState.connected;
    await show(const Size(390, 844));
    await tester.pumpAndSettle();

    final output = const String.fromEnvironment('XPLM_SCREENSHOT');
    if (output.isNotEmpty) {
      final boundary =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(output).writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }
    for (final size in [
      const Size(320, 568),
      const Size(440, 956),
      const Size(1024, 768),
    ]) {
      await show(size, textScale: 1.3);
    }
    controller.connectionState = VpnConnectionState.connecting;
    await show(const Size(390, 844), reduce: true);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .value,
      .75,
    );
    controller.account = UserAccount.empty();
    controller.connectionState = VpnConnectionState.disconnected;
    await show(const Size(390, 844));
    expect(find.text('Подписка активна'), findsNothing);
    expect(find.text('Нет активной подписки'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
