import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_vpn/core/models/subscription.dart';
import 'package:pulse_vpn/core/services/settings_repository.dart';
import 'package:pulse_vpn/core/services/subscription_client.dart';
import 'package:pulse_vpn/core/services/subscription_link.dart';
import 'package:pulse_vpn/core/services/vpn_service.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';

const url = 'https://x-plm.online/sub/demo';
const good = FetchedSubscription(
  body:
      'vless://11111111-1111-1111-1111-111111111111@203.0.113.10:443?security=reality&sni=example.com&pbk=pk&sid=ab&type=tcp#Germany',
  userinfo: 'upload=0; download=0; total=0; expire=4102444800',
);

class Repo extends SettingsRepository {
  @override
  Future<void> saveAccount(UserAccount account) async {}
}

class Client extends SubscriptionClient {
  Future<FetchedSubscription> Function() next = () async => good;
  @override
  Future<FetchedSubscription> fetch(Uri uri) => next();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Client client;
  late VpnController controller;
  setUp(() {
    client = Client();
    controller = VpnController(
      service: MockVpnService(),
      repository: Repo(),
      subscriptions: client,
    )..subscriptionUrl = url;
  });
  tearDown(() => controller.dispose());
  test(
    'mobile network failure keeps saved identity and retry is not a paywall',
    () async {
      client.next = () async =>
          throw const SocketException('mobile network unavailable');
      await controller.reloadSubscription();
      expect(controller.subscriptionUrl, url);
      expect(controller.needsLink, isFalse);
      expect(controller.subscriptionLoadFailed, isTrue);
      expect(await controller.connect(), isTrue);
      expect(controller.errorMessage, isNotNull);
      client.next = () async => good;
      await controller.reloadSubscription();
      expect(controller.hasAccess, isTrue);
      expect(controller.subscriptionUrl, url);
    },
  );
  test(
    'a temporary invalid response preserves the valid loaded profile',
    () async {
      await controller.reloadSubscription();
      final profile = controller.profile;
      client.next = () async =>
          throw const FormatException('temporary portal response');
      await controller.reloadSubscription();
      expect(controller.profile, same(profile));
      expect(controller.hasAccess, isTrue);
      expect(controller.needsLink, isFalse);
    },
  );
  test(
    'an older failed refresh cannot overwrite a newer successful response',
    () async {
      final stale = Completer<FetchedSubscription>();
      client.next = () => stale.future;
      final first = controller.reloadSubscription();
      client.next = () async => good;
      await controller.reloadSubscription();
      stale.completeError(const SocketException('old network failed'));
      await first;
      expect(controller.hasAccess, isTrue);
    },
  );
  test('explicit server rejection still revokes access', () async {
    await controller.reloadSubscription();
    client.next = () async => throw const SubscriptionRejected();
    await controller.reloadSubscription();
    expect(controller.hasAccess, isFalse);
    expect(controller.linkState, SubscriptionLinkState.expired);
    expect(controller.subscriptionUrl, url);
  });
}
