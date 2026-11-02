import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:pulse_vpn/features/settings/android_update_prompt.dart';
import 'package:pulse_vpn/features/settings/windows_update_prompt.dart';

Future<void> checkForAppUpdate(
  BuildContext context, {
  required bool manual,
}) async {
  if (kIsWeb) return;
  if (Platform.isWindows) {
    await checkForWindowsUpdate(context, manual: manual);
    return;
  }
  if (Platform.isAndroid) {
    await checkForAndroidUpdate(context, manual: manual);
  }
}
