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
import 'package:pulse_vpn/core/services/settings_repository.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';
import 'package:pulse_vpn/features/account/account_screen.dart';
import 'package:pulse_vpn/features/locations/country_picker_screen.dart';
import 'package:pulse_vpn/features/paywall/paywall_screen.dart';
import 'package:pulse_vpn/features/shell/xplm_shell.dart';
import 'package:pulse_vpn/features/xplm/widgets/xplm_html_widgets.dart';
import 'package:pulse_vpn/features/xplm/widgets/xplm_codex_widgets.dart';
import 'package:pulse_vpn/core/models/tunnel_node.dart';

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
  bool unmeasured = false;
  int refreshes = 0;
  int removals = 0;
  @override
  List<ServerLocation> get locations => [
    ServerLocation.auto,
    if (!empty)
      ..._countries.map(
        (l) => unmeasured
            ? ServerLocation(
                id: l.id,
                countryCode: l.countryCode,
                nameRu: l.nameRu,
              )
            : l,
      ),
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
    await AppBrand.init();
    expect(AppBrand.current.isXplm, isTrue);
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
    // Home/server art uses repeating controllers; settle would hang.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
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

  testWidgets(
    'shell keeps tab history, visible navigation and predictable back',
    (tester) async {
      final c = _Fixture();
      c.subscriptionUrl = 'https://sub.x-plm.online/s/test-token-1234567890';
      cleanup(tester, c);
      final capture = GlobalKey();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      await SettingsRepository().markOnboardingSeen();
      await tester.pumpWidget(
        ChangeNotifierProvider<VpnController>.value(
          value: c,
          child: MaterialApp(
            theme: NordSignalTheme.xplmLight,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: RepaintBoundary(key: capture, child: child!),
            ),
            home: const XplmShell(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      Finder tab(String name) => find.descendant(
        of: find.byType(XplmBottomNav),
        matching: find.text(name),
      );
      await tester.tap(tab('Профиль'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Уведомления'), findsOneWidget);
      await screenshot(tester, capture, 'profile-navigation', [
        'xplm_profile_logo.png',
      ]);
      await tester.tap(find.byTooltip('Настройки приложения'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Подсказки в приложении'), findsOneWidget);
      await screenshot(tester, capture, 'settings-navigation', []);
      await tester.ensureVisible(find.text('VPN и защита'));
      await tester.tap(find.text('VPN и защита'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('security-protocol')), findsOneWidget);
      await tester.tap(tab('Серверы'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.widget<XplmBottomNav>(find.byType(XplmBottomNav)).index, 1);
      await tester.tap(tab('Подписка'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.widget<XplmBottomNav>(find.byType(XplmBottomNav)).index, 2);
      await tester.tap(tab('Главная'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.widget<XplmBottomNav>(find.byType(XplmBottomNav)).index, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Сингапур'), findsOneWidget);
    expect(find.text('Германия'), findsNothing);
    await tester.tap(find.byTooltip('Поиск серверов'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.enterText(find.byType(TextField), 'Фин');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Страна не найдена'), findsOneWidget);
    await tester.tap(find.text('Все страны'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Финляндия'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(c.selectedLocation.id, 'fi');
    // Clear search so the pinned Auto row is visible again.
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.ensureVisible(find.byKey(const ValueKey('server-auto')));
    await tester.tap(find.byKey(const ValueKey('server-auto')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(c.selectedLocation.isAuto, isTrue);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('unknown ping retains bars without invented measurements', (
    tester,
  ) async {
    final c = _Fixture()..unmeasured = true;
    cleanup(tester, c);
    await show(tester, c, const CountryPickerScreen(embeddedInShell: true), 1);
    expect(find.byType(XplmSignalBars), findsNWidgets(8));
    expect(
      tester
          .widgetList<XplmSignalBars>(find.byType(XplmSignalBars))
          .every((bars) => bars.latencyMs == -1),
      isTrue,
    );
    expect(find.text('28 ms'), findsNothing);
    expect(find.text('Пинг: —'), findsNWidgets(8));
    await tester.pumpWidget(const SizedBox());
  });
  test(
    'locations expose existing probe results without changing the VPN service',
    () {
      final c = VpnController(service: MockVpnService());
      addTearDown(c.dispose);
      c.profile = const SubscriptionProfile(
        nodes: [
          TunnelNode(
            countryId: 'de',
            countryCode: 'DE',
            countryName: 'Германия',
            kind: TunnelKind.reality,
            host: 'example.invalid',
            port: 443,
            outbound: {},
          ),
        ],
      );
      expect(c.locations.last.latencyMs, -1);
      c.lastProbeResults = {'Германия': 42};
      expect(c.locations.last.latencyMs, 42);
      c.lastProbeResults = {'Германия': -1};
      expect(c.locations.last.latencyMs, -1);
    },
  );
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(launcher.urls, [AppBrand.current.payUrl]);
    c.subscriptionUrl = 'https://sub.x-plm.online/s/test';
    await show(tester, c, const PaywallScreen(embeddedInShell: true), 2);
    await tester.ensureVisible(find.text(c.strings.refreshAccess));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text(c.strings.refreshAccess));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(c.refreshes, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'profile: clear account and settings entries, traffic, support and confirmed account logout',
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
      expect(find.text('Уведомления'), findsOneWidget);
      expect(find.text('Безопасность'), findsOneWidget);
      expect(find.text('Выйти'), findsOneWidget);
      await tester.tap(find.text('Уведомления'));
      await tester.pumpAndSettle();
      expect(c.appSettings.notificationsEnabled, isFalse);
      await tester.tap(find.text('Уведомления'));
      await tester.pumpAndSettle();
      expect(c.appSettings.notificationsEnabled, isTrue);
      await tester.tap(find.text('Статистика трафика'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Загрузка: 2048 Б/с'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Поддержка'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        launcher.urls,
        contains('mailto:${AppBrand.current.supportEmail}'),
      );
      await tester.tap(find.text('Присоединяйтесь\nк нашему Telegram-каналу'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(launcher.urls, contains(AppBrand.current.channelUrl));
      final accountButton = find.ancestor(
        of: find.text('Аккаунт и подписки'),
        matching: find.byType(TextButton),
      );
      await tester.ensureVisible(accountButton);
      await tester.pumpAndSettle();
      await tester.tap(accountButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.ensureVisible(find.text('Добавить другую подписку'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Добавить другую подписку'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text(c.strings.pasteLinkTitle), findsOneWidget);
      await tester.ensureVisible(find.text('Выйти из аккаунта'));
      await tester.tap(find.text('Выйти из аккаунта'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(c.removals, 0);
      await tester.tap(find.text(c.strings.cancel));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(c.removals, 0);
      await tester.tap(find.text('Выйти из аккаунта'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Выйти'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
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
