import 'dart:io';

import 'package:flutter/foundation.dart';

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

class WindowsStartup {
  static const _task = 'K-Pax';

  static Future<void> setEnabled(bool enabled) async {
    if (kIsWeb || !Platform.isWindows) return;
    if (!enabled) {
      await Process.run('schtasks', ['/Delete', '/F', '/TN', _task]);
      return;
    }
    final exe = Platform.resolvedExecutable;
    await Process.run('schtasks', [
      '/Create',
      '/F',
      '/TN',
      _task,
      '/SC',
      'ONLOGON',
      '/RL',
      'HIGHEST',
      '/TR',
      '"$exe"',
    ]);
  }
}
