import 'package:pulse_vpn/core/models/split_tunnel.dart';

enum AppLanguage { ru, en }

enum AppThemePreference { dark, light }

enum Ipv6Mode { enabled, disabled, tunnelOnly }

enum ReconnectPolicy { normal, aggressive }

extension AppLanguageLabel on AppLanguage {
  String get code => switch (this) {
        AppLanguage.ru => 'ru',
        AppLanguage.en => 'en',
      };

  String get nativeName => switch (this) {
        AppLanguage.ru => 'Русский',
        AppLanguage.en => 'English',
      };

  static AppLanguage fromCode(String? code) {
    return switch (code) {
      'en' => AppLanguage.en,
      _ => AppLanguage.ru,
    };
  }
}

extension Ipv6ModeLabel on Ipv6Mode {
  String label(AppLanguage lang) => switch (this) {
        Ipv6Mode.enabled => lang == AppLanguage.ru ? 'Вкл' : 'On',
        Ipv6Mode.disabled => lang == AppLanguage.ru ? 'Выкл' : 'Off',
        Ipv6Mode.tunnelOnly =>
          lang == AppLanguage.ru ? 'Только туннель' : 'Tunnel only',
      };
}

extension ReconnectPolicyLabel on ReconnectPolicy {
  String label(AppLanguage lang) => switch (this) {
        ReconnectPolicy.normal =>
          lang == AppLanguage.ru ? 'Обычный' : 'Normal',
        ReconnectPolicy.aggressive =>
          lang == AppLanguage.ru ? 'Агрессивный' : 'Aggressive',
      };
}

class AppSettings {
  const AppSettings({
    this.language = AppLanguage.ru,
    this.theme = AppThemePreference.dark,
    this.notificationsEnabled = true,
    this.autoConnectOnLaunch = false,
    this.autoConnectOnWifi = false,
    this.autoConnectOnMobile = false,
    this.rememberLastCountry = true,
    this.splitTunnelMode = SplitTunnelMode.allApps,
    this.splitTunnelPackages = const [],
  });

  final AppLanguage language;
  final AppThemePreference theme;
  final bool notificationsEnabled;
  final bool autoConnectOnLaunch;
  final bool autoConnectOnWifi;
  final bool autoConnectOnMobile;
  final bool rememberLastCountry;
  final SplitTunnelMode splitTunnelMode;
  final List<String> splitTunnelPackages;

  AppSettings copyWith({
    AppLanguage? language,
    AppThemePreference? theme,
    bool? notificationsEnabled,
    bool? autoConnectOnLaunch,
    bool? autoConnectOnWifi,
    bool? autoConnectOnMobile,
    bool? rememberLastCountry,
    SplitTunnelMode? splitTunnelMode,
    List<String>? splitTunnelPackages,
  }) {
    return AppSettings(
      language: language ?? this.language,
      theme: theme ?? this.theme,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      autoConnectOnLaunch: autoConnectOnLaunch ?? this.autoConnectOnLaunch,
      autoConnectOnWifi: autoConnectOnWifi ?? this.autoConnectOnWifi,
      autoConnectOnMobile: autoConnectOnMobile ?? this.autoConnectOnMobile,
      rememberLastCountry: rememberLastCountry ?? this.rememberLastCountry,
      splitTunnelMode: splitTunnelMode ?? this.splitTunnelMode,
      splitTunnelPackages: splitTunnelPackages ?? this.splitTunnelPackages,
    );
  }
}
