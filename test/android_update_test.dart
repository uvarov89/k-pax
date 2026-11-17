import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_vpn/core/services/android_update.dart';

void main() {
  test('offers only a newer trusted apk', () {
    const current = '1.0.21';
    final newer = interpretAndroidUpdate(
      '{"version":"1.0.22","url":"https://github.com/uvarov89/k-pax/releases/download/v1.0.22/K-Pax-1.0.22-preview.apk"}',
      current,
    );
    expect(newer.status, AndroidUpdateStatus.newer);
    expect(newer.release?.version, '1.0.22');

    expect(
      interpretAndroidUpdate(
        '{"version":"1.0.21","url":"https://github.com/uvarov89/k-pax/releases/download/v1.0.21/K-Pax-1.0.21-preview.apk"}',
        current,
      ).status,
      AndroidUpdateStatus.current,
    );
    expect(
      interpretAndroidUpdate(
        '{"version":"1.0.22","url":"https://example.com/K-Pax.apk"}',
        current,
      ).status,
      AndroidUpdateStatus.unavailable,
    );
    expect(
      interpretAndroidUpdate(
        '{"version":"1.0.22","url":"https://github.com/uvarov89/k-pax/releases/download/v1.0.22/K-Pax-Setup.exe"}',
        current,
      ).status,
      AndroidUpdateStatus.unavailable,
    );
  });

  test('brand host allows only the download redirect path', () {
    expect(
      isTrustedAndroidApkUrl(Uri.parse('https://k-pax.space/download/android')),
      isTrue,
    );
    expect(
      isTrustedAndroidApkUrl(Uri.parse('https://k-pax.space/evil.apk')),
      isFalse,
    );
    expect(
      isTrustedAndroidApkBinaryUrl(
        Uri.parse(
          'https://github.com/uvarov89/k-pax/releases/download/v1.0.22/K-Pax-1.0.22.apk',
        ),
      ),
      isTrue,
    );
    expect(
      isTrustedAndroidApkBinaryUrl(Uri.parse('https://evil.example/K-Pax.apk')),
      isFalse,
    );
  });
}
