import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:pulse_vpn/app/brand/app_brand.dart';

class WindowsRelease {
  const WindowsRelease({required this.version, required this.url});

  final String version;
  final Uri url;
}

int compareNumericVersions(String left, String right) {
  List<int> parts(String value) {
    final core = value.split('+').first.split('-').first;
    return [
      for (final piece in core.split('.'))
        if (piece.isNotEmpty) int.tryParse(piece) ?? 0,
    ];
  }

  final a = parts(left);
  final b = parts(right);
  final count = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < count; i++) {
    final av = i < a.length ? a[i] : 0;
    final bv = i < b.length ? b[i] : 0;
    if (av != bv) return av.compareTo(bv);
  }
  return 0;
}

bool isTrustedWindowsSetupUrl(Uri uri) {
  return uri.scheme == 'https' &&
      uri.host == 'github.com' &&
      uri.path.startsWith('/uvarov89/k-pax/releases/download/') &&
      uri.path.endsWith('.exe') &&
      !uri.path.contains('..');
}

enum WindowsUpdateStatus { newer, current, unavailable }

class WindowsUpdateLookup {
  const WindowsUpdateLookup({required this.status, this.release});

  final WindowsUpdateStatus status;
  final WindowsRelease? release;
}

WindowsUpdateLookup interpretWindowsUpdate(String body, String currentVersion) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      return const WindowsUpdateLookup(status: WindowsUpdateStatus.unavailable);
    }
    final version = decoded['version']?.toString().trim() ?? '';
    final uri = Uri.tryParse(decoded['url']?.toString().trim() ?? '');
    if (version.isEmpty || uri == null || !isTrustedWindowsSetupUrl(uri)) {
      return const WindowsUpdateLookup(status: WindowsUpdateStatus.unavailable);
    }
    if (compareNumericVersions(version, currentVersion) <= 0) {
      return const WindowsUpdateLookup(status: WindowsUpdateStatus.current);
    }
    return WindowsUpdateLookup(
      status: WindowsUpdateStatus.newer,
      release: WindowsRelease(version: version, url: uri),
    );
  } catch (_) {
    return const WindowsUpdateLookup(status: WindowsUpdateStatus.unavailable);
  }
}

class WindowsUpdateCheck {
  const WindowsUpdateCheck();

  static Uri get endpoint => AppBrand.current.windowsUpdateEndpoint;

  Future<WindowsUpdateLookup> lookup(String currentVersion) async {
    if (kIsWeb || !Platform.isWindows) {
      return const WindowsUpdateLookup(status: WindowsUpdateStatus.unavailable);
    }
    final client = HttpClient();
    try {
      final request =
          await client.getUrl(endpoint).timeout(const Duration(seconds: 8));
      request.headers.set(
        HttpHeaders.userAgentHeader,
        AppBrand.current.appName,
      );
      final response = await request.close().timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        return const WindowsUpdateLookup(status: WindowsUpdateStatus.unavailable);
      }
      final body = await response.transform(utf8.decoder).join();
      return interpretWindowsUpdate(body, currentVersion);
    } catch (_) {
      return const WindowsUpdateLookup(status: WindowsUpdateStatus.unavailable);
    } finally {
      client.close(force: true);
    }
  }
}
