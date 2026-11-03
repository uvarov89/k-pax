import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:pulse_vpn/app/brand/app_brand.dart';
import 'package:pulse_vpn/core/models/connection_models.dart';
import 'package:pulse_vpn/core/services/android_update.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';

var _checking = false;

Future<Directory> _androidCacheDir() async {
  try {
    final path = await const MethodChannel('kpax/android').invokeMethod<String>('cacheDir');
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
    final request = await client.getUrl(url).timeout(const Duration(seconds: 20));
    request.followRedirects = true;
    request.maxRedirects = 8;
    request.headers.set(HttpHeaders.userAgentHeader, brand.appName);
    final response = await request.close().timeout(const Duration(minutes: 5));
    if (response.statusCode != 200) return null;
    final sink = file.openWrite();
    await response.pipe(sink);
    await sink.close();
    if (!await file.exists() || await file.length() < 1024 * 100) {
      if (await file.exists()) await file.delete();
      return null;
    }
    return file;
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

Future<String?> _installApk(File file) async {
  try {
    final outcome = await const MethodChannel('kpax/android').invokeMethod<String>(
      'installApk',
      file.path,
    );
    return outcome ?? 'started';
  } catch (_) {
    return null;
  }
}

Future<void> checkForAndroidUpdate(
  BuildContext context, {
  required bool manual,
}) async {
  if (_checking) return;
  _checking = true;
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final info = await PackageInfo.fromPlatform();
    final lookup = await const AndroidUpdateCheck().lookup(info.version);
    if (!context.mounted) return;
    final s = context.read<VpnController>().strings;
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
          messenger?.showSnackBar(SnackBar(content: Text(s.updateDownloading)));
          final file = await _downloadApk(release.url);
          if (!context.mounted) return;
          if (file == null) {
            messenger?.showSnackBar(SnackBar(content: Text(s.updateApplyFailed)));
            break;
          }
          final controller = context.read<VpnController>();
          if (controller.connectionState != VpnConnectionState.disconnected &&
              controller.connectionState != VpnConnectionState.disconnecting) {
            await controller.disconnect();
          }
          final outcome = await _installApk(file);
          if (!context.mounted) return;
          if (outcome == 'need_permission') {
            messenger?.showSnackBar(
              SnackBar(content: Text(s.updateInstallPermission)),
            );
          } else if (outcome != 'started') {
            messenger?.showSnackBar(SnackBar(content: Text(s.updateApplyFailed)));
          }
        }
        break;
    }
  } finally {
    _checking = false;
  }
}
