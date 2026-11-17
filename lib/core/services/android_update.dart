import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:pulse_vpn/app/brand/app_brand.dart';
import 'package:pulse_vpn/core/services/windows_update.dart';

class AndroidRelease {
  const AndroidRelease({required this.version, required this.url});

  final String version;
  final Uri url;
}

bool _isTrustedGithubAndroidApk(Uri uri, AppBrand brand) {
  final lower = uri.path.toLowerCase();
  if (!lower.endsWith('.apk')) return false;
  if (uri.host != 'github.com') return false;
  if (!uri.path.startsWith('/uvarov89/k-pax/releases/download/')) {
    return false;
  }
  final name = uri.pathSegments.isEmpty
      ? ''
      : uri.pathSegments.last.toLowerCase();
  if (brand.isXplm) {
    return name.startsWith('x-plm-') || name.startsWith('xplm-');
  }
  return name.startsWith('k-pax-');
}

/// Manifest / JSON `url` — brand redirect endpoint or a direct GitHub APK.
bool isTrustedAndroidApkUrl(Uri uri) {
  if (uri.scheme != 'https' || uri.path.contains('..')) return false;
  final brand = AppBrand.current;
  // Exact redirect path only — never "any *.apk on brand host".
  if (uri.host == brand.host) {
    return uri.path == '/download/android';
  }
  return _isTrustedGithubAndroidApk(uri, brand);
}

/// Final binary after redirects — brand redirect target or GitHub APK only.
bool isTrustedAndroidApkBinaryUrl(Uri uri) {
  if (uri.scheme != 'https' || uri.path.contains('..')) return false;
  final brand = AppBrand.current;
  if (uri.host == brand.host) {
    return uri.path == '/download/android';
  }
  return _isTrustedGithubAndroidApk(uri, brand);
}

/// GitHub sends valid release APK downloads through its signed asset CDN.
/// Reject the CDN as an *initial* update URL, but permit it after a
/// brand-specific, trusted GitHub release URL in the redirect chain.
bool isTrustedAndroidApkRedirectChain(
  Uri requested,
  Iterable<Uri> locations,
) {
  if (!isTrustedAndroidApkUrl(requested)) return false;
  final brand = AppBrand.current;
  var previous = requested;
  var githubReleaseSeen = _isTrustedGithubAndroidApk(requested, brand);

  for (final location in locations) {
    final uri = previous.resolveUri(location);
    if (uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.pathSegments.contains('..')) {
      return false;
    }
    if (_isTrustedGithubAndroidApk(uri, brand)) {
      githubReleaseSeen = true;
    } else if (uri.host == brand.host &&
        uri.path == '/download/android' &&
        !githubReleaseSeen) {
      // Brand's canonical download redirect (no arbitrary same-host paths).
    } else if (githubReleaseSeen &&
        ((uri.host == 'release-assets.githubusercontent.com' &&
                uri.path.startsWith('/github-production-release-asset/')) ||
            (uri.host == 'objects.githubusercontent.com' &&
                uri.path.startsWith('/github-production-release-asset')))) {
      // GitHub release asset CDN; the original URL already passed brand checks.
    } else {
      return false;
    }
    previous = uri;
  }
  return true;
}

enum AndroidUpdateStatus { newer, current, unavailable }

class AndroidUpdateLookup {
  const AndroidUpdateLookup({required this.status, this.release});

  final AndroidUpdateStatus status;
  final AndroidRelease? release;
}

AndroidUpdateLookup interpretAndroidUpdate(String body, String currentVersion) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      return const AndroidUpdateLookup(status: AndroidUpdateStatus.unavailable);
    }
    final version = decoded['version']?.toString().trim() ?? '';
    final uri = Uri.tryParse(decoded['url']?.toString().trim() ?? '');
    if (version.isEmpty || uri == null || !isTrustedAndroidApkUrl(uri)) {
      return const AndroidUpdateLookup(status: AndroidUpdateStatus.unavailable);
    }
    if (compareNumericVersions(version, currentVersion) <= 0) {
      return const AndroidUpdateLookup(status: AndroidUpdateStatus.current);
    }
    return AndroidUpdateLookup(
      status: AndroidUpdateStatus.newer,
      release: AndroidRelease(version: version, url: uri),
    );
  } catch (_) {
    return const AndroidUpdateLookup(status: AndroidUpdateStatus.unavailable);
  }
}

class AndroidUpdateCheck {
  const AndroidUpdateCheck();

  static Uri get endpoint => AppBrand.current.androidUpdateEndpoint;

  Future<AndroidUpdateLookup> lookup(String currentVersion) async {
    if (kIsWeb || !Platform.isAndroid) {
      return const AndroidUpdateLookup(status: AndroidUpdateStatus.unavailable);
    }
    final brand = AppBrand.current;
    final client = HttpClient();
    try {
      final request = await client.getUrl(endpoint).timeout(const Duration(seconds: 8));
      request.headers.set(HttpHeaders.userAgentHeader, brand.appName);
      final response = await request.close().timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        return const AndroidUpdateLookup(status: AndroidUpdateStatus.unavailable);
      }
      final body = await response.transform(utf8.decoder).join();
      return interpretAndroidUpdate(body, currentVersion);
    } catch (_) {
      return const AndroidUpdateLookup(status: AndroidUpdateStatus.unavailable);
    } finally {
      client.close(force: true);
    }
  }
}
