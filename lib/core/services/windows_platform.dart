import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:pulse_vpn/app/brand/app_brand.dart';

/// Removes legacy Windows Firewall rules left by older K-Pax/X-Plm builds.
/// This implementation does not provide a persistent fail-closed kill switch.
class WindowsFirewall {
  /// Widget tests on Windows: netsh can block on UAC / policy.
  static bool disableForTests = false;

  static Future<void> clear() async {
    if (kIsWeb || !Platform.isWindows || disableForTests) return;
    // Drop both brand rule names so white-label leftovers do not stick around.
    for (final name in [
      'K-Pax-KillSwitch',
      'K-Pax-KillSwitch-App',
      'X-Plm-KillSwitch',
      'X-Plm-KillSwitch-App',
    ]) {
      try {
        await Process.run('netsh', [
          'advfirewall',
          'firewall',
          'delete',
          'rule',
          'name=$name',
        ]).timeout(const Duration(seconds: 3));
      } catch (_) {
        // Missing elevation / sandbox / test host — never block hydrate/connect.
      }
    }
  }

  static Future<void> blockOutboundExceptApp() async {
    // The previous machine-wide outbound BLOCK rule overrides its own ALLOW
    // rules and can strand both the VPN process and the device offline.
    // Disabled pending a correctly implemented and tested WFP kill switch.
    // IMPORTANT: Windows does NOT provide a persistent fail-closed kill switch.
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
