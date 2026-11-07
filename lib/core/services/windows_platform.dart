import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:pulse_vpn/app/brand/app_brand.dart';

/// Removes a leftover outbound block and can put it back if the tunnel drops.
class WindowsFirewall {
  static const _block = 'K-Pax-KillSwitch';
  static const _allow = 'K-Pax-KillSwitch-App';

  static Future<void> clear() async {
    if (kIsWeb || !Platform.isWindows) return;
    await Process.run('netsh', [
      'advfirewall',
      'firewall',
      'delete',
      'rule',
      'name=$_block',
    ]);
    await Process.run('netsh', [
      'advfirewall',
      'firewall',
      'delete',
      'rule',
      'name=$_allow',
    ]);
  }

  static Future<void> blockOutboundExceptApp() async {
    if (kIsWeb || !Platform.isWindows) return;
    await clear();
    await Process.run('netsh', [
      'advfirewall',
      'firewall',
      'add',
      'rule',
      'name=$_block',
      'dir=out',
      'action=block',
      'enable=yes',
    ]);
    await Process.run('netsh', [
      'advfirewall',
      'firewall',
      'add',
      'rule',
      'name=$_allow',
      'dir=out',
      'action=allow',
      'program=${Platform.resolvedExecutable}',
      'enable=yes',
    ]);
  }
}

typedef StartupCommand =
    Future<ProcessResult> Function(String executable, List<String> arguments);

class WindowsStartup {
  static String get taskName => AppBrand.current.isXplm ? 'X-Plm' : 'K-Pax';
  static Future<void> setEnabled(bool enabled, {StartupCommand? run}) async {
    if (kIsWeb || !Platform.isWindows) return;
    final execute =
        run ??
        (String executable, List<String> arguments) =>
            Process.run(executable, arguments);
    ProcessResult result;
    if (!enabled) {
      final query = await execute('schtasks', ['/Query', '/FO', 'CSV', '/NH']);
      if (query.exitCode != 0) throw StateError('Could not read startup tasks');
      final names = query.stdout.toString().split('\n').map((line) {
        final match = RegExp(r'^"((?:[^"]|"")*)"').firstMatch(line);
        return match
            ?.group(1)
            ?.replaceAll('""', '"')
            .split(String.fromCharCode(92))
            .last;
      });
      if (!names.contains(taskName)) return;
      result = await execute('schtasks', ['/Delete', '/F', '/TN', taskName]);
    } else {
      result = await execute('schtasks', [
        '/Create',
        '/F',
        '/TN',
        taskName,
        '/SC',
        'ONLOGON',
        '/RL',
        'HIGHEST',
        '/TR',
        '"${Platform.resolvedExecutable}"',
      ]);
    }
    if (result.exitCode != 0) throw StateError('Could not update startup task');
  }
}
