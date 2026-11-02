import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:pulse_vpn/core/services/windows_update.dart';

class AndroidRelease {
  const AndroidRelease({required this.version, required this.url});

  final String version;
  final Uri url;
}

bool isTrustedAndroidApkUrl(Uri uri) {
  return uri.scheme == 'https' &&
      uri.host == 'github.com' &&
      uri.path.startsWith('/uvarov89/k-pax/releases/download/') &&
      uri.path.toLowerCase().endsWith('.apk') &&
      !uri.path.contains('..');
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

  static final Uri endpoint = Uri.parse('https://k-pax.space/app/android');

  Future<AndroidUpdateLookup> lookup(String currentVersion) async {
    if (kIsWeb || !Platform.isAndroid) {
      return const AndroidUpdateLookup(status: AndroidUpdateStatus.unavailable);
    }
    final client = HttpClient();
    try {
      final request = await client.getUrl(endpoint).timeout(const Duration(seconds: 8));
      request.headers.set(HttpHeaders.userAgentHeader, 'K-Pax');
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
