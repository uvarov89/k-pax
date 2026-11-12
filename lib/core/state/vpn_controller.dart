import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

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
    Future<int?> Function(String host, int port)? tcpProbe,
  }) : _service = service ?? defaultVpnService(),
       _repository = repository ?? SettingsRepository(),
       _subscriptions = subscriptions ?? SubscriptionClient(),
       _tcpProbe = tcpProbe;

  final VpnService _service;
  final SettingsRepository _repository;
  final SubscriptionClient _subscriptions;
  /// Optional TCP RTT probe override (tests). Null → [measureTcp].
  final Future<int?> Function(String host, int port)? _tcpProbe;
  int _loginEpoch = 0;
  bool _disposed = false;
  (int, String)? _pollingLogin;
  int _devicesEpoch = 0;
  int _accountEpoch = 0;
  Future<void> _accountWrites = Future<void>.value();
  Future<void> _persistAccountState() {
    final saved = List<SavedSubscription>.of(subscriptions);
    final url = subscriptionUrl ?? '';
    final user = account;
    final next = _accountWrites.catchError((_) {}).then((_) async {
      await _repository.saveSubscriptions(saved);
      await _repository.saveSubscriptionUrl(url);
      await _repository.saveAccount(user);
    });
    _accountWrites = next;
    return next;
  }

  Future<void> _pendingLoginWrites = Future<void>.value();

  Future<void> _queueLoginWrite(Future<void> Function() action) {
    final next = _pendingLoginWrites.catchError((_) {}).then((_) => action());
    _pendingLoginWrites = next;
    return next;
  }

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
  bool needsEmailLink = false;
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
      subscriptionUrl == null &&
      (linkState == SubscriptionLinkState.missing ||
          linkState == SubscriptionLinkState.failed);

  bool get subscriptionLoadFailed =>
      subscriptionUrl != null && linkState == SubscriptionLinkState.failed;

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
          latencyMs: AppBrand.current.isXplm
              ? (lastProbeResults?[node.countryName] ?? -1)
              : -1,
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
        return s.connectedTo(
          connectedNode?.countryName ?? effectiveLocation.nameRu,
        );
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
      await _clearPendingLogin();
      return;
    }
    final pending = await _repository.loadPendingLogin();
    if (pending == null) return;
    final started = DateTime.fromMillisecondsSinceEpoch(pending.startedMs);
    if (DateTime.now().difference(started) > const Duration(minutes: 30)) {
      await _clearPendingLogin();
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

  Future<void> _clearPendingLogin() =>
      _queueLoginWrite(_repository.clearPendingLogin);

  Future<void> _persistPendingLogin() {
    final session = loginSession;
    final started = _loginStartedAt;
    if (session == null || session.isEmpty || started == null) {
      return _clearPendingLogin();
    }
    final channel = loginChannel ?? '';
    final bot = loginBotUrl;
    final hint = loginHint;
    final number = oneTimeNumber;
    return _queueLoginWrite(
      () => _repository.savePendingLogin(
        session: session,
        channel: channel,
        botUrl: bot,
        hint: hint,
        publicId: number,
        startedMs: started.millisecondsSinceEpoch,
      ),
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
      final seed = lastNode ?? await _selectNode();
      final node = await _startWithFailover(seed);
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
    cancelLogin();
    final epoch = ++_accountEpoch;
    final clearedLogin = _pendingLoginWrites;
    if (isConnected) await disconnect();
    final settingsService = _service;
    if (settingsService is VpnSettingsService) {
      await (settingsService as VpnSettingsService).clearSavedAccess();
    }
    if (_disposed || epoch != _accountEpoch) return;
    final url = subscriptionUrl;
    final previousProfile = profile;
    final previousAccount = account;
    final previousProvider = providerWebPage;
    final previousSubscriptions = subscriptions;
    final previousState = linkState;
    if (url != null) {
      subscriptions = subscriptions.where((item) => item.url != url).toList();
    }
    subscriptionUrl = null;
    profile = null;
    providerWebPage = null;
    connectedNode = null;
    account = UserAccount.empty();
    selectedLocation = ServerLocation.auto;
    locationMode = LocationMode.auto;
    linkError = null;
    lastProbeResults = null;
    oneTimeUrl = null;
    oneTimeNumber = null;
    needsEmailLink = false;
    devices = const [];
    devicesError = null;
    isLoadingDevices = false;
    _devicesEpoch++;
    linkState = SubscriptionLinkState.missing;
    notifyListeners();
    try {
      await _persistAccountState();
      await clearedLogin;
    } catch (_) {
      if (!_disposed && epoch == _accountEpoch) {
        subscriptionUrl = url;
        profile = previousProfile;
        account = previousAccount;
        providerWebPage = previousProvider;
        subscriptions = previousSubscriptions;
        linkState = previousState;
        notifyListeners();
      }
      rethrow;
    }
  }

  /// Saves the link if it is new and makes it the active one.
  Future<void> _activate(String url) async {
    final epoch = ++_accountEpoch;
    if (connectionState != VpnConnectionState.disconnected) await disconnect();
    if (_disposed || epoch != _accountEpoch) return;
    if (subscriptions.every((item) => item.url != url)) {
      subscriptions = [...subscriptions, SavedSubscription(url: url)];
    }
    if (subscriptionUrl != url) {
      profile = null;
      account = UserAccount.empty();
      providerWebPage = null;
      connectedNode = null;
      lastProbeResults = null;
      devices = const [];
      devicesError = null;
      isLoadingDevices = false;
      _devicesEpoch++;
    }
    subscriptionUrl = url;
    linkState = SubscriptionLinkState.loading;
    notifyListeners();
    await _persistAccountState();
    if (_disposed || epoch != _accountEpoch) return;
    await reloadSubscription();
    if (_disposed || epoch != _accountEpoch) return;
    await _persistAccountState();
  }

  Future<void> switchSubscription(String url) async {
    if (url == subscriptionUrl || isBusy) return;
    cancelLogin();
    await _activate(url);
  }

  Future<void> removeSubscription(String url) async {
    if (url == subscriptionUrl) {
      await forgetSubscriptionLink();
      if (subscriptions.isNotEmpty) await _activate(subscriptions.first.url);
      return;
    }
    subscriptions = subscriptions.where((item) => item.url != url).toList();
    await _persistAccountState();
    notifyListeners();
  }

  Future<void> _rename(String url, String name) async {
    final index = subscriptions.indexWhere((item) => item.url == url);
    if (index < 0 || subscriptions[index].name == name) return;
    subscriptions = [...subscriptions]
      ..[index] = subscriptions[index].named(name);
    await _persistAccountState();
  }

  void clearOneTimeLink() {
    oneTimeUrl = null;
    oneTimeNumber = null;
    notifyListeners();
  }

  void cancelLogin() {
    _loginEpoch++;
    _loginPoll?.cancel();
    _loginPoll = null;
    _loginStartedAt = null;
    loginSession = null;
    loginChannel = null;
    loginBotUrl = null;
    loginHint = null;
    unawaited(_clearPendingLogin().catchError((_) {}));
    if (linkState == SubscriptionLinkState.loading) {
      linkState = subscriptionUrl == null
          ? SubscriptionLinkState.missing
          : profile == null
          ? SubscriptionLinkState.failed
          : profile!.isExpired
          ? SubscriptionLinkState.expired
          : SubscriptionLinkState.ready;
    }
    notifyListeners();
  }

  Future<void> submitSubscriptionLink(String raw) async {
    oneTimeUrl = null;
    oneTimeNumber = null;
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

  SubscriptionLinkState get _loginFailureState =>
      subscriptionUrl != null && profile != null
      ? (profile!.isExpired
            ? SubscriptionLinkState.expired
            : SubscriptionLinkState.ready)
      : SubscriptionLinkState.failed;

  Future<void> _beginContactLogin(String contact) async {
    final epoch = _loginEpoch;
    linkState = SubscriptionLinkState.loading;
    linkError = null;
    loginHint = null;
    loginBotUrl = null;
    loginChannel = null;
    loginSession = null;
    notifyListeners();
    if (!AppBrand.current.allowsTelegram && !_looksLikeEmail(contact)) {
      linkError = strings.emailOnlyContact;
      linkState = _loginFailureState;
      notifyListeners();
      return;
    }
    try {
      final result = await _subscriptions.loginWithContact(contact);
      if (_disposed || epoch != _loginEpoch) return;
      if (result.error != null || result.session.isEmpty) {
        linkError = result.error ?? strings.linkOpenFailed;
        linkState = _loginFailureState;
        notifyListeners();
        return;
      }
      loginSession = result.session;
      loginChannel = result.channel;
      loginBotUrl = (result.botUrl ?? '').isEmpty ? null : result.botUrl;
      loginHint = result.hint;
      oneTimeNumber = result.publicId;
      if (result.needsEmailLink) needsEmailLink = true;
      _loginStartedAt = DateTime.now();
      await _persistPendingLogin();
      if (_disposed || epoch != _loginEpoch) return;
      notifyListeners();
      _loginPoll?.cancel();
      _loginPoll = Timer.periodic(const Duration(seconds: 2), (_) {
        unawaited(_pollLoginOnce());
      });
      await _pollLoginOnce();
    } catch (_) {
      if (_disposed || epoch != _loginEpoch) return;
      linkError = strings.linkOpenFailed;
      linkState = _loginFailureState;
      notifyListeners();
    }
  }

  Future<void> submitLoginCode(String code) async {
    final session = loginSession;
    if (session == null || session.isEmpty) return;
    final epoch = _loginEpoch;
    linkError = null;
    notifyListeners();
    try {
      final status = await _subscriptions.confirmLoginCode(session, code);
      if (_disposed || epoch != _loginEpoch || loginSession != session) return;
      if (!status.isReady || status.url == null) {
        linkError = status.error ?? strings.badLoginCode;
        notifyListeners();
        return;
      }
      _loginPoll?.cancel();
      _loginPoll = null;
      loginSession = null;
      loginBotUrl = null;
      loginHint = null;
      loginChannel = null;
      if (status.needsEmailLink) needsEmailLink = true;
      await _clearPendingLogin();
      if (_disposed || epoch != _loginEpoch) return;
      oneTimeUrl = status.url.toString();
      oneTimeNumber = status.publicId ?? oneTimeNumber;
      await _activate(oneTimeUrl!);
      if (status.publicId != null) {
        await _rememberAccountNumber(status.publicId);
      }
    } catch (_) {
      if (_disposed || epoch != _loginEpoch) return;
      linkError = strings.linkOpenFailed;
      notifyListeners();
    }
  }

  Future<String?> startLinkEmail(String email) async {
    final token = subscriptionToken;
    if (token == null) return strings.openProfileForAccess;
    try {
      return await _subscriptions.startLinkEmail(token, email);
    } catch (_) {
      return strings.linkOpenFailed;
    }
  }

  Future<String?> confirmLinkEmail(String code) async {
    final token = subscriptionToken;
    if (token == null) return strings.openProfileForAccess;
    try {
      final error = await _subscriptions.confirmLinkEmail(token, code);
      if (error != null) return error;
      needsEmailLink = false;
      notifyListeners();
      return null;
    } catch (_) {
      return strings.linkOpenFailed;
    }
  }

  Future<void> _pollLoginOnce() async {
    final session = loginSession;
    if (session == null || session.isEmpty) return;
    final epoch = _loginEpoch;
    final requestKey = (epoch, session);
    if (_pollingLogin == requestKey) return;
    final started = _loginStartedAt;
    if (started != null &&
        DateTime.now().difference(started) > const Duration(minutes: 30)) {
      _loginPoll?.cancel();
      _loginPoll = null;
      loginSession = null;
      loginBotUrl = null;
      loginHint = null;
      await _clearPendingLogin();
      if (_disposed || epoch != _loginEpoch) return;
      linkError = strings.loginTimedOut;
      linkState = _loginFailureState;
      notifyListeners();
      return;
    }
    _pollingLogin = requestKey;
    try {
      final status = await _subscriptions.pollLoginStatus(session);
      if (_disposed || epoch != _loginEpoch || loginSession != session) return;
        if (status.isReady) {
        _loginPoll?.cancel();
        _loginPoll = null;
        loginSession = null;
        loginBotUrl = null;
        loginHint = null;
        loginChannel = null;
        if (status.needsEmailLink) needsEmailLink = true;
        await _clearPendingLogin();
        if (_disposed || epoch != _loginEpoch) return;
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
        await _clearPendingLogin();
        if (_disposed || epoch != _loginEpoch) return;
        linkError = strings.loginTimedOut;
        linkState = _loginFailureState;
        notifyListeners();
      }
    } catch (_) {
      // Keep waiting: transient network blips should not abort login.
    } finally {
      if (_pollingLogin == requestKey) _pollingLogin = null;
    }
  }

  int _subscriptionReloadEpoch = 0;

  Future<void> reloadSubscription() async {
    final reloadEpoch = ++_subscriptionReloadEpoch;
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
        if (_disposed ||
            reloadEpoch != _subscriptionReloadEpoch ||
            url != subscriptionUrl) {
          return;
        }
        profile = parseSubscription(fetched.body, userinfo: fetched.userinfo);
        providerWebPage = fetched.webPage;
        if (fetched.title != null) await _rename(url, fetched.title!);
        if (_disposed ||
            reloadEpoch != _subscriptionReloadEpoch ||
            url != subscriptionUrl) {
          return;
        }
        await _rememberAccountNumber(fetched.publicId);
        if (_disposed ||
            reloadEpoch != _subscriptionReloadEpoch ||
            url != subscriptionUrl) {
          return;
        }
        needsEmailLink = fetched.needsEmailLink;
      }
      _applyProfile();
      _restoreSavedLocation();
    } on FormatException {
      if (_disposed ||
          reloadEpoch != _subscriptionReloadEpoch ||
          url != subscriptionUrl) {
        return;
      }
      linkError = strings.emptySubscription;
      if (kept != null && account.hasAccess) {
        profile = kept;
        linkState = SubscriptionLinkState.ready;
      } else {
        profile = null;
        linkState = SubscriptionLinkState.failed;
      }
    } on SubscriptionRejected {
      if (_disposed ||
          reloadEpoch != _subscriptionReloadEpoch ||
          url != subscriptionUrl) {
        return;
      }
      profile = null;
      linkState = SubscriptionLinkState.expired;
      account = account.copyWith(
        plan: SubscriptionPlan.expired,
        accessExpiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      unawaited(_repository.saveAccount(account));
    } catch (_) {
      if (_disposed ||
          reloadEpoch != _subscriptionReloadEpoch ||
          url != subscriptionUrl) {
        return;
      }
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
    await _persistAccountState();
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

  Future<void> _appSettingsWrites = Future<void>.value();

  Future<void> updateAppSettings(AppSettings settings) {
    final next = _appSettingsWrites
        .catchError((_) {})
        .then((_) => _updateAppSettings(settings));
    _appSettingsWrites = next;
    return next;
  }

  Future<void> _updateAppSettings(AppSettings settings) async {
    final previous = appSettings;
    final launchChanged = settings.launchAtLogin != previous.launchAtLogin;
    appSettings = settings;
    notifyListeners();
    try {
      if (launchChanged) {
        await WindowsStartup.setEnabled(settings.launchAtLogin);
      }
      final settingsService = _service;
      if (settingsService is VpnSettingsService) {
        await (settingsService as VpnSettingsService).applyAppSettings(
          settings,
        );
      }
      await _repository.saveAppSettings(settings);
    } catch (_) {
      final settingsService = _service;
      if (settingsService is VpnSettingsService) {
        try {
          await (settingsService as VpnSettingsService).applyAppSettings(
            previous,
          );
        } catch (_) {
          // Keep the original error; the UI restores the previous selection.
        }
      }
      if (identical(appSettings, settings)) {
        appSettings = previous;
      } else if (launchChanged) {
        appSettings = appSettings.copyWith(
          launchAtLogin: previous.launchAtLogin,
        );
      }
      if (!_disposed) notifyListeners();
      rethrow;
    }
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
    final previous = proSettings;
    final lifted = proSettings.killSwitch && !settings.killSwitch;
    proSettings = settings;
    notifyListeners();
    try {
      await _repository.saveProSettings(settings);
    } catch (_) {
      if (identical(proSettings, settings)) proSettings = previous;
      if (!_disposed) notifyListeners();
      rethrow;
    }
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

  final Set<(String, String)> _removingDeviceRequests = {};
  Set<String> get removingDeviceIds => _removingDeviceRequests
      .where((request) => request.$1 == subscriptionToken)
      .map((request) => request.$2)
      .toSet();

  Future<void> loadDevices() async {
    final token = subscriptionToken;
    final epoch = ++_devicesEpoch;
    if (token == null) {
      devices = const [];
      devicesError = null;
      isLoadingDevices = false;
      notifyListeners();
      return;
    }
    isLoadingDevices = true;
    devicesError = null;
    notifyListeners();
    try {
      final loaded = await _subscriptions.fetchDevices(token);
      if (_disposed || epoch != _devicesEpoch || token != subscriptionToken) {
        return;
      }
      devices = loaded;
    } catch (_) {
      if (_disposed || epoch != _devicesEpoch || token != subscriptionToken) {
        return;
      }
      devicesError = strings.devicesLoadFailed;
      devices = const [];
    } finally {
      if (!_disposed && epoch == _devicesEpoch && token == subscriptionToken) {
        isLoadingDevices = false;
        notifyListeners();
      }
    }
  }

  Future<bool> kickDevice(String deviceId) async {
    final token = subscriptionToken;
    if (token == null ||
        deviceId.isEmpty ||
        _removingDeviceRequests.contains((token, deviceId))) {
      return false;
    }
    _removingDeviceRequests.add((token, deviceId));
    notifyListeners();
    try {
      final ok = await _subscriptions.kickDevice(token, deviceId);
      if (_disposed || token != subscriptionToken) return false;
      if (ok) await loadDevices();
      return ok;
    } catch (_) {
      return false;
    } finally {
      _removingDeviceRequests.remove((token, deviceId));
      if (!_disposed) notifyListeners();
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

  bool get _isAutoMode =>
      locationMode == LocationMode.auto || selectedLocation.isAuto;

  Future<TunnelNode> _selectNode({
    Set<String>? excludeCountryIds,
    Set<String>? excludeEndpoints,
  }) async {
    final nodes = profile?.nodes ?? const <TunnelNode>[];
    final countryId = _isAutoMode ? null : selectedLocation.id;
    final order = _kindOrder();
    final pool = nodes.where((node) {
      if (countryId != null && node.countryId != countryId) return false;
      if (excludeCountryIds != null &&
          excludeCountryIds.contains(node.countryId)) {
        return false;
      }
      if (excludeEndpoints != null &&
          excludeEndpoints.contains(_endpointKey(node))) {
        return false;
      }
      return order.contains(node.kind);
    }).toList();
    if (pool.isEmpty) {
      throw StateError('no node');
    }
    // Spread load across near-best countries only in Автовыбор (not manual country).
    return _autoServerAndType(pool, order, spreadLoad: countryId == null);
  }

  /// Start [first], then same-country spares. In Auto only, keep picking other
  /// countries until the pool is exhausted.
  Future<TunnelNode> _startWithFailover(TunnelNode first) async {
    final tried = <String>{};
    final triedCountries = <String>{first.countryId};
    Object? lastError;

    Future<TunnelNode?> tryStart(TunnelNode node, {bool disconnectFirst = false}) async {
      tried.add(_endpointKey(node));
      triedCountries.add(node.countryId);
      if (disconnectFirst) {
        try {
          await _service.disconnect();
        } catch (_) {}
      }
      try {
        await _start(node);
        return node;
      } catch (e) {
        lastError = e;
        return null;
      }
    }

    Future<TunnelNode?> trySpares(TunnelNode from) async {
      if (!proSettings.protocolFallback) return null;
      var spare = _spareFor(from, tried);
      while (spare != null) {
        final ok = await tryStart(spare, disconnectFirst: true);
        if (ok != null) return ok;
        spare = _spareFor(spare, tried);
      }
      return null;
    }

    final primary = await tryStart(first);
    if (primary != null) return primary;

    final spareOk = await trySpares(first);
    if (spareOk != null) return spareOk;

    if (!_isAutoMode) {
      throw lastError ?? StateError('connect failed');
    }

    // Auto: jump to another country after same-country path is exhausted.
    while (true) {
      final TunnelNode next;
      try {
        next = await _selectNode(
          excludeCountryIds: triedCountries,
          excludeEndpoints: tried,
        );
      } catch (_) {
        throw lastError ?? StateError('connect failed');
      }
      final started = await tryStart(next, disconnectFirst: true);
      if (started != null) return started;
      final nextSpare = await trySpares(next);
      if (nextSpare != null) return nextSpare;
    }
  }

  /// Reachable server among near-best RTTs. Message lines stay out of the race
  /// unless they are the only allowed profile.
  Future<TunnelNode> _autoServerAndType(
    List<TunnelNode> pool,
    List<TunnelKind> order, {
    bool spreadLoad = true,
  }) async {
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
      return _pickNearBest(same, spreadLoad: spreadLoad);
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
  ///
  /// TCP races: pick randomly among nodes within a small RTT slack of the best
  /// (not pure least-ping), so Автовыбор spreads load across DE/FI/BG.
  Future<TunnelNode> _pickNearBest(
    List<TunnelNode> nodes, {
    bool spreadLoad = true,
  }) async {
    if (nodes.length == 1) return nodes.first;
    if (nodes.first.kind == TunnelKind.hy2 ||
        nodes.first.kind == TunnelKind.tuic) {
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
    final timed = <({TunnelNode node, int ms})>[];
    for (final node in race) {
      final port = node.port == 0 ? 443 : node.port;
      if (!seen.add('${node.host}:$port')) continue;
      final ms = await (_tcpProbe ?? measureTcp)(node.host, port);
      if (ms != null) timed.add((node: node, ms: ms));
    }
    if (timed.isEmpty) return race.first;

    timed.sort((a, b) => a.ms.compareTo(b.ms));
    final bestMs = timed.first.ms;
    // Slack: at least +50 ms, or +30% of best — still "near best", not random junk.
    final slack = math.max(50, (bestMs * 0.3).round());
    var pool = timed
        .where((item) => item.ms <= bestMs + slack)
        .map((item) => item.node)
        .toList();

    if (spreadLoad && pool.length > 1) {
      // Soft-avoid FI (VPSPay girl_round throttle) when another near-best exists.
      final withoutHot = pool
          .where((node) => node.countryId.toLowerCase() != 'fi')
          .toList();
      if (withoutHot.isNotEmpty) pool = withoutHot;
    }

    if (pool.length == 1) return pool.first;
    // Sticky among near-best: same account keeps the same country across reconnects,
    // while different accounts spread across DE/FI/BG.
    return pool[_stickyIndex(pool.length)];
  }

  int _stickySeed() {
    final id = account.userId.trim();
    if (id.isNotEmpty) return id.hashCode;
    final url = (subscriptionUrl ?? '').trim();
    if (url.isNotEmpty) return url.hashCode;
    return 0;
  }

  int _stickyIndex(int length) {
    if (length <= 1) return 0;
    final seed = _stickySeed();
    if (seed == 0) return _autoPickRandom.nextInt(length);
    return seed.abs() % length;
  }

  static final _autoPickRandom = math.Random();

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

  String _endpointKey(TunnelNode node) =>
      '${node.countryId}|${node.kind.name}|${node.host}|${node.port}';

  /// Same-country fallbacks: self-steal / other ports, then other hosts (RU front),
  /// then next protocol kinds. [tried] prevents 443↔2053 loops.
  TunnelNode? _spareFor(TunnelNode node, [Set<String>? tried]) {
    final seen = tried ?? {_endpointKey(node)};
    final nodes = profile?.nodes ?? const <TunnelNode>[];
    final sameCountry = nodes
        .where((item) => item.countryId == node.countryId)
        .toList();

    // Reality: prefer other endpoints on the same host, then other hosts (front).
    if (node.kind == TunnelKind.reality) {
      final sameHost = <TunnelNode>[];
      final otherHost = <TunnelNode>[];
      for (final item in sameCountry) {
        if (item.kind != TunnelKind.reality) continue;
        final key = _endpointKey(item);
        if (seen.contains(key)) continue;
        if (item.host == node.host) {
          sameHost.add(item);
        } else {
          otherHost.add(item);
        }
      }
      // Sticky among RU fronts so spare load splits across ru/ru2 per account.
      if (otherHost.length > 1) {
        final idx = _stickyIndex(otherHost.length);
        otherHost.insert(0, otherHost.removeAt(idx));
      }
      for (final candidate in [..._preferPrimaryEndpoints(sameHost), ...otherHost]) {
        return candidate;
      }
    } else {
      for (final candidate in _preferPrimaryEndpoints(
        sameCountry
            .where(
              (item) =>
                  item.kind == node.kind && !seen.contains(_endpointKey(item)),
            )
            .toList(),
      )) {
        return candidate;
      }
    }

    final order = _kindOrder();
    final start = order.indexOf(node.kind);
    if (start < 0) return null;
    for (final kind in order.skip(start + 1)) {
      for (final candidate in sameCountry) {
        if (candidate.kind == kind && !seen.contains(_endpointKey(candidate))) {
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
    if (subscriptionLoadFailed) {
      await reloadSubscription();
      if (subscriptionLoadFailed) {
        connectionState = VpnConnectionState.error;
        errorMessage = linkError ?? strings.linkOpenFailed;
        notifyListeners();
        // A network failure is not a reason to log in again or pay again.
        return true;
      }
      if (isBusy || isConnected) return true;
    }
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

    TunnelNode seed;
    try {
      seed = await _selectNode();
    } catch (error) {
      connectionState = VpnConnectionState.error;
      errorMessage = _failureText(error);
      notifyListeners();
      return true;
    }

    try {
      final node = await _startWithFailover(seed);
      await WindowsFirewall.clear();
      connectedNode = node;
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
        if (current == null ||
            _probeRank(node.kind) < _probeRank(current.kind)) {
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
    _disposed = true;
    _loginEpoch++;
    _devicesEpoch++;
    _accountEpoch++;
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
