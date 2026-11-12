/// Compile-time distribution channel (sideload vs Google Play).
///
/// Play AAB builds: `--dart-define=PLAY_STORE=true` together with `--flavor kpaxPlay`.
final class AppDistribution {
  const AppDistribution._();

  static const bool playStore = bool.fromEnvironment(
    'PLAY_STORE',
    defaultValue: false,
  );

  /// In-app APK download/install is only for direct (GitHub) builds.
  static bool get allowsApkSelfUpdate => !playStore;

  /// About → «Проверить обновления» opens the store listing instead of GitHub.
  static bool get updatesViaStore => playStore;
}
