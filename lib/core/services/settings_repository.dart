import 'package:shared_preferences/shared_preferences.dart';

import 'package:pulse_vpn/core/models/app_settings.dart';
import 'package:pulse_vpn/core/models/connection_models.dart';
import 'package:pulse_vpn/core/models/split_tunnel.dart';
import 'package:pulse_vpn/core/models/subscription.dart';

class SettingsRepository {
  static const _kLanguage = 'language';
  static const _kTheme = 'theme';
  static const _kNotifications = 'notifications';
  static const _kAutoLaunch = 'auto_connect_launch';
  static const _kAutoWifi = 'auto_connect_wifi';
  static const _kAutoMobile = 'auto_connect_mobile';
  static const _kRememberCountry = 'remember_last_country';
  static const _kSplitMode = 'split_tunnel_mode';
  static const _kSplitPackages = 'split_tunnel_packages';
  static const _kUserMode = 'user_mode';
  static const _kLocationMode = 'location_mode';
  static const _kLocationId = 'location_id';
  static const _kProtocol = 'protocol';
  static const _kBypass = 'bypass';
  static const _kDns = 'dns_auto';
  static const _kKillSwitch = 'kill_switch';
  static const _kIpv6 = 'ipv6';
  static const _kFallback = 'protocol_fallback';
  static const _kReconnect = 'reconnect_policy';
  static const _kUserId = 'user_id';
  static const _kReferralCode = 'referral_code';
  static const _kPlan = 'subscription_plan';
  static const _kTrialStarted = 'trial_started';
  static const _kAccessExpires = 'access_expires';
  static const _kReferralMonths = 'referral_months';
  static const _kFriendsConverted = 'friends_converted';
  static const _kDisplayName = 'display_name';
  static const _kSubscriptionUrl = 'subscription_url';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  T _enumAt<T extends Enum>(List<T> values, int? index, T fallback) {
    if (index == null || index < 0 || index >= values.length) {
      return fallback;
    }
    return values[index];
  }

  Future<AppSettings> loadAppSettings() async {
    final p = await _prefs;
    return AppSettings(
      language: AppLanguageLabel.fromCode(p.getString(_kLanguage)),
      theme: p.getString(_kTheme) == 'light'
          ? AppThemePreference.light
          : AppThemePreference.dark,
      notificationsEnabled: p.getBool(_kNotifications) ?? true,
      autoConnectOnLaunch: p.getBool(_kAutoLaunch) ?? false,
      autoConnectOnWifi: p.getBool(_kAutoWifi) ?? false,
      autoConnectOnMobile: p.getBool(_kAutoMobile) ?? false,
      rememberLastCountry: p.getBool(_kRememberCountry) ?? true,
      splitTunnelMode: SplitTunnelModeX.fromIndex(p.getInt(_kSplitMode)),
      splitTunnelPackages: p.getStringList(_kSplitPackages) ?? const [],
    );
  }

  Future<void> saveAppSettings(AppSettings settings) async {
    final p = await _prefs;
    await p.setString(_kLanguage, settings.language.code);
    await p.setString(
      _kTheme,
      settings.theme == AppThemePreference.light ? 'light' : 'dark',
    );
    await p.setBool(_kNotifications, settings.notificationsEnabled);
    await p.setBool(_kAutoLaunch, settings.autoConnectOnLaunch);
    await p.setBool(_kAutoWifi, settings.autoConnectOnWifi);
    await p.setBool(_kAutoMobile, settings.autoConnectOnMobile);
    await p.setBool(_kRememberCountry, settings.rememberLastCountry);
    await p.setInt(_kSplitMode, settings.splitTunnelMode.index);
    await p.setStringList(_kSplitPackages, settings.splitTunnelPackages);
  }

  Future<ProSettings> loadProSettings() async {
    final p = await _prefs;
    return ProSettings(
      protocol: _enumAt(
        TunnelProtocol.values,
        p.getInt(_kProtocol),
        TunnelProtocol.auto,
      ),
      bypassMode: _enumAt(
        BypassMode.values,
        p.getInt(_kBypass),
        BypassMode.auto,
      ),
      dnsAutomatic: p.getBool(_kDns) ?? true,
      killSwitch: p.getBool(_kKillSwitch) ?? false,
      ipv6Mode: _enumAt(Ipv6Mode.values, p.getInt(_kIpv6), Ipv6Mode.enabled),
      protocolFallback: p.getBool(_kFallback) ?? true,
      reconnectPolicy: _enumAt(
        ReconnectPolicy.values,
        p.getInt(_kReconnect),
        ReconnectPolicy.normal,
      ),
    );
  }

  Future<void> saveProSettings(ProSettings settings) async {
    final p = await _prefs;
    await p.setInt(_kProtocol, settings.protocol.index);
    await p.setInt(_kBypass, settings.bypassMode.index);
    await p.setBool(_kDns, settings.dnsAutomatic);
    await p.setBool(_kKillSwitch, settings.killSwitch);
    await p.setInt(_kIpv6, settings.ipv6Mode.index);
    await p.setBool(_kFallback, settings.protocolFallback);
    await p.setInt(_kReconnect, settings.reconnectPolicy.index);
  }

  Future<UserAccount?> loadAccount() async {
    final p = await _prefs;
    final userId = p.getString(_kUserId);
    final referral = p.getString(_kReferralCode);
    final trialMs = p.getInt(_kTrialStarted);
    final expiresMs = p.getInt(_kAccessExpires);
    if (userId == null ||
        referral == null ||
        trialMs == null ||
        expiresMs == null) {
      return null;
    }
    return UserAccount(
      userId: userId,
      referralCode: referral,
      plan: _enumAt(
        SubscriptionPlan.values,
        p.getInt(_kPlan),
        SubscriptionPlan.trial,
      ),
      trialStartedAt: DateTime.fromMillisecondsSinceEpoch(trialMs),
      accessExpiresAt: DateTime.fromMillisecondsSinceEpoch(expiresMs),
      referralMonthsEarned: p.getInt(_kReferralMonths) ?? 0,
      friendsConverted: p.getInt(_kFriendsConverted) ?? 0,
      displayName: p.getString(_kDisplayName) ?? 'Guest',
    );
  }

  Future<void> saveAccount(UserAccount account) async {
    final p = await _prefs;
    await p.setString(_kUserId, account.userId);
    await p.setString(_kReferralCode, account.referralCode);
    await p.setInt(_kPlan, account.plan.index);
    await p.setInt(
      _kTrialStarted,
      account.trialStartedAt.millisecondsSinceEpoch,
    );
    await p.setInt(
      _kAccessExpires,
      account.accessExpiresAt.millisecondsSinceEpoch,
    );
    await p.setInt(_kReferralMonths, account.referralMonthsEarned);
    await p.setInt(_kFriendsConverted, account.friendsConverted);
    await p.setString(_kDisplayName, account.displayName ?? 'Guest');
  }

  Future<String?> loadSubscriptionUrl() async {
    final p = await _prefs;
    final value = p.getString(_kSubscriptionUrl);
    if (value == null || value.isEmpty) return null;
    return value;
  }

  Future<void> saveSubscriptionUrl(String url) async {
    final p = await _prefs;
    await p.setString(_kSubscriptionUrl, url);
  }

  Future<({AppUserMode mode, LocationMode locationMode, String locationId})>
      loadSessionPrefs() async {
    final p = await _prefs;
    return (
      mode: _enumAt(
        AppUserMode.values,
        p.getInt(_kUserMode),
        AppUserMode.simple,
      ),
      locationMode: _enumAt(
        LocationMode.values,
        p.getInt(_kLocationMode),
        LocationMode.auto,
      ),
      locationId: p.getString(_kLocationId) ?? 'auto',
    );
  }

  Future<void> saveSessionPrefs({
    required AppUserMode mode,
    required LocationMode locationMode,
    required String locationId,
  }) async {
    final p = await _prefs;
    await p.setInt(_kUserMode, mode.index);
    await p.setInt(_kLocationMode, locationMode.index);
    await p.setString(_kLocationId, locationId);
  }
}
