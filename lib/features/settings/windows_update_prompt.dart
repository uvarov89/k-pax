import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:pulse_vpn/app/brand/app_brand.dart';
import 'package:pulse_vpn/core/services/update_clearnet.dart';
import 'package:pulse_vpn/core/services/windows_update.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';

var _checking = false;

Future<File?> _downloadSetup(Uri url) async {
  final brand = AppBrand.current;
  final setupName =
      brand.isXplm ? 'X-Plm-Setup-update.exe' : 'K-Pax-Setup-update.exe';
  final file = File('${Directory.systemTemp.path}\\$setupName');
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

Future<bool> _applySetup(File file) async {
  try {
    await const MethodChannel(
      'kpax/window',
    ).invokeMethod<void>('launchInstaller', file.path);
    await const MethodChannel('kpax/window').invokeMethod<void>('quit');
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> checkForWindowsUpdate(
  BuildContext context, {
  required bool manual,
}) async {
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
    final lookup = await const WindowsUpdateCheck().lookup(info.version);
    if (!context.mounted) return;
    switch (lookup.status) {
      case WindowsUpdateStatus.unavailable:
        if (manual) {
          messenger?.showSnackBar(SnackBar(content: Text(s.updateCheckFailed)));
        }
        break;
      case WindowsUpdateStatus.current:
        if (manual) {
          messenger?.showSnackBar(SnackBar(content: Text(s.updateCurrent)));
        }
        break;
      case WindowsUpdateStatus.newer:
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
          final file = await _downloadSetup(release.url);
          if (!context.mounted) return;
          if (file == null) {
            messenger?.showSnackBar(
              SnackBar(content: Text(s.updateApplyFailed)),
            );
            break;
          }
          final started = await _applySetup(file);
          if (!started) {
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
