import 'dart:async';
import 'dart:io';

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
import 'package:pulse_vpn/core/services/windows_platform.dart';

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
  List<SavedSubscription> subscriptions = const [];
  Uri? providerWebPage;
  TunnelNode? connectedNode;
  String _savedLocationId = ServerLocation.auto.id;

  Timer? _sessionTimer;
  DateTime? _connectedAt;
  StreamSubscription<String>? _vpnStatusSub;
  StreamSubscription<TunnelSpeed>? _trafficSub;
  int uploadBytesPerSec = 0;
  int downloadBytesPerSec = 0;
  int _reconnectBudget = 0;

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

  /// Payment, referrals and the account number exist only for K-Pax links.
  bool get isKPaxSubscription {
    final url = subscriptionUrl;
    return url != null && kPaxSubscriptionUri(url) != null;
  }

  /// Other providers may give a link without an end date.
  bool get hasExpiry => profile?.expiresAt != null;

  String get subscriptionName {
    final url = subscriptionUrl;
    if (url == null) return '';
    return subscriptionLabel(
      subscriptions.firstWhere(
        (item) => item.url == url,
        orElse: () => SavedSubscription(url: url),
      ),
    );
  }

  String subscriptionLabel(SavedSubscription item) {
    if (kPaxSubscriptionUri(item.url) != null) return 'K-Pax';
    if (item.name.isNotEmpty) return item.name;
    if (looksLikeShare(item.url)) return strings.ownServer;
    final host = Uri.tryParse(item.url)?.host ?? '';
    return host.isEmpty ? strings.subscription : host;
  }

  List<ServerLocation> get locations {
    final seen = <String>{};
    final list = <ServerLocation>[ServerLocation.auto];
    // Any line defines a country: other providers may offer only Hy2 or only CDN lines.
    for (final node in profile?.nodes ?? const <TunnelNode>[]) {
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
        return errorMessage ?? s.notConnected;
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
      _ => subscriptionName.isEmpty ? s.planName : subscriptionName,
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

    subscriptions = await _repository.loadSubscriptions();
    subscriptionUrl = await _repository.loadSubscriptionUrl();
    if (subscriptionUrl == null && subscriptions.isNotEmpty) {
      subscriptionUrl = subscriptions.first.url;
    }
    if (subscriptionUrl == null) {
      linkState = SubscriptionLinkState.missing;
    } else {
      await reloadSubscription();
    }

    _restoreSavedLocation();
    _listenVpnStatus();
    if (!kIsWeb && Platform.isWindows) {
      await WindowsFirewall.clear();
      if (appSettings.launchAtLogin) {
        await WindowsStartup.setEnabled(true);
      }
    }
    showTrialWelcome = false;
    isHydrated = true;
    notifyListeners();
  }

  void _listenVpnStatus() {
    _vpnStatusSub ??= _service.statusStream.listen((status) {
      unawaited(_onVpnStatus(status));
    });
    _trafficSub ??= _service.trafficStream.listen((speed) {
      if (!isConnected) return;
      uploadBytesPerSec = speed.upBytesPerSec;
      downloadBytesPerSec = speed.downBytesPerSec;
      notifyListeners();
    });
  }

  Future<void> _onVpnStatus(String status) async {
    if (status != 'Stopped') return;
    if (connectionState != VpnConnectionState.connected) return;
    _sessionTimer?.cancel();
    _sessionTimer = null;
    _connectedAt = null;
    sessionDuration = Duration.zero;
    uploadBytesPerSec = 0;
    downloadBytesPerSec = 0;
    connectedNode = null;
    connectionState = VpnConnectionState.disconnected;
    final block = proSettings.killSwitch;
    final retry = proSettings.reconnectPolicy == ReconnectPolicy.aggressive &&
        _reconnectBudget > 0;
    errorMessage = block ? strings.killSwitchHeld : null;
    notifyListeners();
    if (block) await WindowsFirewall.blockOutboundExceptApp();
    if (!retry) return;
    _reconnectBudget -= 1;
    await Future<void>.delayed(const Duration(seconds: 2));
    if (connectionState != VpnConnectionState.disconnected) return;
    await connect(userInitiated: false);
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
    final url = subscriptionUrl;
    if (url != null) {
      subscriptions = subscriptions.where((item) => item.url != url).toList();
      await _repository.saveSubscriptions(subscriptions);
    }
    subscriptionUrl = null;
    profile = null;
    providerWebPage = null;
    linkError = null;
    connectedNode = null;
    linkState = SubscriptionLinkState.missing;
    await _repository.saveSubscriptionUrl('');
    notifyListeners();
  }

  /// Saves the link if it is new and makes it the active one.
  Future<void> _activate(String url) async {
    if (connectionState != VpnConnectionState.disconnected) await disconnect();
    if (subscriptions.every((item) => item.url != url)) {
      subscriptions = [...subscriptions, SavedSubscription(url: url)];
      await _repository.saveSubscriptions(subscriptions);
    }
    if (subscriptionUrl != url) {
      profile = null;
      providerWebPage = null;
      connectedNode = null;
      lastProbeResults = null;
    }
    subscriptionUrl = url;
    await _repository.saveSubscriptionUrl(url);
    await reloadSubscription();
  }

  Future<void> switchSubscription(String url) async {
    if (url == subscriptionUrl || isBusy) return;
    await _activate(url);
  }

  Future<void> removeSubscription(String url) async {
    if (url == subscriptionUrl) {
      await forgetSubscriptionLink();
      if (subscriptions.isNotEmpty) await _activate(subscriptions.first.url);
      return;
    }
    subscriptions = subscriptions.where((item) => item.url != url).toList();
    await _repository.saveSubscriptions(subscriptions);
    notifyListeners();
  }

  Future<void> _rename(String url, String name) async {
    final index = subscriptions.indexWhere((item) => item.url == url);
    if (index < 0 || subscriptions[index].name == name) return;
    subscriptions = [...subscriptions]..[index] = subscriptions[index].named(name);
    await _repository.saveSubscriptions(subscriptions);
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
      await _activate(looksLikeShare(text) ? text : remote.toString());
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
      await _activate(oneTimeUrl!);
      await _rememberAccountNumber(result.publicId);
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
    if (profile == null) {
      linkState = SubscriptionLinkState.loading;
      linkError = null;
      notifyListeners();
    }
    final kept = profile;
    try {
      if (looksLikeShare(url)) {
        profile = parseSubscription(url);
      } else {
        final fetched = await _subscriptions.fetch(Uri.parse(url));
        if (url != subscriptionUrl) return;
        profile = parseSubscription(fetched.body, userinfo: fetched.userinfo);
        providerWebPage = fetched.webPage;
        if (fetched.title != null) await _rename(url, fetched.title!);
        await _rememberAccountNumber(fetched.publicId);
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
      if (kept == null) {
        profile = null;
        linkError = strings.linkOpenFailed;
        linkState = SubscriptionLinkState.failed;
      } else {
        profile = kept;
        linkState = SubscriptionLinkState.ready;
      }
    }
    notifyListeners();
  }

  Future<void> _rememberAccountNumber(String? id) async {
    final number = id?.trim() ?? '';
    if (!isKPaxSubscription ||
        !RegExp(r'^KP-\d{5,8}$').hasMatch(number) ||
        account.userId == number) {
      return;
    }
    account = account.copyWith(userId: number);
    notifyListeners();
    await _repository.saveAccount(account);
  }

  void _applyProfile() {
    final current = profile;
    if (current == null) return;
    if (current.isExpired) {
      linkState = SubscriptionLinkState.expired;
      account = account.copyWith(
        plan: SubscriptionPlan.expired,
        accessExpiresAt: current.expiresAt,
        displayName: subscriptionName,
      );
      return;
    }
    linkState = SubscriptionLinkState.ready;
    account = account.copyWith(
      plan: SubscriptionPlan.trial,
      accessExpiresAt: current.expiresAt ?? DateTime.now().add(const Duration(days: 3650)),
      displayName: subscriptionName,
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
    final launchChanged = settings.launchAtLogin != appSettings.launchAtLogin;
    appSettings = settings;
    notifyListeners();
    await _repository.saveAppSettings(settings);
    if (launchChanged) await WindowsStartup.setEnabled(settings.launchAtLogin);
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
    final lifted = proSettings.killSwitch && !settings.killSwitch;
    proSettings = settings;
    notifyListeners();
    await _repository.saveProSettings(settings);
    if (lifted) await WindowsFirewall.clear();
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

  List<TunnelKind> _kindOrder() {
    const tcp = [TunnelKind.reality, TunnelKind.grpc, TunnelKind.message];
    const udpFirst = [
      TunnelKind.hy2,
      TunnelKind.tuic,
      TunnelKind.reality,
      TunnelKind.grpc,
      TunnelKind.message,
    ];
    const standard = [
      TunnelKind.reality,
      TunnelKind.grpc,
      TunnelKind.hy2,
      TunnelKind.tuic,
      TunnelKind.message,
    ];
    final chain = switch (proSettings.bypassMode) {
      BypassMode.tcpOnly => tcp,
      BypassMode.udpPrefer => udpFirst,
      BypassMode.auto => standard,
    };
    final forced = switch (proSettings.protocol) {
      TunnelProtocol.auto => null,
      TunnelProtocol.vlessReality => TunnelKind.reality,
      TunnelProtocol.hysteria2 => TunnelKind.hy2,
      TunnelProtocol.grpc => TunnelKind.grpc,
      TunnelProtocol.tuic => TunnelKind.tuic,
      TunnelProtocol.message => TunnelKind.message,
    };
    if (forced == null) return chain;
    if (!proSettings.protocolFallback) return [forced];
    return [forced, ...chain.where((kind) => kind != forced)];
  }

  Future<TunnelNode> _selectNode() async {
    final nodes = profile?.nodes ?? const <TunnelNode>[];
    final countryId = locationMode == LocationMode.auto || selectedLocation.isAuto
        ? null
        : selectedLocation.id;
    final order = _kindOrder();
    final pool = nodes
        .where(
          (node) =>
              (countryId == null || node.countryId == countryId) &&
              order.contains(node.kind),
        )
        .toList();
    if (pool.isEmpty) {
      throw StateError('no node');
    }
    return _autoServerAndType(pool, order);
  }

  /// Fastest reachable server. Message lines stay out of the race unless
  /// they are the only allowed profile.
  Future<TunnelNode> _autoServerAndType(
    List<TunnelNode> pool,
    List<TunnelKind> order,
  ) async {
    final messagesOnly = pool.every((node) => node.kind == TunnelKind.message);
    final race = messagesOnly
        ? pool
        : pool.where((node) => node.kind != TunnelKind.message).toList();
    final source = race.isEmpty ? pool : race;
    // Protocol order wins first; among servers of that protocol the fastest one is used.
    for (final kind in order) {
      final same = source.where((node) => node.kind == kind).toList();
      if (same.isEmpty) continue;
      return _fastest(same);
    }
    return _preferType(pool, order);
  }

  /// UDP lines (Hy2, TUIC) cannot be timed over TCP; they keep subscription order.
  Future<TunnelNode> _fastest(List<TunnelNode> nodes) async {
    if (nodes.length == 1) return nodes.first;
    if (nodes.first.kind == TunnelKind.hy2 || nodes.first.kind == TunnelKind.tuic) {
      return nodes.first;
    }
    final seen = <String>{};
    TunnelNode? best;
    var bestMs = 1 << 30;
    for (final node in nodes) {
      final port = node.port == 0 ? 443 : node.port;
      if (!seen.add('${node.host}:$port')) continue;
      final ms = await measureTcp(node.host, port);
      if (ms != null && ms < bestMs) {
        best = node;
        bestMs = ms;
      }
    }
    return best ?? nodes.first;
  }

  TunnelNode _preferType(List<TunnelNode> nodes, List<TunnelKind> order) {
    for (final kind in order) {
      for (final node in nodes) {
        if (node.kind == kind) return node;
      }
    }
    return nodes.first;
  }

  TunnelNode? _spareFor(TunnelNode node) {
    final order = _kindOrder();
    final start = order.indexOf(node.kind);
    if (start < 0) return null;
    for (final kind in order.skip(start + 1)) {
      for (final candidate in profile?.nodes ?? const <TunnelNode>[]) {
        if (candidate.countryId == node.countryId && candidate.kind == kind) {
          return candidate;
        }
      }
    }
    return null;
  }

  String _failureText(Object error) {
    final raw = error is StateError ? error.message : '';
    final detail = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (detail.isEmpty || detail == 'no node') return strings.connectFailed;
    final short = detail.length > 180 ? detail.substring(0, 180) : detail;
    return '${strings.connectFailed}\n$short';
  }

  /// Returns false when paywall should be shown.
  Future<bool> connect({bool userInitiated = true}) async {
    if (isBusy || isConnected) return true;
    if (!hasAccess) {
      errorMessage = isKPaxSubscription || needsLink
          ? strings.subscriptionRequired
          : strings.providerExpired;
      notifyListeners();
      return false;
    }

    if (userInitiated) {
      _reconnectBudget =
          proSettings.reconnectPolicy == ReconnectPolicy.aggressive ? 5 : 0;
    }
    connectionState = VpnConnectionState.connecting;
    errorMessage = null;
    notifyListeners();

    TunnelNode node;
    try {
      node = await _selectNode();
    } catch (error) {
      connectionState = VpnConnectionState.error;
      errorMessage = _failureText(error);
      notifyListeners();
      return true;
    }

    try {
      await _start(node);
      await WindowsFirewall.clear();
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
      var spare = proSettings.protocolFallback ? _spareFor(node) : null;
      while (spare != null) {
        try {
          await _service.disconnect();
        } catch (_) {}
        try {
          await _start(spare);
          await WindowsFirewall.clear();
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
        } catch (_) {
          spare = _spareFor(spare);
        }
      }
      connectionState = VpnConnectionState.error;
      errorMessage = _failureText(e);
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
      await WindowsFirewall.clear();
    } finally {
      _sessionTimer?.cancel();
      _sessionTimer = null;
      _connectedAt = null;
      sessionDuration = Duration.zero;
      connectedNode = null;
      uploadBytesPerSec = 0;
      downloadBytesPerSec = 0;
      errorMessage = null;
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
      final byCountry = <String, TunnelNode>{};
      for (final node in profile?.nodes ?? const <TunnelNode>[]) {
        if (node.kind == TunnelKind.message) continue;
        final current = byCountry[node.countryId];
        if (current == null || _probeRank(node.kind) < _probeRank(current.kind)) {
          byCountry[node.countryId] = node;
        }
      }
      final results = <String, int>{};
      for (final node in byCountry.values) {
        final port = node.port == 0 ? 443 : node.port;
        results[node.countryName] = await measureTcp(node.host, port) ?? -1;
      }
      lastProbeResults = results;
    } finally {
      isProbing = false;
      notifyListeners();
    }
  }

  int _probeRank(TunnelKind kind) => switch (kind) {
        TunnelKind.reality => 0,
        TunnelKind.grpc => 1,
        TunnelKind.hy2 => 2,
        TunnelKind.tuic => 3,
        TunnelKind.message => 4,
      };

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
    _vpnStatusSub?.cancel();
    _trafficSub?.cancel();
    super.dispose();
  }
}
