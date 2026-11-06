import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulse_vpn/core/models/app_settings.dart';
import 'package:pulse_vpn/core/services/ios_singbox_vpn_service.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('sing_box');
  final calls = <MethodCall>[];
  var rejectSettings = false;
  setUp(() {
    calls.clear();
    rejectSettings = false;
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'initialize') return true;
          if (call.method == 'configureOnDemand' && rejectSettings) {
            rejectSettings = false;
            throw PlatformException(code: 'SAVE_FAILED');
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test(
    'all network selections reach native profile, including disabling',
    () async {
      final service = IosSingboxVpnService();
      for (final wifi in [false, true]) {
        for (final mobile in [false, true]) {
          await service.applyAppSettings(
            AppSettings(autoConnectOnWifi: wifi, autoConnectOnMobile: mobile),
          );
          expect(calls.last.method, 'configureOnDemand');
          expect(calls.last.arguments, {'wifi': wifi, 'cellular': mobile});
        }
      }
      expect(calls.any((c) => c.method == 'connect'), isFalse);
    },
  );
  test('clearing access revokes the persisted native configuration', () async {
    await IosSingboxVpnService().clearSavedAccess();
    expect(calls.last.method, 'clearSavedAccess');
    expect(calls.any((c) => c.method == 'connect'), isFalse);
  });
  test(
    'native save failure restores the prior UI and native settings',
    () async {
      final controller = VpnController(service: IosSingboxVpnService());
      addTearDown(controller.dispose);
      final previous = controller.appSettings;
      rejectSettings = true;
      await expectLater(
        controller.updateAppSettings(
          previous.copyWith(autoConnectOnWifi: true),
        ),
        throwsA(isA<PlatformException>()),
      );
      expect(
        controller.appSettings.autoConnectOnWifi,
        previous.autoConnectOnWifi,
      );
      expect(calls.last.arguments, {
        'wifi': previous.autoConnectOnWifi,
        'cellular': previous.autoConnectOnMobile,
      });
    },
  );
}
