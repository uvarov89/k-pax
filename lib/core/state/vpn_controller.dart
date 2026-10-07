import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:pulse_vpn/app/l10n/app_strings.dart';
import 'package:pulse_vpn/core/models/app_settings.dart';
import 'package:pulse_vpn/core/models/connection_models.dart';
import 'package:pulse_vpn/core/models/server_location.dart';
import 'package:pulse_vpn/core/models/subscription.dart';
import 'package:pulse_vpn/core/models/tunnel_node.dart';
import 'package:pulse_vpn/core/services/settings_repository.dart';
import 'package:pulse_vpn/core/services/singbox_vpn_service.dart';
import 'package:pulse_vpn/core/services/subscription_client.dart';
import 'package:pulse_vpn/core/services/subscription_link.dart';
import 'package:pulse_vpn/core/services/tunnel_config.dart';
import 'package:pulse_vpn/core/services/vpn_service.dart';

enum SubscriptionLinkState { missing, loading, ready, expired, failed }

class VpnController extends ChangeNotifier {
  VpnController({
    VpnService? service,
    SettingsRepository? repository,
    SubscriptionClient? subscriptions,
  })  : _service = service ?? defaultVpnService(),
        _repository = repository ?? SettingsRepository(),
        _subscriptions = subscriptions ?? SubscriptionClient();

  final VpnService _service;
  final SettingsRepository _repository;
  final SubscriptionClient _subscriptions;

  AppSettings appSettings = const AppSettings();
  AppUserMode userMode = AppUserMode.simple;
  LocationMode locationMode = LocationMode.auto;
  ServerLocation selectedLocation = ServerLocation.auto;
  ProSettings proSettings = const ProSettings();
  UserAccount account = UserAccount.empty();

  VpnConnectionState connectionState = VpnConnectionState.disconnected;
  String? errorMessage;
  Duration sessionDuration = Duration.zero;
  Map<String, int>? lastProbeResults;
  bool isProbing = false;
  bool isHydrated = false;
  bool isRefreshingServers = false;
  bool isCheckoutLoading = false;
  bool showTrialWelcome = false;
  SubscriptionLinkState linkState = SubscriptionLinkState.missing;
  String? subscriptionUrl;
  String? linkError;
  String? oneTimeUrl;
  String? oneTimeNumber;
  String? restoreChannel;
  SubscriptionProfile? profile;
  TunnelNode? connectedNode;
  String _savedLocationId = ServerLocation.auto.id;

  Timer? _sessionTimer;
  DateTime? _connectedAt;

  AppStrings get strings => AppStrings(appSettings.language);

  bool get isBusy =>
      connectionState == VpnConnectionState.connecting ||
      connectionState == VpnConnectionState.disconnecting;

  bool get isConnected => connectionState == VpnConnectionState.connected;

  bool get hasAccess =>
      linkState == SubscriptionLinkState.ready && account.hasAccess;

  bool get needsLink =>
      linkState == SubscriptionLinkState.missing ||
      linkState == SubscriptionLinkState.failed;

  List<ServerLocation> get locations {
    final seen = <String>{};
    final list = <ServerLocation>[ServerLocation.auto];
    for (final node in profile?.nodes ?? const <TunnelNode>[]) {
      if (node.kind == TunnelKind.hy2) continue;
      if (!seen.add(node.countryId)) continue;
      list.add(
        ServerLocation(
          id: node.countryId,
          countryCode: node.countryCode,
          nameRu: node.countryName,
        ),
      );
    }
    return list;
  }

  bool get canUseProNetworkTools => hasAccess;

  ServerLocation get effectiveLocation {
    final activeId = connectedNode?.countryId;
    if (activeId != null) {
      return locations.firstWhere(
        (item) => item.id == activeId,
        orElse: () => selectedLocation,
      );
    }
    if (locationMode == LocationMode.auto || selectedLocation.isAuto) {
      return ServerLocation.auto;
    }
    return locations.firstWhere(
      (item) => item.id == selectedLocation.id,
      orElse: () => ServerLocation.auto,
    );
  }

  String get statusLine {
    final s = strings;
    switch (connectionState) {
      case VpnConnectionState.disconnected:
        return s.notConnected;
      case VpnConnectionState.connecting:
        return s.connectingStatus;
      case VpnConnectionState.connected:
        return s.connectedTo(connectedNode?.countryName ?? effectiveLocation.nameRu);
      case VpnConnectionState.disconnecting:
        return s.disconnectingStatus;
      case VpnConnectionState.error:
        return errorMessage ?? s.connectionError;
    }
  }

  String get sessionLabel {
    final h = sessionDuration.inHours.toString().padLeft(2, '0');
    final m = (sessionDuration.inMinutes % 60).toString().padLeft(2, '0');
    final s = (sessionDuration.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String planLabel(SubscriptionPlan plan) {
    final s = strings;
    return switch (plan) {
      SubscriptionPlan.expired => s.planExpired,
      _ => s.planName,
    };
  }

  Future<void> hydrate() async {
    appSettings = await _repository.loadAppSettings();
    proSettings = await _repository.loadProSettings();
    final session = await _repository.loadSessionPrefs();
    userMode = session.mode;
    locationMode = session.locationMode;

    _savedLocationId = session.locationId;
    if (!appSettings.rememberLastCountry) {
      selectedLocation = ServerLocation.auto;
      locationMode = LocationMode.auto;
    }

    subscriptionUrl = await _repository.loadSubscriptionUrl();
    if (subscriptionUrl == null) {
      linkState = SubscriptionLinkState.missing;
    } else {
      await reloadSubscription();
    }

    _restoreSavedLocation();
    showTrialWelcome = false;
    isHydrated = true;
    notifyListeners();
  }

  void _restoreSavedLocation() {
    selectedLocation = locations.firstWhere(
      (item) => item.id == _savedLocationId,
      orElse: () => ServerLocation.auto,
    );
    if (selectedLocation.isAuto) locationMode = LocationMode.auto;
  }

  Future<void> forgetSubscriptionLink() async {
    if (isConnected) await disconnect();
    subscriptionUrl = null;
    profile = null;
    linkError = null;
    connectedNode = null;
    linkState = SubscriptionLinkState.missing;
    await _repository.saveSubscriptionUrl('');
    notifyListeners();
  }

  void clearOneTimeLink() {
    oneTimeUrl = null;
    oneTimeNumber = null;
    notifyListeners();
  }

  String? _restoreChannelFor(String raw) {
    final typed = raw.trim();
    if (typed.contains('@') && !typed.startsWith('@') && !typed.contains('://')) {
      return 'email';
    }
    if (!typed.contains('://')) return 'telegram';
    return null;
  }

  Future<void> submitSubscriptionLink(String raw) async {
    restoreChannel = null;
    final text = raw.trim();
    final remote = subscriptionAddress(text);
    if (looksLikeShare(text) || remote != null) {
      subscriptionUrl = looksLikeShare(text) ? text : remote.toString();
      await _repository.saveSubscriptionUrl(subscriptionUrl!);
      await reloadSubscription();
      return;
    }
    linkState = SubscriptionLinkState.loading;
    linkError = null;
    notifyListeners();
    try {
      final result = await _subscriptions.startWithContact(raw);
      if (result.error != null) {
        linkError = result.error;
        if (result.error!.contains('уже')) {
          restoreChannel = _restoreChannelFor(raw);
        }
        linkState = SubscriptionLinkState.failed;
        notifyListeners();
        return;
      }
      if (!result.created || result.url == null) {
        restoreChannel = result.channel == 'email' || result.channel == 'telegram'
            ? result.channel
            : _restoreChannelFor(raw);
        linkError = strings.contactTaken(result.publicId);
        linkState = SubscriptionLinkState.failed;
        notifyListeners();
        return;
      }
      oneTimeUrl = result.url.toString();
      oneTimeNumber = result.publicId;
      subscriptionUrl = oneTimeUrl;
      await _repository.saveSubscriptionUrl(subscriptionUrl!);
      await reloadSubscription();
    } catch (_) {
      linkError = strings.linkOpenFailed;
      linkState = SubscriptionLinkState.failed;
      notifyListeners();
    }
  }

  Future<void> reloadSubscription() async {
    final url = subscriptionUrl;
    if (url == null) {
      linkState = SubscriptionLinkState.missing;
      profile = null;
      notifyListeners();
      return;
    }
    linkState = SubscriptionLinkState.loading;
    linkError = null;
    notifyListeners();
    try {
      if (looksLikeShare(url)) {
        profile = parseSubscription(url);
      } else {
        final fetched = await _subscriptions.fetch(Uri.parse(url));
        profile = parseSubscription(fetched.body, userinfo: fetched.userinfo);
      }
      _applyProfile();
      _restoreSavedLocation();
    } on FormatException {
      profile = null;
      linkError = strings.emptySubscription;
      linkState = SubscriptionLinkState.failed;
    } on SubscriptionRejected {
      profile = null;
      linkState = SubscriptionLinkState.expired;
      account = account.copyWith(
        plan: SubscriptionPlan.expired,
        accessExpiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
    } catch (_) {
      profile = null;
      linkError = strings.linkOpenFailed;
      linkState = SubscriptionLinkState.failed;
    }
    notifyListeners();
  }

  void _applyProfile() {
    final current = profile;
    if (current == null) return;
    if (current.isExpired) {
      linkState = SubscriptionLinkState.expired;
      account = account.copyWith(
        plan: SubscriptionPlan.expired,
        accessExpiresAt: current.expiresAt,
        displayName: 'K-Pax',
      );
      return;
    }
    linkState = SubscriptionLinkState.ready;
    account = account.copyWith(
      plan: SubscriptionPlan.trial,
      accessExpiresAt: current.expiresAt ?? DateTime.now().add(const Duration(days: 3650)),
      displayName: 'K-Pax',
    );
  }

  Future<void> maybeAutoConnect() async {
    if (!appSettings.autoConnectOnLaunch) return;
    if (!hasAccess) return;
    if (isConnected || isBusy) return;
    await connect();
  }

  void dismissTrialWelcome() {
    showTrialWelcome = false;
    notifyListeners();
  }

  Future<void> updateAppSettings(AppSettings settings) async {
    appSettings = settings;
    notifyListeners();
    await _repository.saveAppSettings(settings);
  }

  Future<void> setUserMode(AppUserMode mode) async {
    if (userMode == mode) return;
    userMode = mode;
    notifyListeners();
    await _persistSession();
  }

  Future<void> setLocationMode(LocationMode mode) async {
    if (locationMode == mode) return;
    locationMode = mode;
    if (mode == LocationMode.auto) {
      selectedLocation = ServerLocation.auto;
    }
    notifyListeners();
    await _persistSession();
  }

  Future<void> selectLocation(ServerLocation location) async {
    selectedLocation = location;
    locationMode = location.isAuto ? LocationMode.auto : LocationMode.country;
    notifyListeners();
    await _persistSession();
  }

  Future<void> updateProSettings(ProSettings settings) async {
    proSettings = settings;
    notifyListeners();
    await _repository.saveProSettings(settings);
  }

  Future<void> refreshServers() async {
    if (isRefreshingServers) return;
    isRefreshingServers = true;
    notifyListeners();
    await reloadSubscription();
    isRefreshingServers = false;
    notifyListeners();
  }

  /// Stub checkout until real payment provider is wired.
  Future<bool> simulatePurchase(SubscriptionPlan plan) async {
    if (plan != SubscriptionPlan.basic && plan != SubscriptionPlan.pro) {
      return false;
    }
    if (isCheckoutLoading) return false;
    isCheckoutLoading = true;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final now = DateTime.now();
    final base = account.accessExpiresAt.isAfter(now)
        ? account.accessExpiresAt
        : now;
    account = account.copyWith(
      plan: plan,
      accessExpiresAt: base.add(const Duration(days: 30)),
    );
    isCheckoutLoading = false;
    notifyListeners();
    await _repository.saveAccount(account);
    return true;
  }

  Future<bool> restorePurchasesStub() async {
    isCheckoutLoading = true;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 900));
    isCheckoutLoading = false;
    notifyListeners();
    return hasAccess;
  }

  /// Demo: friend converted → +30 days, capped yearly.
  Future<bool> simulateReferralConversion() async {
    if (account.referralMonthsEarned >= UserAccount.referralYearlyCap) {
      return false;
    }
    final base = account.accessExpiresAt.isAfter(DateTime.now())
        ? account.accessExpiresAt
        : DateTime.now();
    final nextPlan = account.plan == SubscriptionPlan.expired
        ? SubscriptionPlan.basic
        : account.plan;
    account = account.copyWith(
      plan: nextPlan == SubscriptionPlan.trial ? SubscriptionPlan.basic : nextPlan,
      accessExpiresAt: base.add(const Duration(days: 30)),
      referralMonthsEarned: account.referralMonthsEarned + 1,
      friendsConverted: account.friendsConverted + 1,
    );
    notifyListeners();
    await _repository.saveAccount(account);
    return true;
  }

  Future<void> resetToFreshTrialForDemo() async {
    if (isConnected) await disconnect();
    account = UserAccount.freshTrial();
    showTrialWelcome = true;
    notifyListeners();
    await _repository.saveAccount(account);
  }

  Future<void> expireAccessForDemo() async {
    if (isConnected) await disconnect();
    account = account.copyWith(
      plan: SubscriptionPlan.expired,
      accessExpiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
    );
    notifyListeners();
    await _repository.saveAccount(account);
  }

  Future<void> toggleConnection() async {
    if (isBusy) return;
    if (isConnected) {
      await disconnect();
    } else {
      await connect();
    }
  }

  Future<void> _start(TunnelNode node) async {
    connectedNode = node;
    await _service.connect(
      location: effectiveLocation,
      settings: proSettings,
      appSettings: appSettings,
      node: node,
    );
  }

  Future<TunnelNode> _selectNode() async {
    final nodes = profile?.nodes ?? const <TunnelNode>[];
    final countryId = locationMode == LocationMode.auto || selectedLocation.isAuto
        ? null
        : selectedLocation.id;
    Iterable<TunnelNode> pool = nodes;
    if (countryId != null) {
      pool = pool.where((node) => node.countryId == countryId);
    }
    if (proSettings.protocol == TunnelProtocol.hysteria2) {
      final hy2 = pool.where((node) => node.kind == TunnelKind.hy2).toList();
      if (hy2.isNotEmpty) return hy2.first;
    }
    var primary = pool.where((node) => node.kind == TunnelKind.reality).toList();
    if (primary.isEmpty) {
      primary = pool.where((node) => node.kind != TunnelKind.hy2).toList();
    }
    if (primary.isEmpty) {
      throw StateError('no node');
    }
    if (primary.length == 1 || countryId != null) return primary.first;
    TunnelNode best = primary.first;
    var bestMs = 1 << 30;
    for (final node in primary) {
      final ms = await measureTcp(node.host, node.port);
      if (ms != null && ms < bestMs) {
        best = node;
        bestMs = ms;
      }
    }
    return best;
  }

  TunnelNode? _spareFor(TunnelNode node) {
    for (final candidate in profile?.nodes ?? const <TunnelNode>[]) {
      if (candidate.countryId == node.countryId && candidate.kind == TunnelKind.grpc) {
        return candidate;
      }
    }
    return null;
  }

  /// Returns false when paywall should be shown.
  Future<bool> connect() async {
    if (isBusy || isConnected) return true;
    if (!hasAccess) {
      errorMessage = strings.subscriptionRequired;
      notifyListeners();
      return false;
    }

    connectionState = VpnConnectionState.connecting;
    errorMessage = null;
    notifyListeners();

    TunnelNode node;
    try {
      node = await _selectNode();
    } catch (_) {
      connectionState = VpnConnectionState.error;
      errorMessage = strings.connectFailed;
      notifyListeners();
      return true;
    }

    try {
      await _start(node);
      connectionState = VpnConnectionState.connected;
      _connectedAt = DateTime.now();
      sessionDuration = Duration.zero;
      _sessionTimer?.cancel();
      _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_connectedAt == null) return;
        sessionDuration = DateTime.now().difference(_connectedAt!);
        notifyListeners();
      });
    } catch (e) {
      final spare = _spareFor(node);
      if (spare != null && proSettings.protocolFallback) {
        try {
          await _service.disconnect();
        } catch (_) {}
        try {
          await _start(spare);
          connectionState = VpnConnectionState.connected;
          _connectedAt = DateTime.now();
          sessionDuration = Duration.zero;
          _sessionTimer?.cancel();
          _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
            if (_connectedAt == null) return;
            sessionDuration = DateTime.now().difference(_connectedAt!);
            notifyListeners();
          });
          notifyListeners();
          return true;
        } catch (_) {}
      }
      connectionState = VpnConnectionState.error;
      errorMessage = strings.connectFailed;
    }
    notifyListeners();
    return true;
  }

  Future<void> disconnect() async {
    if (isBusy || connectionState == VpnConnectionState.disconnected) return;
    connectionState = VpnConnectionState.disconnecting;
    notifyListeners();

    try {
      await _service.disconnect();
    } finally {
      _sessionTimer?.cancel();
      _sessionTimer = null;
      _connectedAt = null;
      sessionDuration = Duration.zero;
      connectedNode = null;
      connectionState = VpnConnectionState.disconnected;
      notifyListeners();
    }
  }

  Future<void> runNodeProbe() async {
    if (isProbing) return;
    isProbing = true;
    lastProbeResults = null;
    notifyListeners();
    try {
      lastProbeResults = await _service.probeNodes();
    } finally {
      isProbing = false;
      notifyListeners();
    }
  }

  Future<void> _persistSession() async {
    final locationId = appSettings.rememberLastCountry
        ? selectedLocation.id
        : ServerLocation.auto.id;
    await _repository.saveSessionPrefs(
      mode: userMode,
      locationMode: locationMode,
      locationId: locationId,
    );
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    super.dispose();
  }
}
