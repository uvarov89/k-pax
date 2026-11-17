import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_vpn/app/brand/app_brand.dart';
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

  test('GitHub asset CDN is allowed only after trusted brand-specific release', () {
    const githubApk =
        'https://github.com/uvarov89/k-pax/releases/download/v1.0.65/K-Pax-1.0.65.apk';
    const cdn =
        'https://release-assets.githubusercontent.com/github-production-release-asset/1234/abcd?sp=r';

    expect(
      isTrustedAndroidApkRedirectChain(
        Uri.parse(githubApk),
        [Uri.parse(cdn)],
      ),
      isTrue,
    );
    expect(
      isTrustedAndroidApkRedirectChain(
        Uri.parse('https://k-pax.space/download/android'),
        [Uri.parse(githubApk), Uri.parse(cdn)],
      ),
      isTrue,
    );
    // CDN must not be accepted as a free-standing update URL.
    expect(isTrustedAndroidApkUrl(Uri.parse(cdn)), isFalse);
    expect(
      isTrustedAndroidApkRedirectChain(
        Uri.parse('https://k-pax.space/download/android'),
        [Uri.parse('https://evil.example/kpax.apk')],
      ),
      isFalse,
    );
    expect(
      isTrustedAndroidApkRedirectChain(
        Uri.parse(githubApk),
        [Uri.parse('http://release-assets.githubusercontent.com/github-production-release-asset/1/2')],
      ),
      isFalse,
    );
    expect(
      isTrustedAndroidApkRedirectChain(
        Uri.parse(githubApk),
        [Uri.parse('https://evil.example/github-production-release-asset/1/2')],
      ),
      isFalse,
    );
  });

  test('X-Plm accepts its CDN release and rejects K-Pax payloads', () {
    AppBrand.debugReset(AppBrand.xplm);
    addTearDown(() => AppBrand.debugReset(AppBrand.kpax));
    const cdn =
        'https://release-assets.githubusercontent.com/github-production-release-asset/7890/efgh';
    const xplmApk =
        'https://github.com/uvarov89/k-pax/releases/download/v1.0.65-xplm/X-Plm-1.0.65.apk';
    expect(
      isTrustedAndroidApkRedirectChain(
        Uri.parse('https://x-plm.online/download/android'),
        [Uri.parse(xplmApk), Uri.parse(cdn)],
      ),
      isTrue,
    );
    expect(
      isTrustedAndroidApkRedirectChain(
        Uri.parse('https://github.com/uvarov89/k-pax/releases/download/v1.0.65/K-Pax-1.0.65.apk'),
        [Uri.parse(cdn)],
      ),
      isFalse,
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
