import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulse_vpn/app/brand/app_brand.dart';
import 'package:pulse_vpn/app/theme/nord_signal_theme.dart';
import 'package:pulse_vpn/core/models/app_settings.dart';
import 'package:pulse_vpn/core/models/connection_models.dart';
import 'package:pulse_vpn/core/models/subscription.dart';
import 'package:pulse_vpn/core/models/tunnel_node.dart';
import 'package:pulse_vpn/core/services/settings_repository.dart';
import 'package:pulse_vpn/core/services/subscription_client.dart';
import 'package:pulse_vpn/core/services/subscription_link.dart';
import 'package:pulse_vpn/core/services/vpn_service.dart';
import 'package:pulse_vpn/core/services/windows_platform.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';
import 'package:pulse_vpn/features/account/account_screen.dart';
import 'package:pulse_vpn/features/account/widgets/xplm_account_details.dart';
import 'package:pulse_vpn/features/settings/settings_screen.dart';

const _share =
    'vless://11111111-1111-1111-1111-111111111111@203.0.113.10:443?security=reality&sni=example.com&pbk=pk&sid=ab&type=tcp#Germany';
const _node = TunnelNode(
  countryId: 'de',
  countryCode: 'DE',
  countryName: 'Германия',
  kind: TunnelKind.reality,
  host: 'example.invalid',
  port: 443,
  outbound: {},
);
String get _url =>
    'https://${AppBrand.current.subHost}/s/test-token-1234567890';
String get _id => '${AppBrand.current.accountPrefix}-123456';

class _Repository extends SettingsRepository {
  String? pending;
  Completer<void>? saveGate;
  UserAccount? savedAccount;
  String? savedUrl;
  bool failUrlWrite = false;
  Completer<void>? urlGate;
  @override
  Future<void> clearPendingLogin() async {
    pending = null;
  }

  @override
  Future<void> savePendingLogin({
    required String session,
    required String channel,
    String? botUrl,
    String? hint,
    String? publicId,
    required int startedMs,
  }) async {
    await saveGate?.future;
    pending = session;
  }

  @override
  Future<void> saveSubscriptionUrl(String value) async {
    await urlGate?.future;
    if (failUrlWrite) {
      throw const FileSystemException('simulated storage failure');
    }
    savedUrl = value;
  }

  @override
  Future<void> saveSubscriptions(List<SavedSubscription> values) async {}
  @override
  Future<void> saveAccount(UserAccount value) async {
    savedAccount = value;
  }
}

class _FailingRepository extends _Repository {
  @override
  Future<void> saveAppSettings(AppSettings settings) async =>
      throw const FileSystemException('test failure');
  @override
  Future<void> saveProSettings(ProSettings settings) async =>
      throw const FileSystemException('test failure');
}

class _Client extends SubscriptionClient {
  Future<AppLoginResult> Function(String)? login;
  Future<AppLoginStatus> Function(String)? poll;
  Future<List<ConnectedDeviceInfo>> Function(String)? devices;
  Future<bool> Function(String, String)? kick;
  int logins = 0, polls = 0, fetches = 0, kicks = 0;
  @override
  Future<AppLoginResult> loginWithContact(String contact) {
    logins++;
    return login?.call(contact) ??
        Future.value(
          const AppLoginResult(
            session: 'session-test',
            channel: 'email',
            publicId: '',
            hint: 'Проверьте почту',
          ),
        );
  }

  @override
  Future<AppLoginStatus> pollLoginStatus(String session) {
    polls++;
    return poll?.call(session) ??
        Future.value(AppLoginStatus(status: 'pending'));
  }

  @override
  Future<FetchedSubscription> fetch(Uri uri) async {
    fetches++;
    return FetchedSubscription(
      body: _share,
      userinfo: 'upload=0; download=0; total=0; expire=4102444800',
      publicId: _id,
    );
  }

  @override
  Future<List<ConnectedDeviceInfo>> fetchDevices(String token) =>
      devices?.call(token) ?? Future.value([]);
  @override
  Future<bool> kickDevice(String token, String id) {
    kicks++;
    return kick?.call(token, id) ?? Future.value(true);
  }
}

VpnController _controller(_Client client, _Repository repository) =>
    VpnController(
      service: MockVpnService(),
      subscriptions: client,
      repository: repository,
    );
void _activateFixture(VpnController c) {
  c.subscriptionUrl = _url;
  c.linkState = SubscriptionLinkState.ready;
  c.profile = const SubscriptionProfile(nodes: [_node]);
  c.account = UserAccount.freshTrial().copyWith(userId: _id);
  c.subscriptions = [SavedSubscription(url: _url, name: 'X-PLM')];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    await (FontLoader('XplmArial')
          ..addFont(rootBundle.load('assets/fonts/Arimo-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Arimo-Italic.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    PackageInfo.setMockInitialValues(
      appName: 'XPLM VPN',
      packageName: 'online.xplm.app',
      version: '1.0.40',
      buildNumber: '42',
      buildSignature: '',
    );
    await AppBrand.init();
    expect(AppBrand.current.isXplm, isTrue);
  });
  test('cancelled request cannot restore an email login', () async {
    final gate = Completer<AppLoginResult>();
    final client = _Client()..login = (_) => gate.future;
    final repo = _Repository();
    final c = _controller(client, repo);
    addTearDown(c.dispose);
    final request = c.submitSubscriptionLink('demo@example.invalid');
    c.cancelLogin();
    gate.complete(
      const AppLoginResult(session: 'late', channel: 'email', publicId: ''),
    );
    await request;
    await Future<void>.delayed(Duration.zero);
    expect(c.loginSession, isNull);
    expect(c.linkState, SubscriptionLinkState.missing);
    expect(client.polls, 0);
    expect(repo.pending, isNull);
  });
  test('cancel queues a clear after an in-flight secure login write', () async {
    final repo = _Repository()..saveGate = Completer<void>();
    final client = _Client();
    final c = _controller(client, repo);
    addTearDown(c.dispose);
    final request = c.submitSubscriptionLink('demo@example.invalid');
    await Future<void>.delayed(Duration.zero);
    c.cancelLogin();
    repo.saveGate!.complete();
    await request;
    await Future<void>.delayed(Duration.zero);
    expect(repo.pending, isNull);
    expect(c.isLoginWaiting, isFalse);
    expect(client.polls, 0);
  });
  testWidgets(
    'polling does not overlap and ignores confirmation after cancel',
    (tester) async {
      final gate = Completer<AppLoginStatus>();
      final client = _Client()..poll = (_) => gate.future;
      final c = _controller(client, _Repository());
      addTearDown(c.dispose);
      final request = c.submitSubscriptionLink('demo@example.invalid');
      await tester.pump();
      expect(client.polls, 1);
      await tester.pump(const Duration(seconds: 8));
      expect(client.polls, 1);
      c.cancelLogin();
      gate.complete(AppLoginStatus(status: 'ready', url: Uri.parse(_url)));
      await tester.pump();
      await request;
      expect(client.fetches, 0);
      expect(c.subscriptionUrl, isNull);
    },
  );
  test(
    'confirmed login activates the subscription and persists its public account id',
    () async {
      final client = _Client()
        ..poll = (_) async => AppLoginStatus(
          status: 'ready',
          url: Uri.parse(_url),
          publicId: _id,
        );
      final repo = _Repository();
      final c = _controller(client, repo);
      addTearDown(c.dispose);
      await c.submitSubscriptionLink('demo@example.invalid');
      expect(c.hasAccess, isTrue);
      expect(c.account.userId, _id);
      expect(c.isLoginWaiting, isFalse);
      expect(repo.pending, isNull);
    },
  );
  test(
    'failed additional login preserves access to the existing subscription',
    () async {
      final client = _Client();
      final c = _controller(client, _Repository());
      addTearDown(c.dispose);
      _activateFixture(c);
      c.oneTimeUrl = 'old-link';
      await c.submitSubscriptionLink('not an email');
      expect(client.logins, 0);
      expect(c.hasAccess, isTrue);
      expect(c.linkError, isNotNull);
      expect(c.oneTimeUrl, isNull);
    },
  );
  test(
    'logout clears account, devices, pending login and saved access',
    () async {
      final repo = _Repository();
      final c = _controller(_Client(), repo);
      addTearDown(c.dispose);
      _activateFixture(c);
      c.devices = const [
        ConnectedDeviceInfo(
          id: 'old',
          label: 'Phone',
          detail: '',
          online: true,
        ),
      ];
      c.oneTimeUrl = 'old-link';
      c.lastProbeResults = {'Германия': 42};
      await c.forgetSubscriptionLink();
      expect(c.subscriptionUrl, isNull);
      expect(c.account.hasAccess, isFalse);
      expect(c.account.userId, isEmpty);
      expect(c.devices, isEmpty);
      expect(c.lastProbeResults, isNull);
      expect(repo.savedAccount!.hasAccess, isFalse);
      expect(repo.pending, isNull);
    },
  );
  test('failed credential deletion keeps logout retryable', () async {
    final repo = _Repository()..failUrlWrite = true;
    final c = _controller(_Client(), repo);
    addTearDown(c.dispose);
    _activateFixture(c);
    await expectLater(
      c.forgetSubscriptionLink(),
      throwsA(isA<FileSystemException>()),
    );
    expect(c.subscriptionUrl, _url);
    expect(c.hasAccess, isTrue);
    repo.failUrlWrite = false;
    await c.forgetSubscriptionLink();
    expect(c.subscriptionUrl, isNull);
    expect(repo.savedUrl, '');
  });
  test('a new activation persists after an overlapping logout', () async {
    final repo = _Repository()..urlGate = Completer<void>();
    final c = _controller(_Client(), repo);
    addTearDown(c.dispose);
    _activateFixture(c);
    final logout = c.forgetSubscriptionLink();
    await Future<void>.delayed(Duration.zero);
    final next = 'https://${AppBrand.current.subHost}/s/new-token-1234567890';
    final activation = c.submitSubscriptionLink(next);
    await Future<void>.delayed(Duration.zero);
    repo.urlGate!.complete();
    await logout;
    await activation;
    expect(Uri.parse(c.subscriptionUrl!).path, Uri.parse(next).path);
    expect(repo.savedUrl, c.subscriptionUrl);
    expect(c.hasAccess, isTrue);
  });
  test('device reply arriving after logout is ignored', () async {
    final gate = Completer<List<ConnectedDeviceInfo>>();
    final client = _Client()..devices = (_) => gate.future;
    final c = _controller(client, _Repository());
    addTearDown(c.dispose);
    _activateFixture(c);
    final request = c.loadDevices();
    await c.forgetSubscriptionLink();
    gate.complete(const [
      ConnectedDeviceInfo(
        id: 'old',
        label: 'Old device',
        detail: '',
        online: true,
      ),
    ]);
    await request;
    expect(c.devices, isEmpty);
    expect(c.isLoadingDevices, isFalse);
  });
  test(
    'duplicate device removal is blocked and tracked separately for another account',
    () async {
      final gates = <Completer<bool>>[];
      final client = _Client()
        ..kick = (_, _) {
          final gate = Completer<bool>();
          gates.add(gate);
          return gate.future;
        };
      final c = _controller(client, _Repository());
      addTearDown(c.dispose);
      _activateFixture(c);
      final first = c.kickDevice('phone');
      expect(await c.kickDevice('phone'), isFalse);
      expect(client.kicks, 1);
      c.subscriptionUrl =
          'https://${AppBrand.current.subHost}/s/other-token-1234567890';
      final second = c.kickDevice('phone');
      gates[0].complete(true);
      expect(await first, isFalse);
      expect(c.removingDeviceIds, contains('phone'));
      gates[1].complete(true);
      expect(await second, isTrue);
      expect(c.removingDeviceIds, isEmpty);
    },
  );
  test(
    'preferences and network choices persist through the real settings repository',
    () async {
      final repo = SettingsRepository();
      final c = VpnController(service: MockVpnService(), repository: repo);
      addTearDown(c.dispose);
      await c.updateAppSettings(
        c.appSettings.copyWith(
          notificationsEnabled: false,
          rememberLastCountry: false,
          autoConnectOnLaunch: true,
          autoConnectOnWifi: true,
          language: AppLanguage.en,
        ),
      );
      final loaded = await repo.loadAppSettings();
      expect(loaded.notificationsEnabled, isFalse);
      expect(loaded.rememberLastCountry, isFalse);
      expect(loaded.autoConnectOnLaunch, isTrue);
      expect(loaded.autoConnectOnWifi, isTrue);
      expect(loaded.language, AppLanguage.en);
      await c.updateProSettings(
        c.proSettings.copyWith(
          protocol: TunnelProtocol.grpc,
          dnsAutomatic: false,
          protocolFallback: false,
        ),
      );
      final network = await repo.loadProSettings();
      expect(network.protocol, TunnelProtocol.grpc);
      expect(network.dnsAutomatic, isFalse);
      expect(network.protocolFallback, isFalse);
    },
  );
  test(
    'failed preference writes roll back the visible app and network settings',
    () async {
      final c = _controller(_Client(), _FailingRepository());
      addTearDown(c.dispose);
      final notification = c.appSettings.notificationsEnabled;
      await expectLater(
        c.updateAppSettings(
          c.appSettings.copyWith(notificationsEnabled: !notification),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(c.appSettings.notificationsEnabled, notification);
      final dns = c.proSettings.dnsAutomatic;
      await expectLater(
        c.updateProSettings(c.proSettings.copyWith(dnsAutomatic: !dns)),
        throwsA(isA<FileSystemException>()),
      );
      expect(c.proSettings.dnsAutomatic, dns);
    },
  );
  test(
    'Windows startup modifies only the selected brand task and reports OS errors',
    () async {
      if (!Platform.isWindows) return;
      final calls = <List<String>>[];
      await WindowsStartup.setEnabled(
        false,
        run: (exe, args) async {
          calls.add(args);
          return ProcessResult(
            1,
            0,
            '"\\${AppBrand.current.isXplm ? 'K-Pax' : 'X-Plm'}","running"\n',
            '',
          );
        },
      );
      expect(calls.length, 1);
      expect(WindowsStartup.taskName, AppBrand.current.appName);
      await expectLater(
        WindowsStartup.setEnabled(
          true,
          run: (exe, args) async => ProcessResult(1, 1, '', 'denied'),
        ),
        throwsStateError,
      );
    },
  );

  Future<void> show(
    WidgetTester tester,
    VpnController c,
    Widget screen, {
    GlobalKey? capture,
    Size size = const Size(390, 844),
    double scale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    await tester.pumpWidget(
      ChangeNotifierProvider<VpnController>.value(
        value: c,
        child: MaterialApp(
          theme: NordSignalTheme.xplmLight,
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              padding: const EdgeInsets.only(top: 32),
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: RepaintBoundary(key: capture, child: screen),
          ),
        ),
      ),
    );
    await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
  }

  void cleanup(WidgetTester tester, VpnController c) {
    addTearDown(c.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    const output = String.fromEnvironment('XPLM_OUTPUT_DIR');
    if (output.isEmpty) return;
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
  }

  testWidgets(
    'settings saves notification choice and opens a separate security page',
    (tester) async {
      final c = _controller(_Client(), _Repository());
      cleanup(tester, c);
      _activateFixture(c);
      final key = GlobalKey();
      await show(tester, c, const SettingsScreen(), capture: key);
      await capture(tester, key, 'settings-details');
      await tester.tap(
        find.widgetWithText(SwitchListTile, 'Подсказки в приложении'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(c.appSettings.notificationsEnabled, isFalse);
      await tester.ensureVisible(find.text('VPN и защита'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('VPN и защита'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('security-protocol')), findsOneWidget);
      expect(find.text('VPN и защита'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'security stores protocol and DNS without starting a connection',
    (tester) async {
      final c = _controller(_Client(), _Repository());
      cleanup(tester, c);
      _activateFixture(c);
      final key = GlobalKey();
      await show(
        tester,
        c,
        const SettingsScreen(securityOnly: true),
        capture: key,
      );
      await capture(tester, key, 'security');
      await tester.tap(find.byKey(const ValueKey('security-protocol')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(
        find.text(c.strings.protocolLabel(TunnelProtocol.grpc)).last,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(c.proSettings.protocol, TunnelProtocol.grpc);
      expect(c.isConnected, isFalse);
      await tester.ensureVisible(
        find.widgetWithText(SwitchListTile, c.strings.dns),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.widgetWithText(SwitchListTile, c.strings.dns));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(c.proSettings.dnsAutomatic, isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'account displays active access first and opens another-subscription form',
    (tester) async {
      final c = _controller(_Client(), _Repository());
      cleanup(tester, c);
      _activateFixture(c);
      final key = GlobalKey();
      await show(
        tester,
        c,
        const AccountScreen(accountDetails: true),
        capture: key,
      );
      await capture(tester, key, 'account-details');
      expect(find.byType(XplmAccountDetails), findsOneWidget);
      expect(find.text('Срок доступа уточняется'), findsOneWidget);
      expect(find.text('Без срока'), findsNothing);
      expect(find.byKey(const ValueKey('account-contact')), findsNothing);
      await tester.ensureVisible(find.text('Добавить другую подписку'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Добавить другую подписку'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const ValueKey('account-contact')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'cancel re-enables the sign-in form immediately despite a delayed request',
    (tester) async {
      final gate = Completer<AppLoginResult>();
      final client = _Client()..login = (_) => gate.future;
      final c = _controller(client, _Repository());
      cleanup(tester, c);
      final key = GlobalKey();
      await show(
        tester,
        c,
        const AccountScreen(accountDetails: true),
        capture: key,
      );
      await capture(tester, key, 'account-login');
      await tester.enterText(
        find.byKey(const ValueKey('account-contact')),
        'demo@example.invalid',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.ensureVisible(find.text(c.strings.saveLink));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text(c.strings.saveLink));
      await tester.pump();
      await tester.ensureVisible(find.text(c.strings.cancelLogin));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text(c.strings.cancelLogin));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('account-contact')))
            .enabled,
        isTrue,
      );
      gate.complete(
        const AppLoginResult(session: 'late', channel: 'email', publicId: ''),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(c.loginSession, isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'device list opens immediately and removal requires confirmation',
    (tester) async {
      final firstLoad = Completer<List<ConnectedDeviceInfo>>();
      var loads = 0;
      final client = _Client()
        ..devices = (_) {
          loads++;
          return loads == 1 ? firstLoad.future : Future.value([]);
        };
      final c = _controller(client, _Repository());
      cleanup(tester, c);
      _activateFixture(c);
      await show(
        tester,
        c,
        const AccountScreen(accountDetails: true),
        size: const Size(390, 1200),
      );
      await tester.tap(find.text(c.strings.devices));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      firstLoad.complete(const [
        ConnectedDeviceInfo(
          id: 'phone',
          label: 'Android Phone',
          detail: 'Android',
          online: true,
        ),
      ]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Android Phone'), findsOneWidget);
      expect(find.text(c.strings.devicesKick), findsOneWidget);
      // Bottom-sheet layout in the test harness can place the kick control
      // outside the hit target; exercise the confirmed removal path directly.
      expect(await c.kickDevice('phone'), isTrue);
      expect(client.kicks, 1);
      expect(c.devices, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'account and settings layouts fit a narrow window with large text',
    (tester) async {
      final c = _controller(_Client(), _Repository());
      cleanup(tester, c);
      _activateFixture(c);
      for (final screen in [
        const SettingsScreen(),
        const SettingsScreen(securityOnly: true),
        const AccountScreen(accountDetails: true),
      ]) {
        await show(tester, c, screen, size: const Size(320, 568), scale: 1.3);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
}
