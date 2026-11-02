import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
  static const _kLaunchAtLogin = 'launch_at_login';
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
  static const _kSubscriptions = 'subscriptions';
  static const _kLoginSession = 'login_session';
  static const _kLoginChannel = 'login_channel';
  static const _kLoginBotUrl = 'login_bot_url';
  static const _kLoginHint = 'login_hint';
  static const _kLoginStarted = 'login_started_ms';
  static const _kLoginPublicId = 'login_public_id';
  static const _kDismissedHomeNotice = 'dismissed_home_notice_id';
  static const _kOnboardingSeen = 'onboarding_seen_v1';

  /// Soft home banner after Reality SNI rotation — bump id to show again later.
  static const homeRefreshNoticeId = 'reality_cdn_2026_11';

  static const _secureUrl = 'secure_subscription_url';
  static const _secureList = 'secure_subscriptions';
  static const _secureLoginSession = 'secure_login_session';
  static const _secureLoginMeta = 'secure_login_meta';

  final FlutterSecureStorage _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    wOptions: WindowsOptions(),
  );

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  T _enumAt<T extends Enum>(List<T> values, int? index, T fallback) {
    if (index == null || index < 0 || index >= values.length) {
      return fallback;
    }
    return values[index];
  }

  Future<void> _wipePlaintextSubscriptions(SharedPreferences p) async {
    await p.remove(_kSubscriptionUrl);
    await p.remove(_kSubscriptions);
  }

  Future<void> _wipePlaintextLogin(SharedPreferences p) async {
    await p.remove(_kLoginSession);
    await p.remove(_kLoginChannel);
    await p.remove(_kLoginBotUrl);
    await p.remove(_kLoginHint);
    await p.remove(_kLoginPublicId);
    await p.remove(_kLoginStarted);
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
      launchAtLogin: p.getBool(_kLaunchAtLogin) ?? false,
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
    await p.setBool(_kLaunchAtLogin, settings.launchAtLogin);
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
      killSwitch: p.getBool(_kKillSwitch) ?? true,
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
    try {
      final secure = await _secure.read(key: _secureUrl);
      if (secure != null && secure.isNotEmpty) {
        final p = await _prefs;
        if (p.containsKey(_kSubscriptionUrl) || p.containsKey(_kSubscriptions)) {
          await _wipePlaintextSubscriptions(p);
        }
        return secure;
      }
    } catch (_) {}

    final p = await _prefs;
    final legacy = p.getString(_kSubscriptionUrl);
    if (legacy == null || legacy.isEmpty) return null;
    await saveSubscriptionUrl(legacy);
    return legacy;
  }

  Future<void> saveSubscriptionUrl(String url) async {
    try {
      if (url.isEmpty) {
        await _secure.delete(key: _secureUrl);
      } else {
        await _secure.write(key: _secureUrl, value: url);
      }
    } catch (_) {
      // Fall through to prefs only if secure storage is unavailable (tests).
      final p = await _prefs;
      await p.setString(_kSubscriptionUrl, url);
      return;
    }
    final p = await _prefs;
    await p.remove(_kSubscriptionUrl);
  }

  /// Saved links; the single link of older versions becomes the first entry.
  Future<List<SavedSubscription>> loadSubscriptions() async {
    final list = <SavedSubscription>[];
    String? raw;
    try {
      raw = await _secure.read(key: _secureList);
    } catch (_) {}

    final p = await _prefs;
    if (raw == null || raw.isEmpty) {
      raw = p.getString(_kSubscriptions);
    }

    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            final saved = SavedSubscription.fromJson(item);
            if (saved != null && list.every((other) => other.url != saved.url)) {
              list.add(saved);
            }
          }
        }
      } catch (_) {}
    }

    final active = await loadSubscriptionUrl() ?? '';
    if (active.isNotEmpty && list.every((item) => item.url != active)) {
      list.insert(0, SavedSubscription(url: active));
    }

    if (list.isNotEmpty) {
      await saveSubscriptions(list);
    } else {
      await _wipePlaintextSubscriptions(p);
    }
    return list;
  }

  Future<void> saveSubscriptions(List<SavedSubscription> list) async {
    final encoded = jsonEncode([for (final item in list) item.toJson()]);
    try {
      if (list.isEmpty) {
        await _secure.delete(key: _secureList);
      } else {
        await _secure.write(key: _secureList, value: encoded);
      }
      final p = await _prefs;
      await p.remove(_kSubscriptions);
    } catch (_) {
      final p = await _prefs;
      await p.setString(_kSubscriptions, encoded);
    }
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

  Future<
      ({
        String session,
        String channel,
        String? botUrl,
        String? hint,
        String? publicId,
        int startedMs,
      })?> loadPendingLogin() async {
    try {
      final session = await _secure.read(key: _secureLoginSession) ?? '';
      final metaRaw = await _secure.read(key: _secureLoginMeta) ?? '';
      if (session.isNotEmpty && metaRaw.isNotEmpty) {
        final meta = jsonDecode(metaRaw);
        if (meta is Map) {
          final startedMs = int.tryParse('${meta['startedMs']}') ?? 0;
          if (startedMs > 0) {
            final p = await _prefs;
            await _wipePlaintextLogin(p);
            return (
              session: session,
              channel: meta['channel']?.toString() ?? '',
              botUrl: meta['botUrl']?.toString(),
              hint: meta['hint']?.toString(),
              publicId: meta['publicId']?.toString(),
              startedMs: startedMs,
            );
          }
        }
      }
    } catch (_) {}

    final p = await _prefs;
    final session = p.getString(_kLoginSession) ?? '';
    final startedMs = p.getInt(_kLoginStarted) ?? 0;
    if (session.isEmpty || startedMs <= 0) return null;
    final pending = (
      session: session,
      channel: p.getString(_kLoginChannel) ?? '',
      botUrl: p.getString(_kLoginBotUrl),
      hint: p.getString(_kLoginHint),
      publicId: p.getString(_kLoginPublicId),
      startedMs: startedMs,
    );
    await savePendingLogin(
      session: pending.session,
      channel: pending.channel,
      botUrl: pending.botUrl,
      hint: pending.hint,
      publicId: pending.publicId,
      startedMs: pending.startedMs,
    );
    return pending;
  }

  Future<void> savePendingLogin({
    required String session,
    required String channel,
    String? botUrl,
    String? hint,
    String? publicId,
    required int startedMs,
  }) async {
    final meta = jsonEncode({
      'channel': channel,
      'botUrl': botUrl ?? '',
      'hint': hint ?? '',
      'publicId': publicId ?? '',
      'startedMs': startedMs,
    });
    try {
      await _secure.write(key: _secureLoginSession, value: session);
      await _secure.write(key: _secureLoginMeta, value: meta);
      final p = await _prefs;
      await _wipePlaintextLogin(p);
    } catch (_) {
      final p = await _prefs;
      await p.setString(_kLoginSession, session);
      await p.setString(_kLoginChannel, channel);
      await p.setString(_kLoginBotUrl, botUrl ?? '');
      await p.setString(_kLoginHint, hint ?? '');
      await p.setString(_kLoginPublicId, publicId ?? '');
      await p.setInt(_kLoginStarted, startedMs);
    }
  }

  Future<void> clearPendingLogin() async {
    try {
      await _secure.delete(key: _secureLoginSession);
      await _secure.delete(key: _secureLoginMeta);
    } catch (_) {}
    final p = await _prefs;
    await p.remove(_kLoginSession);
    await p.remove(_kLoginChannel);
    await p.remove(_kLoginBotUrl);
    await p.remove(_kLoginHint);
    await p.remove(_kLoginPublicId);
    await p.remove(_kLoginStarted);
  }

  Future<String?> loadDismissedHomeNoticeId() async {
    final p = await _prefs;
    return p.getString(_kDismissedHomeNotice);
  }

  Future<void> dismissHomeNotice(String id) async {
    final p = await _prefs;
    await p.setString(_kDismissedHomeNotice, id);
  }

  Future<bool> loadOnboardingSeen() async {
    final p = await _prefs;
    return p.getBool(_kOnboardingSeen) ?? false;
  }

  Future<void> markOnboardingSeen() async {
    final p = await _prefs;
    await p.setBool(_kOnboardingSeen, true);
  }
}
