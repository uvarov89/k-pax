import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/link.dart';
import 'package:pulse_vpn/app/brand/app_brand.dart';
import 'package:pulse_vpn/app/theme/nord_signal_theme.dart';
import 'package:pulse_vpn/core/models/connection_models.dart';
import 'package:pulse_vpn/core/models/server_location.dart';
import 'package:pulse_vpn/core/models/subscription.dart';
import 'package:pulse_vpn/core/services/vpn_service.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';
import 'package:pulse_vpn/features/account/account_screen.dart';
import 'package:pulse_vpn/features/locations/country_picker_screen.dart';
import 'package:pulse_vpn/features/paywall/paywall_screen.dart';
import 'package:pulse_vpn/features/shell/xplm_shell.dart';
import 'package:pulse_vpn/features/xplm/widgets/xplm_html_widgets.dart';

const _countries = [
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
  ServerLocation(id: 'fr', countryCode: 'FR', nameRu: 'Франция', latencyMs: 48),
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

class _Fixture extends VpnController {
  _Fixture() : super(service: MockVpnService()) {
    linkState = SubscriptionLinkState.ready;
    subscriptionUrl = 'https://sub.x-plm.online/s/test';
    account = UserAccount.freshTrial();
    selectedLocation = _countries.first;
    locationMode = LocationMode.country;
    downloadBytesPerSec = 2048;
    uploadBytesPerSec = 1024;
  }
  bool empty = false;
  int refreshes = 0;
  int removals = 0;
  @override
  List<ServerLocation> get locations => [
    ServerLocation.auto,
    if (!empty) ..._countries,
  ];
  @override
  Future<void> selectLocation(ServerLocation location) async {
    selectedLocation = location;
    locationMode = location.isAuto ? LocationMode.auto : LocationMode.country;
    notifyListeners();
  }

  @override
  Future<void> refreshAccessAfterPayment({bool openAccount = false}) async {
    refreshes++;
  }

  @override
  Future<void> forgetSubscriptionLink() async {
    removals++;
    subscriptionUrl = null;
    linkState = SubscriptionLinkState.missing;
    notifyListeners();
  }
}

class _Launcher extends UrlLauncherPlatform {
  final urls = <String>[];
  @override
  LinkDelegate? get linkDelegate => null;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    urls.add(url);
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('XplmArial')
          ..addFont(rootBundle.load('assets/fonts/Arimo-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Arimo-Italic.ttf')))
        .load();
    await (FontLoader(
      'Manrope',
    )..addFont(rootBundle.load('assets/fonts/Manrope-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final version = RegExp(
      r'^version:\s*([^+]+)\+(\d+)',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync())!;
    PackageInfo.setMockInitialValues(
      appName: 'XPLM VPN',
      packageName: 'online.xplm.vpn',
      version: version[1]!,
      buildNumber: version[2]!,
      buildSignature: '',
    );
  });
  late _Launcher launcher;
  late UrlLauncherPlatform originalLauncher;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    originalLauncher = UrlLauncherPlatform.instance;
    launcher = _Launcher();
    UrlLauncherPlatform.instance = launcher;
  });
  tearDown(() => UrlLauncherPlatform.instance = originalLauncher);

  Future<void> show(
    WidgetTester tester,
    _Fixture controller,
    Widget screen,
    int tab, {
    Size size = const Size(390, 844),
    double scale = 1,
    GlobalKey? capture,
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
              padding: const EdgeInsets.only(top: 44),
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: RepaintBoundary(
              key: capture,
              child: Scaffold(
                body: XplmTabNavigation(select: (_) {}, child: screen),
                bottomNavigationBar: XplmBottomNav(
                  index: tab,
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> screenshot(
    WidgetTester tester,
    GlobalKey key,
    String name,
    List<String> assets,
  ) async {
    const output = String.fromEnvironment('XPLM_OUTPUT_DIR');
    if (output.isEmpty) return;
    final previousShadows = debugDisableShadows;
    try {
      debugDisableShadows = false;
      for (final asset in assets) {
        await tester.runAsync(
          () => precacheImage(
            AssetImage('assets/brand/$asset'),
            key.currentContext!,
          ),
        );
      }
      for (final object in tester.allRenderObjects) {
        object.markNeedsPaint();
      }
      await tester.pumpAndSettle();
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '$output/xplm-$name.png',
        ).writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    } finally {
      debugDisableShadows = previousShadows;
    }
  }

  void cleanup(WidgetTester tester, _Fixture c) {
    addTearDown(c.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('servers: real rows, filtering, search and selection', (
    tester,
  ) async {
    final c = _Fixture();
    cleanup(tester, c);
    final key = GlobalKey();
    await show(
      tester,
      c,
      const CountryPickerScreen(embeddedInShell: true),
      1,
      capture: key,
    );
    await screenshot(tester, key, 'servers', [
      'xplm_servers_earth.png',
      for (final code in ['de', 'fi', 'bg', 'fr', 'nl', 'us', 'gb', 'sg'])
        'xplm_flags/$code.png',
    ]);
    await tester.tap(find.text('Азия'));
    await tester.pumpAndSettle();
    expect(find.text('Сингапур'), findsOneWidget);
    expect(find.text('Германия'), findsNothing);
    await tester.tap(find.byTooltip('Поиск серверов'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Фин');
    await tester.pumpAndSettle();
    expect(find.text('Страна не найдена'), findsOneWidget);
    await tester.tap(find.text('Все страны'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Финляндия'));
    await tester.pumpAndSettle();
    expect(c.selectedLocation.id, 'fi');
    await tester.drag(
      find.byWidgetPredicate(
        (widget) =>
            widget is ListView && widget.scrollDirection == Axis.horizontal,
      ),
      const Offset(-450, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(c.strings.auto));
    await tester.pumpAndSettle();
    expect(c.selectedLocation.isAuto, isTrue);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('empty subscription has no demo servers and can open account', (
    tester,
  ) async {
    final c = _Fixture()
      ..empty = true
      ..subscriptionUrl = null
      ..linkState = SubscriptionLinkState.missing;
    cleanup(tester, c);
    await show(tester, c, const CountryPickerScreen(embeddedInShell: true), 1);
    expect(find.text('Германия'), findsNothing);
    await tester.tap(find.text('Добавить подписку'));
    await tester.pumpAndSettle();
    expect(find.text(c.strings.pasteLinkTitle), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('subscription: configured payment URL and refresh access', (
    tester,
  ) async {
    final c = _Fixture()..subscriptionUrl = null;
    cleanup(tester, c);
    final key = GlobalKey();
    await show(
      tester,
      c,
      const PaywallScreen(embeddedInShell: true),
      2,
      capture: key,
    );
    await screenshot(tester, key, 'subscription', [
      'xplm_gift.png',
      'xplm_subscription_earth.png',
    ]);
    await tester.ensureVisible(find.text('Оформить подписку ›'));
    await tester.tap(find.text('Оформить подписку ›'));
    await tester.pumpAndSettle();
    expect(launcher.urls, [AppBrand.current.payUrl]);
    c.subscriptionUrl = 'https://sub.x-plm.online/s/test';
    await show(tester, c, const PaywallScreen(embeddedInShell: true), 2);
    await tester.ensureVisible(find.text(c.strings.refreshAccess));
    await tester.pumpAndSettle();
    await tester.tap(find.text(c.strings.refreshAccess));
    await tester.pumpAndSettle();
    expect(c.refreshes, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'profile: actual notification preference, traffic, links, account and confirmed logout',
    (tester) async {
      final c = _Fixture();
      cleanup(tester, c);
      final key = GlobalKey();
      await show(
        tester,
        c,
        const AccountScreen(embeddedInShell: true),
        3,
        capture: key,
      );
      await screenshot(tester, key, 'profile', ['xplm_profile_logo.png']);
      await tester.tap(find.text('Уведомления'));
      await tester.pumpAndSettle();
      expect(c.appSettings.notificationsEnabled, isFalse);
      expect(find.text('Выкл.'), findsOneWidget);
      await tester.tap(find.text('Статистика трафика'));
      await tester.pumpAndSettle();
      expect(find.text('Загрузка: 2048 Б/с'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Поддержка'));
      await tester.pumpAndSettle();
      expect(
        launcher.urls,
        contains('mailto:${AppBrand.current.supportEmail}'),
      );
      await tester.tap(find.text('Присоединяйтесь\nк нашему Telegram-каналу'));
      await tester.pumpAndSettle();
      expect(launcher.urls, contains(AppBrand.current.channelUrl));
      await tester.ensureVisible(find.text('Аккаунт и подписки'));
      await tester.tap(find.text('Аккаунт и подписки'));
      await tester.pumpAndSettle();
      expect(find.text(c.strings.pasteLinkTitle), findsOneWidget);
      await tester.tap(find.byTooltip('Назад'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Выйти'));
      await tester.tap(find.text('Выйти'));
      await tester.pumpAndSettle();
      expect(c.removals, 0);
      await tester.tap(find.text(c.strings.cancel));
      await tester.pumpAndSettle();
      expect(c.removals, 0);
      await tester.tap(find.text('Выйти'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(c.strings.remove));
      await tester.pumpAndSettle();
      expect(c.removals, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('remaining screens adapt to narrow, large and desktop windows', (
    tester,
  ) async {
    final c = _Fixture();
    cleanup(tester, c);
    for (final size in [
      const Size(320, 568),
      const Size(440, 956),
      const Size(1024, 768),
    ]) {
      for (final entry in <(Widget, int)>[
        (const CountryPickerScreen(embeddedInShell: true), 1),
        (const PaywallScreen(embeddedInShell: true), 2),
        (const AccountScreen(embeddedInShell: true), 3),
      ]) {
        await show(tester, c, entry.$1, entry.$2, size: size, scale: 1.3);
      }
    }
    await tester.pumpWidget(const SizedBox());
  });
}
