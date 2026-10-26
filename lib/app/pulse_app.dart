import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:pulse_vpn/app/theme/nord_signal_theme.dart';
import 'package:pulse_vpn/core/models/app_settings.dart';
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

  @override
  void initState() {
    super.initState();
    _theme = widget.controller.appSettings.theme;
    widget.controller.addListener(_onTheme);
    _bindTray();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.maybeAutoConnect();
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
    const MethodChannel('kpax/window').invokeMethod<void>('setTrayState', state);
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
    final isLight = _theme == AppThemePreference.light;
    return ChangeNotifierProvider.value(
      value: widget.controller,
      child: MaterialApp(
        title: 'K-Pax',
        debugShowCheckedModeBanner: false,
        theme: _themeForWindow(NordSignalTheme.forPreference(_theme)),
        builder: (context, child) {
          final overlay = SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness:
                isLight ? Brightness.dark : Brightness.light,
            systemNavigationBarColor:
                isLight ? NordColors.lightBgBottom : NordColors.bgBottom,
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
