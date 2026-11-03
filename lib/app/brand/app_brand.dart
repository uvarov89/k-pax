import 'package:package_info_plus/package_info_plus.dart';

/// Compile-time / runtime brand for white-label builds (K-Pax vs X-Plm).
final class AppBrand {
  const AppBrand._({
    required this.id,
    required this.appName,
    required this.host,
    required this.subHost,
    required this.accountPrefix,
    required this.priceRub,
    required this.deepLinkScheme,
    required this.logoAsset,
    required this.updateApkName,
    required this.telegramHandle,
    required this.channelUrl,
  });

  final String id;
  final String appName;
  final String host;
  final String subHost;
  final String accountPrefix;
  final int priceRub;
  final String deepLinkScheme;
  final String logoAsset;
  final String updateApkName;
  final String? telegramHandle;
  final String? channelUrl;

  bool get isXplm => id == 'xplm';
  bool get isKpax => id == 'kpax';

  /// X-Plm is email-only; K-Pax also accepts Telegram nicks.
  bool get allowsTelegram => isKpax;

  String get supportEmail => 'support@$host';
  String get siteUrl => 'https://$host/';
  String get payUrl => 'https://$host/pay';
  String get termsUrl => 'https://$host/terms';
  String get privacyUrl => 'https://$host/privacy';
  String get priceLabel => '$priceRub ₽';
  String get subExample => 'https://$subHost/s/…';

  Uri get androidUpdateEndpoint => Uri.parse('https://$host/app/android');
  Uri get windowsUpdateEndpoint => Uri.parse('https://$host/app/windows');
  Uri appStart() => Uri.parse('https://$host/app/start');
  Uri appLogin() => Uri.parse('https://$host/app/login');
  Uri appLoginStatus() => Uri.parse('https://$host/app/login/status');
  Uri appDevices() => Uri.parse('https://$host/app/devices');
  Uri appDevicesKick() => Uri.parse('https://$host/app/devices/kick');

  String inviteLink(String id) => 'https://$host/?ref=$id';

  String subscriptionUrl(String token) => 'https://$subHost/s/$token';

  static const kpax = AppBrand._(
    id: 'kpax',
    appName: 'K-Pax',
    host: 'k-pax.space',
    subHost: 'sub.k-pax.space',
    accountPrefix: 'KP',
    priceRub: 110,
    deepLinkScheme: 'kpax',
    logoAsset: 'assets/brand/logo.png',
    updateApkName: 'K-Pax-update.apk',
    telegramHandle: '@k_pax_space',
    channelUrl: 'https://t.me/kpaxvpn',
  );

  static const xplm = AppBrand._(
    id: 'xplm',
    appName: 'X-Plm',
    host: 'x-plm.online',
    subHost: 'sub.x-plm.online',
    accountPrefix: 'XP',
    priceRub: 299,
    deepLinkScheme: 'xplm',
    logoAsset: 'assets/brand/xplm_logo.png',
    updateApkName: 'X-Plm-update.apk',
    telegramHandle: null,
    channelUrl: null,
  );

  static AppBrand _current = kpax;

  static AppBrand get current => _current;

  /// Prefer `--dart-define=BRAND=xplm`; else infer from Android applicationId.
  static Future<void> init() async {
    const fromEnv = String.fromEnvironment('BRAND', defaultValue: '');
    final normalized = fromEnv.trim().toLowerCase();
    if (normalized == 'xplm') {
      _current = xplm;
      return;
    }
    if (normalized == 'kpax') {
      _current = kpax;
      return;
    }
    try {
      final info = await PackageInfo.fromPlatform();
      final pkg = info.packageName.toLowerCase();
      _current = pkg.contains('xplm') ? xplm : kpax;
    } catch (_) {
      _current = kpax;
    }
  }
}
