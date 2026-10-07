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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.maybeAutoConnect();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: widget.controller,
      child: Consumer<VpnController>(
        builder: (context, controller, _) {
          final isLight =
              controller.appSettings.theme == AppThemePreference.light;
          return MaterialApp(
            title: 'K-Pax',
            debugShowCheckedModeBanner: false,
            theme: NordSignalTheme.forPreference(controller.appSettings.theme),
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
          );
        },
      ),
    );
  }
}
