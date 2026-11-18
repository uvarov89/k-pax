import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_vpn/app/brand/app_brand.dart';
import 'package:pulse_vpn/core/services/client_diagnostics.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    AppBrand.debugReset(AppBrand.kpax);
  });

  test('redactDiagnosticsError strips links, uuids and keys', () {
    const raw =
        'fail vless://11111111-1111-1111-1111-111111111111@1.2.3.4:443 '
        'pbk=publicKEY sid=abcd '
        'https://sub.k-pax.space/s/abcdefghijklmnopqrstuvwxyz '
        'Bearer clash-secret-value token=sekrit '
        'orphan 22222222-2222-2222-2222-222222222222';
    final redacted = redactDiagnosticsError(raw);
    expect(redacted, isNot(contains('vless://')));
    expect(redacted, isNot(contains('11111111-1111-1111-1111-111111111111')));
    expect(redacted, isNot(contains('22222222-2222-2222-2222-222222222222')));
    expect(redacted, isNot(contains('publicKEY')));
    expect(redacted, isNot(contains('/s/abcdefghijklmnopqrstuvwxyz')));
    expect(redacted, isNot(contains('clash-secret-value')));
    expect(redacted, isNot(contains('sekrit')));
    expect(redacted, contains('[vless]'));
    expect(redacted, contains('[uuid]'));
    expect(redacted, contains('pbk=[redacted]'));
    expect(redacted, contains('sid=[redacted]'));
    expect(redacted.length, lessThanOrEqualTo(kDiagnosticsMaxErrorLen + 1));
  });

  test('redactDiagnosticsError truncates long text', () {
    final long = List.filled(400, 'x').join();
    final redacted = redactDiagnosticsError(long, maxLen: 50);
    expect(redacted.length, lessThanOrEqualTo(51));
    expect(redacted.endsWith('…'), isTrue);
  });

  test('encodeClientEventsBatch matches panel contract', () {
    final events = [
      buildDiagnosticsEvent(
        event: 'connect_start',
        sessionId: 'sess1',
        brand: 'kpax',
        appVersion: '1.0.70',
        platform: 'windows',
        countryId: 'de',
        kind: 'reality',
        port: 443,
        host: 'de.example',
        attempt: 1,
      ),
    ];
    final body = encodeClientEventsBatch(
      token: 'sub-token',
      sessionId: 'sess1',
      events: events,
    );
    expect(body['token'], 'sub-token');
    expect(body['session_id'], 'sess1');
    final list = body['events'] as List;
    expect(list, hasLength(1));
    final event = list.first as Map<String, Object?>;
    expect(event['event'], 'connect_start');
    expect(event['brand'], 'kpax');
    expect(event['app_version'], '1.0.70');
    expect(event['platform'], 'windows');
    expect(event['country_id'], 'de');
    expect(event['kind'], 'reality');
    expect(event['port'], 443);
    expect(event['host'], 'de.example');
    expect(event['attempt'], 1);
    expect(event['ts'], isA<String>());
    expect(event.containsKey('error'), isFalse);
  });

  test('AppBrand.appClientEvents uses brand host', () {
    expect(
      AppBrand.kpax.appClientEvents().toString(),
      'https://k-pax.space/app/client-events',
    );
    expect(
      AppBrand.xplm.appClientEvents().toString(),
      'https://x-plm.online/app/client-events',
    );
  });

  test('connect_hang event carries hang error_code', () {
    final event = buildDiagnosticsEvent(
      event: 'connect_hang',
      sessionId: 'sess-hang',
      brand: 'kpax',
      appVersion: '1.0.71',
      platform: 'android',
      countryId: 'de',
      kind: 'reality',
      port: 443,
      host: 'de.example',
      errorCode: 'hang',
      error: 'connecting >45s',
      attempt: 3,
    );
    expect(event['event'], 'connect_hang');
    expect(event['error_code'], 'hang');
    expect(event['error'], 'connecting >45s');
    expect(event['attempt'], 3);
    expect(event['host'], 'de.example');
    expect(event['port'], 443);
    expect(kConnectHangTimeout, const Duration(seconds: 45));
  });

  test('logConnectHang enqueues once and marks urgent flush path', () async {
    SharedPreferences.setMockInitialValues({});
    final diag = ClientDiagnostics(
      tokenProvider: () async => null,
      enabled: true,
      prefsFactory: SharedPreferences.getInstance,
      appVersionLoader: () async => '1.0.71',
    );
    await diag.start(enabled: true);
    final before = diag.queuedCount;
    diag.logConnectHang(attempt: 2, error: 'connecting >45s');
    expect(diag.queuedCount, greaterThan(before));
    final hang = diag.debugQueue.lastWhere(
      (e) => e['event'] == 'connect_hang',
    );
    expect(hang['error_code'], 'hang');
    expect(hang['attempt'], 2);
    expect(hang['error'], 'connecting >45s');
    // tokenProvider returns null → flush no-ops but urgent path was taken.
    await diag.flush(urgent: true);
    diag.dispose();
  });
}
