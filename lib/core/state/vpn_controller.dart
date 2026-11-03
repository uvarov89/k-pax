import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:pulse_vpn/app/brand/app_brand.dart';
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
  SubscriptionLinkState linkState = SubscriptionLinkState.missing;
  String? subscriptionUrl;
  String? linkError;
  String? oneTimeUrl;
  String? oneTimeNumber;
  String? loginSession;
  String? loginChannel;
  String? loginBotUrl;
  String? loginHint;
  SubscriptionProfile? profile;
  List<SavedSubscription> subscriptions = const [];
  Uri? providerWebPage;
  TunnelNode? connectedNode;
  String _savedLocationId = ServerLocation.auto.id;

  Timer? _sessionTimer;
  Timer? _loginPoll;
  DateTime? _loginStartedAt;
  DateTime? _connectedAt;
  StreamSubscription<String>? _vpnStatusSub;
  StreamSubscription<TunnelSpeed>? _trafficSub;
  int uploadBytesPerSec = 0;
  int downloadBytesPerSec = 0;
  int _reconnectBudget = 0;
  bool _wantConnected = false;
  bool _reconnectInFlight = false;
  UiFlash? _uiFlash;
  String? _dismissedHomeNoticeId;

  AppStrings get strings => AppStrings(appSettings.language);

  /// Soft prompt after server-side Reality SNI rotation (K-Pax only).
  bool get showRefreshSubscriptionNotice =>
      isKPaxSubscription &&
      hasAccess &&
      !isLoginWaiting &&
      _dismissedHomeNoticeId != SettingsRepository.homeRefreshNoticeId;

  bool get isBusy =>
      connectionState == VpnConnectionState.connecting ||
      connectionState == VpnConnectionState.disconnecting;

  bool get isConnected => connectionState == VpnConnectionState.connected;

  bool get hasAccess =>
      linkState == SubscriptionLinkState.ready && account.hasAccess;

  bool get needsLink =>
      linkState == SubscriptionLinkState.missing ||
      linkState == SubscriptionLinkState.failed;

  bool get isLoginWaiting =>
      loginSession != null && linkState == SubscriptionLinkState.loading;

  /// Payment, referrals and the account number exist only for owned-brand links.
  bool get isKPaxSubscription {
    final url = subscriptionUrl;
    return url != null && brandSubscriptionUri(url) != null;
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
    if (brandSubscriptionUri(item.url) != null) return AppBrand.current.appName;
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
        return errorMessage == s.reconnectingStatus
            ? s.reconnectingStatus
            : s.connectingStatus;
      case VpnConnectionState.connected:
        return s.connectedTo(connectedNode?.countryName ?? effectiveLocation.nameRu);
      case VpnConnectionState.disconnecting:
        return s.disconnectingStatus;
      case VpnConnectionState.error:
        return errorMessage ?? s.connectionError;
    }
  }

  /// One-shot UI hint for Home (snackbar / open account). Call [takeUiFlash].
  UiFlash? takeUiFlash() {
    final flash = _uiFlash;
    _uiFlash = null;
    return flash;
  }

  void _emitFlash(String message, {bool openAccount = false}) {
    _uiFlash = UiFlash(message: message, openAccount: openAccount);
    notifyListeners();
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
    _dismissedHomeNoticeId = await _repository.loadDismissedHomeNoticeId();
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
    isHydrated = true;
    notifyListeners();
    await _resumePendingLogin();
  }

  Future<void> _resumePendingLogin() async {
    if (subscriptionUrl != null) {
      await _repository.clearPendingLogin();
      return;
    }
    final pending = await _repository.loadPendingLogin();
    if (pending == null) return;
    final started = DateTime.fromMillisecondsSinceEpoch(pending.startedMs);
    if (DateTime.now().difference(started) > const Duration(minutes: 30)) {
      await _repository.clearPendingLogin();
      return;
    }
    loginSession = pending.session;
    loginChannel = pending.channel.isEmpty ? null : pending.channel;
    loginBotUrl = (pending.botUrl ?? '').isEmpty ? null : pending.botUrl;
    loginHint = (pending.hint ?? '').isEmpty ? null : pending.hint;
    oneTimeNumber = (pending.publicId ?? '').isEmpty ? null : pending.publicId;
    _loginStartedAt = started;
    linkState = SubscriptionLinkState.loading;
    linkError = null;
    notifyListeners();
    _loginPoll?.cancel();
    _loginPoll = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_pollLoginOnce());
    });
    await _pollLoginOnce();
  }

  Future<void> _persistPendingLogin() async {
    final session = loginSession;
    final started = _loginStartedAt;
    if (session == null || session.isEmpty || started == null) {
      await _repository.clearPendingLogin();
      return;
    }
    await _repository.savePendingLogin(
      session: session,
      channel: loginChannel ?? '',
      botUrl: loginBotUrl,
      hint: loginHint,
      publicId: oneTimeNumber,
      startedMs: started.millisecondsSinceEpoch,
    );
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
    final normalized = status.trim().toLowerCase();
    if (normalized != 'stopped') return;
    if (connectionState != VpnConnectionState.connected) return;
    if (_reconnectInFlight) return;

    final lastNode = connectedNode;
    _sessionTimer?.cancel();
    _sessionTimer = null;
    _connectedAt = null;
    sessionDuration = Duration.zero;
    uploadBytesPerSec = 0;
    downloadBytesPerSec = 0;

    final block = proSettings.killSwitch;
    final shouldRetry = _wantConnected && _reconnectBudget > 0;
    if (!shouldRetry) {
      connectedNode = null;
      connectionState = VpnConnectionState.disconnected;
      errorMessage = block ? strings.killSwitchHeld : null;
      notifyListeners();
      if (block) await WindowsFirewall.blockOutboundExceptApp();
      return;
    }

    if (block) await WindowsFirewall.blockOutboundExceptApp();
    await _attemptReconnect(lastNode);
  }

  Future<void> _attemptReconnect(TunnelNode? lastNode) async {
    if (!_wantConnected || _reconnectBudget <= 0 || _reconnectInFlight) return;
    final block = proSettings.killSwitch;
    _reconnectBudget -= 1;
    _reconnectInFlight = true;
    connectionState = VpnConnectionState.connecting;
    errorMessage = strings.reconnectingStatus;
    notifyListeners();

    await Future<void>.delayed(const Duration(seconds: 2));
    if (!_wantConnected) {
      _reconnectInFlight = false;
      connectionState = VpnConnectionState.disconnected;
      errorMessage = null;
      connectedNode = null;
      notifyListeners();
      return;
    }

    try {
      var node = lastNode;
      node ??= await _selectNode();
      try {
        await _start(node);
      } catch (_) {
        final spare =
            proSettings.protocolFallback ? _spareFor(node) : null;
        if (spare == null) rethrow;
        try {
          await _service.disconnect();
        } catch (_) {}
        await _start(spare);
        node = spare;
      }
      await WindowsFirewall.clear();
      connectedNode = node;
      connectionState = VpnConnectionState.connected;
      errorMessage = null;
      _connectedAt = DateTime.now();
      sessionDuration = Duration.zero;
      _sessionTimer?.cancel();
      _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_connectedAt == null) return;
        sessionDuration = DateTime.now().difference(_connectedAt!);
        notifyListeners();
      });
    } catch (_) {
      connectedNode = null;
      if (_wantConnected && _reconnectBudget > 0) {
        connectionState = VpnConnectionState.disconnected;
        errorMessage = strings.reconnectingStatus;
        notifyListeners();
        _reconnectInFlight = false;
        unawaited(_attemptReconnect(lastNode));
        return;
      }
      connectionState = VpnConnectionState.error;
      errorMessage = block ? strings.killSwitchHeld : strings.reconnectFailed;
      notifyListeners();
    } finally {
      _reconnectInFlight = false;
    }
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

  void cancelLogin() {
    _loginPoll?.cancel();
    _loginPoll = null;
    _loginStartedAt = null;
    loginSession = null;
    loginChannel = null;
    loginBotUrl = null;
    loginHint = null;
    unawaited(_repository.clearPendingLogin());
    if (linkState == SubscriptionLinkState.loading && subscriptionUrl == null) {
      linkState = SubscriptionLinkState.missing;
    }
    notifyListeners();
  }

  Future<void> submitSubscriptionLink(String raw) async {
    cancelLogin();
    final text = normalizeContactInput(raw);
    final kpax = kPaxSubscriptionUri(text);
    if (kpax != null) {
      await _activate(kpax.toString());
      return;
    }
    // Other providers / raw share links — same as before login rewrite.
    final remote = subscriptionAddress(text);
    if (looksLikeShare(text) || remote != null) {
      await _activate(looksLikeShare(text) ? text : remote.toString());
      return;
    }
    await _beginContactLogin(text);
  }

  Future<void> _beginContactLogin(String contact) async {
    linkState = SubscriptionLinkState.loading;
    linkError = null;
    loginHint = null;
    loginBotUrl = null;
    loginChannel = null;
    loginSession = null;
    notifyListeners();
    if (!AppBrand.current.allowsTelegram && !_looksLikeEmail(contact)) {
      linkError = strings.emailOnlyContact;
      linkState = SubscriptionLinkState.failed;
      notifyListeners();
      return;
    }
    try {
      final result = await _subscriptions.loginWithContact(contact);
      if (result.error != null || result.session.isEmpty) {
        linkError = result.error ?? strings.linkOpenFailed;
        linkState = SubscriptionLinkState.failed;
        notifyListeners();
        return;
      }
      loginSession = result.session;
      loginChannel = result.channel;
      loginBotUrl = (result.botUrl ?? '').isEmpty ? null : result.botUrl;
      loginHint = result.hint;
      oneTimeNumber = result.publicId;
      _loginStartedAt = DateTime.now();
      await _persistPendingLogin();
      notifyListeners();
      _loginPoll?.cancel();
      _loginPoll = Timer.periodic(const Duration(seconds: 2), (_) {
        unawaited(_pollLoginOnce());
      });
      await _pollLoginOnce();
    } catch (_) {
      linkError = strings.linkOpenFailed;
      linkState = SubscriptionLinkState.failed;
      notifyListeners();
    }
  }

  Future<void> _pollLoginOnce() async {
    final session = loginSession;
    if (session == null || session.isEmpty) return;
    final started = _loginStartedAt;
    if (started != null && DateTime.now().difference(started) > const Duration(minutes: 30)) {
      _loginPoll?.cancel();
      _loginPoll = null;
      loginSession = null;
      loginBotUrl = null;
      loginHint = null;
      await _repository.clearPendingLogin();
      linkError = strings.loginTimedOut;
      linkState = SubscriptionLinkState.failed;
      notifyListeners();
      return;
    }
    try {
      final status = await _subscriptions.pollLoginStatus(session);
      if (loginSession != session) return;
      if (status.isReady) {
        _loginPoll?.cancel();
        _loginPoll = null;
        loginSession = null;
        loginBotUrl = null;
        loginHint = null;
        loginChannel = null;
        await _repository.clearPendingLogin();
        oneTimeUrl = status.url.toString();
        oneTimeNumber = status.publicId ?? oneTimeNumber;
        await _activate(oneTimeUrl!);
        if (status.publicId != null) {
          await _rememberAccountNumber(status.publicId);
        }
        return;
      }
      if (status.isExpired) {
        _loginPoll?.cancel();
        _loginPoll = null;
        loginSession = null;
        loginBotUrl = null;
        loginHint = null;
        await _repository.clearPendingLogin();
        linkError = strings.loginTimedOut;
        linkState = SubscriptionLinkState.failed;
        notifyListeners();
      }
    } catch (_) {
      // Keep waiting: transient network blips should not abort login.
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
      unawaited(_repository.saveAccount(account));
    } catch (_) {
      // Fail closed for K-Pax when local access already ended or never loaded.
      final kpaxExpired = isKPaxSubscription && !account.hasAccess;
      if (kept == null || kpaxExpired) {
        profile = null;
        linkError = strings.linkOpenFailed;
        linkState = SubscriptionLinkState.failed;
      } else {
        // Offline grace: keep last good profile only while local expiry still valid.
        profile = kept;
        linkState = SubscriptionLinkState.ready;
      }
    }
    notifyListeners();
  }

  Future<void> _rememberAccountNumber(String? id) async {
    final number = id?.trim() ?? '';
    final prefix = RegExp.escape(AppBrand.current.accountPrefix);
    if (!isKPaxSubscription ||
        !RegExp('^$prefix-\\d{5,8}\$').hasMatch(number) ||
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
    // K-Pax must send expire via subscription-userinfo; without it use a short
    // grace so a blocked refresh cannot keep forever-access from local prefs.
    final fallbackExpiry = isKPaxSubscription
        ? DateTime.now().add(const Duration(hours: 36))
        : DateTime.now().add(const Duration(days: 3650));
    account = account.copyWith(
      plan: SubscriptionPlan.trial,
      accessExpiresAt: current.expiresAt ?? fallbackExpiry,
      displayName: subscriptionName,
    );
  }

  Future<void> maybeAutoConnect() async {
    if (!appSettings.autoConnectOnLaunch) return;
    if (!hasAccess) return;
    if (isConnected || isBusy) return;
    await connect();
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

  Future<void> dismissRefreshSubscriptionNotice() async {
    _dismissedHomeNoticeId = SettingsRepository.homeRefreshNoticeId;
    notifyListeners();
    await _repository.dismissHomeNotice(SettingsRepository.homeRefreshNoticeId);
  }

  Future<void> refreshSubscriptionFromNotice() async {
    await refreshServers();
    if (linkState == SubscriptionLinkState.ready) {
      await dismissRefreshSubscriptionNotice();
      _emitFlash(strings.serversUpdated);
    }
  }

  /// After email/Telegram confirm page opens the app via `kpax://confirmed`.
  Future<void> onLoginConfirmedDeepLink() async {
    if (loginSession != null) {
      await _pollLoginOnce();
      if (hasAccess) {
        _emitFlash(strings.loginConfirmedFlash, openAccount: true);
      } else if (linkError != null) {
        _emitFlash(linkError!, openAccount: true);
      }
      return;
    }
    await refreshAccessAfterPayment(openAccount: true);
  }

  /// After `/pay/done` — reload the same subscription without re-login.
  Future<void> refreshAccessAfterPayment({bool openAccount = false}) async {
    if (subscriptionUrl == null) {
      linkError = strings.openProfileForAccess;
      notifyListeners();
      _emitFlash(strings.openProfileForAccess, openAccount: true);
      return;
    }
    await refreshServers();
    if (hasAccess) {
      _emitFlash(strings.paidRefreshDone, openAccount: openAccount);
    } else if (linkError != null) {
      _emitFlash(linkError!, openAccount: openAccount);
    } else {
      _emitFlash(strings.paidRefreshDone, openAccount: openAccount);
    }
  }

  String? get subscriptionToken {
    final url = subscriptionUrl;
    if (url == null) return null;
    final uri = kPaxSubscriptionUri(url);
    if (uri == null) return null;
    final path = uri.path;
    if (!path.startsWith('/s/')) return null;
    final token = path.substring(3);
    return token.isEmpty ? null : token;
  }

  List<ConnectedDeviceInfo> devices = const [];
  bool isLoadingDevices = false;
  String? devicesError;

  Future<void> loadDevices() async {
    final token = subscriptionToken;
    if (token == null) {
      devices = const [];
      devicesError = null;
      notifyListeners();
      return;
    }
    isLoadingDevices = true;
    devicesError = null;
    notifyListeners();
    try {
      devices = await _subscriptions.fetchDevices(token);
    } catch (_) {
      devicesError = strings.devicesLoadFailed;
      devices = const [];
    }
    isLoadingDevices = false;
    notifyListeners();
  }

  Future<bool> kickDevice(String deviceId) async {
    final token = subscriptionToken;
    if (token == null || deviceId.isEmpty) return false;
    try {
      final ok = await _subscriptions.kickDevice(token, deviceId);
      if (ok) await loadDevices();
      return ok;
    } catch (_) {
      return false;
    }
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
    // Reality (primary dest + self-steal) → gRPC/XHTTP → brand WS/CDN → UDP.
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
      TunnelKind.message,
      TunnelKind.hy2,
      TunnelKind.tuic,
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
    // Protocol order wins first; among Reality prefer :443 (primary dest) over self-steal.
    for (final kind in order) {
      final same = _preferPrimaryEndpoints(
        source.where((node) => node.kind == kind).toList(),
      );
      if (same.isEmpty) continue;
      return _fastest(same);
    }
    return _preferType(pool, order);
  }

  /// Prefer primary Reality (:443) ahead of self-steal (:2053) before probing.
  List<TunnelNode> _preferPrimaryEndpoints(List<TunnelNode> nodes) {
    if (nodes.length <= 1) return nodes;
    if (nodes.first.kind != TunnelKind.reality) return nodes;
    final primary = <TunnelNode>[];
    final secondary = <TunnelNode>[];
    for (final node in nodes) {
      final port = node.port == 0 ? 443 : node.port;
      if (port == 443) {
        primary.add(node);
      } else {
        secondary.add(node);
      }
    }
    return [...primary, ...secondary];
  }

  /// UDP lines (Hy2, TUIC) cannot be timed over TCP; they keep subscription order.
  Future<TunnelNode> _fastest(List<TunnelNode> nodes) async {
    if (nodes.length == 1) return nodes.first;
    if (nodes.first.kind == TunnelKind.hy2 || nodes.first.kind == TunnelKind.tuic) {
      return nodes.first;
    }
    // For Reality keep primary endpoints first; only race within the best group.
    final ranked = _preferPrimaryEndpoints(nodes);
    final preferredPort = ranked.first.port == 0 ? 443 : ranked.first.port;
    final group = ranked
        .where((node) => (node.port == 0 ? 443 : node.port) == preferredPort)
        .toList();
    final race = group.isEmpty ? ranked : group;
    final seen = <String>{};
    TunnelNode? best;
    var bestMs = 1 << 30;
    for (final node in race) {
      final port = node.port == 0 ? 443 : node.port;
      if (!seen.add('${node.host}:$port')) continue;
      final ms = await measureTcp(node.host, port);
      if (ms != null && ms < bestMs) {
        best = node;
        bestMs = ms;
      }
    }
    return best ?? race.first;
  }

  TunnelNode _preferType(List<TunnelNode> nodes, List<TunnelKind> order) {
    for (final kind in order) {
      for (final node in _preferPrimaryEndpoints(
        nodes.where((item) => item.kind == kind).toList(),
      )) {
        return node;
      }
    }
    return nodes.first;
  }

  TunnelNode? _spareFor(TunnelNode node) {
    final nodes = profile?.nodes ?? const <TunnelNode>[];
    // Same country + same kind, other endpoint (Reality :443 ↔ self-steal).
    for (final candidate in _preferPrimaryEndpoints(
      nodes
          .where(
            (item) =>
                item.countryId == node.countryId &&
                item.kind == node.kind &&
                (item.host != node.host || item.port != node.port),
          )
          .toList(),
    )) {
      return candidate;
    }
    final order = _kindOrder();
    final start = order.indexOf(node.kind);
    if (start < 0) return null;
    for (final kind in order.skip(start + 1)) {
      for (final candidate in nodes) {
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
      _wantConnected = true;
      // Always keep a small budget for unexpected drops (Android/iOS); aggressive = more tries.
      _reconnectBudget =
          proSettings.reconnectPolicy == ReconnectPolicy.aggressive ? 5 : 2;
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
    _wantConnected = false;
    _reconnectBudget = 0;
    _reconnectInFlight = false;
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

  static bool _looksLikeEmail(String raw) {
    final text = raw.trim();
    if (!text.contains('@') || text.startsWith('@')) return false;
    return RegExp(
      r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$',
    ).hasMatch(text);
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
    _loginPoll?.cancel();
    _vpnStatusSub?.cancel();
    _trafficSub?.cancel();
    super.dispose();
  }
}

class UiFlash {
  const UiFlash({required this.message, this.openAccount = false});

  final String message;
  final bool openAccount;
}
