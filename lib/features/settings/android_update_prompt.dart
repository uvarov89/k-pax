import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pulse_vpn/app/brand/app_brand.dart';
import 'package:pulse_vpn/app/distribution.dart';
import 'package:pulse_vpn/core/services/android_update.dart';
import 'package:pulse_vpn/core/services/update_clearnet.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';

var _checking = false;

Future<Directory> _androidCacheDir() async {
  try {
    final path = await const MethodChannel(
      'kpax/android',
    ).invokeMethod<String>('cacheDir');
    if (path != null && path.isNotEmpty) return Directory(path);
  } catch (_) {}
  return Directory.systemTemp;
}

Future<File?> _downloadApk(Uri url) async {
  final brand = AppBrand.current;
  final dir = await _androidCacheDir();
  final file = File('${dir.path}/${brand.updateApkName}');
  final client = HttpClient()..autoUncompress = true;
  try {
    final request = await client
        .getUrl(url)
        .timeout(const Duration(seconds: 20));
    request.followRedirects = true;
    request.maxRedirects = 8;
    request.headers.set(HttpHeaders.userAgentHeader, brand.appName);
    final response = await request.close().timeout(const Duration(minutes: 5));
    if (response.statusCode != 200) return null;
    if (!isTrustedAndroidApkRedirectChain(
      url,
      response.redirects.map((hop) => hop.location),
    )) {
      debugPrint('Android update: rejected untrusted redirect chain');
      return null;
    }
    final sink = file.openWrite();
    await response.pipe(sink);
    if (!await file.exists() || await file.length() < 1024 * 100) {
      if (await file.exists()) await file.delete();
      return null;
    }
    // A 200 OK HTML error page must never reach the package installer.
    final handle = await file.open(mode: FileMode.read);
    try {
      final magic = await handle.read(4);
      if (magic.length != 4 ||
          magic[0] != 0x50 ||
          magic[1] != 0x4b ||
          magic[2] != 0x03 ||
          magic[3] != 0x04) {
        await file.delete();
        debugPrint('Android update: downloaded file is not an APK archive');
        return null;
      }
    } finally {
      await handle.close();
    }
    return file;
  } catch (error) {
    // No subscription URLs, tokens, cookies or response bodies in diagnostics.
    debugPrint('Android update download failed: ${error.runtimeType}');
    return null;
  } finally {
    client.close(force: true);
  }
}

Future<String?> _installApk(File file) async {
  try {
    final outcome = await const MethodChannel(
      'kpax/android',
    ).invokeMethod<String>('installApk', file.path);
    return outcome ?? 'started';
  } catch (_) {
    return null;
  }
}

Future<void> _openPlayStoreListing() async {
  try {
    await const MethodChannel('kpax/android').invokeMethod<bool>('openStoreListing');
  } catch (_) {}
}

Future<void> checkForAndroidUpdate(
  BuildContext context, {
  required bool manual,
}) async {
  if (!AppDistribution.allowsApkSelfUpdate) {
    if (manual) await _openPlayStoreListing();
    return;
  }
  if (_checking) return;
  _checking = true;
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final controller = context.read<VpnController>();
    final s = controller.strings;
    // Never check/download through a live tunnel — a dead VPN blocks updates.
    await ensureClearnetForUpdate(controller);
    if (!context.mounted) return;
    final info = await PackageInfo.fromPlatform();
    final lookup = await const AndroidUpdateCheck().lookup(info.version);
    if (!context.mounted) return;
    switch (lookup.status) {
      case AndroidUpdateStatus.unavailable:
        if (manual) {
          messenger?.showSnackBar(SnackBar(content: Text(s.updateCheckFailed)));
        }
        break;
      case AndroidUpdateStatus.current:
        if (manual) {
          messenger?.showSnackBar(SnackBar(content: Text(s.updateCurrent)));
        }
        break;
      case AndroidUpdateStatus.newer:
        final release = lookup.release;
        if (release == null) return;
        final install = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(s.updateTitle(release.version)),
            content: Text(s.updateBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(s.updateLater),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(s.updateNow),
              ),
            ],
          ),
        );
        if (install == true) {
          if (!context.mounted) return;
          await ensureClearnetForUpdate(context.read<VpnController>());
          if (!context.mounted) return;
          messenger?.showSnackBar(SnackBar(content: Text(s.updateDownloading)));
          final file = await _downloadApk(release.url);
          if (!context.mounted) return;
          if (file == null) {
            messenger?.showSnackBar(
              SnackBar(
                content: Text(s.updateDownloadFailed),
                duration: const Duration(seconds: 12),
                action: SnackBarAction(
                  label: s.updateOpenInBrowser,
                  onPressed: () => unawaited(
                    launchUrl(release.url, mode: LaunchMode.externalApplication),
                  ),
                ),
              ),
            );
            break;
          }
          final outcome = await _installApk(file);
          if (!context.mounted) return;
          if (outcome == 'need_permission') {
            messenger?.showSnackBar(
              SnackBar(content: Text(s.updateInstallPermission)),
            );
          } else if (outcome != 'started') {
            messenger?.showSnackBar(
              SnackBar(content: Text(s.updateApplyFailed)),
            );
          }
        }
        break;
    }
  } finally {
    _checking = false;
  }
}
