import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Distribution channel (sideload vs Google Play).
///
/// Prefer `--dart-define=PLAY_STORE=true` with `--flavor *Play`. When the define
/// is omitted, Android reads [BuildConfig.PLAY_STORE_CHANNEL] from the flavor
/// so Play AABs never keep the APK self-update path by accident.
final class AppDistribution {
  const AppDistribution._();

  static const bool _playStoreDefine = bool.fromEnvironment(
    'PLAY_STORE',
    defaultValue: false,
  );

  static bool _playStoreRuntime = false;
  static bool _resolved = false;

  static bool get playStore => _playStoreDefine || _playStoreRuntime;

  /// In-app APK download/install is only for direct (GitHub) builds.
  static bool get allowsApkSelfUpdate => !playStore;

  /// About → «Проверить обновления» opens the store listing instead of GitHub.
  static bool get updatesViaStore => playStore;

  /// Call once at startup so Play flavor builds without dart-define still
  /// disable self-update.
  static Future<void> init() async {
    if (_resolved || _playStoreDefine) {
      _resolved = true;
      return;
    }
    if (kIsWeb || !Platform.isAndroid) {
      _resolved = true;
      return;
    }
    try {
      final value = await const MethodChannel(
        'kpax/android',
      ).invokeMethod<bool>('isPlayStore');
      _playStoreRuntime = value == true;
    } catch (_) {
      _playStoreRuntime = false;
    }
    _resolved = true;
  }
}
