import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:pulse_vpn/app/brand/app_brand.dart';
import 'package:pulse_vpn/app/theme/nord_signal_theme.dart';
import 'package:pulse_vpn/app/theme/xplm_colors.dart';
import 'package:pulse_vpn/core/models/app_settings.dart';
import 'package:pulse_vpn/core/services/deep_link_service.dart';
import 'package:pulse_vpn/core/services/network_auto_connect.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';
import 'package:pulse_vpn/features/home/home_screen.dart';

class PulseApp extends StatefulWidget {
  const PulseApp({super.key, required this.controller});

  final VpnController controller;

  @override
  State<PulseApp> createState() => _PulseAppState();
}

class _PulseAppState extends State<PulseApp> {
  late AppThemePreference _theme;
  DeepLinkService? _deepLinks;
  NetworkAutoConnect? _networkAuto;

  @override
  void initState() {
    super.initState();
    _theme = widget.controller.appSettings.theme;
    widget.controller.addListener(_onTheme);
    _bindTray();
    _deepLinks = DeepLinkService(widget.controller);
    _networkAuto = NetworkAutoConnect(widget.controller);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.maybeAutoConnect();
      _deepLinks?.start();
      // Skip platform plugins under `flutter test` (no EventChannel impl).
      if (!Platform.environment.containsKey('FLUTTER_TEST')) {
        _networkAuto?.start();
      }
    });
  }

  void _bindTray() {
    if (kIsWeb || !Platform.isWindows) return;
    const channel = MethodChannel('kpax/window');
    channel.setMethodCallHandler((call) async {
      if (call.method == 'trayToggle') {
        await widget.controller.toggleConnection();
      }
    });
    widget.controller.addListener(_pushTrayState);
    _pushTrayState();
  }

  void _pushTrayState() {
    if (kIsWeb || !Platform.isWindows) return;
    final controller = widget.controller;
    final state = controller.isBusy
        ? 'busy'
        : controller.isConnected
            ? 'connected'
            : 'disconnected';
    const MethodChannel('kpax/window')
        .invokeMethod<void>('setTrayState', state)
        .catchError((_) {});
  }

  void _onTheme() {
    final next = widget.controller.appSettings.theme;
    if (next == _theme || !mounted) return;
    setState(() => _theme = next);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTheme);
    widget.controller.removeListener(_pushTrayState);
    _deepLinks?.dispose();
    _networkAuto?.dispose();
    super.dispose();
  }

  ThemeData _themeForWindow(ThemeData theme) {
    if (kIsWeb || !Platform.isWindows) return theme;
    return theme.copyWith(
      visualDensity: VisualDensity.compact,
      appBarTheme: theme.appBarTheme.copyWith(
        toolbarHeight: 48,
        titleSpacing: 0,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.all(8),
          minimumSize: const Size(40, 40),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      listTileTheme: const ListTileThemeData(
        visualDensity: VisualDensity.compact,
        minVerticalPadding: 8,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final brand = AppBrand.current;
    final isLight = brand.isXplm || _theme == AppThemePreference.light;
    return ChangeNotifierProvider.value(
      value: widget.controller,
      child: MaterialApp(
        title: brand.appName,
        debugShowCheckedModeBanner: false,
        theme: _themeForWindow(NordSignalTheme.forPreference(_theme)),
        builder: (context, child) {
          final overlay = SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness:
                isLight ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: brand.isXplm
                ? XplmColors.paper
                : isLight
                    ? NordColors.lightBgBottom
                    : NordColors.bgBottom,
            systemNavigationBarIconBrightness:
                isLight ? Brightness.dark : Brightness.light,
          );
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: overlay,
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const HomeScreen(),
      ),
    );
  }
}
