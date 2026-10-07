import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pulse_vpn/app/pulse_app.dart';
import 'package:pulse_vpn/app/theme/nord_signal_theme.dart';
import 'package:pulse_vpn/core/models/app_settings.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = VpnController();
  await controller.hydrate();

  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness:
          controller.appSettings.theme == AppThemePreference.light
              ? Brightness.dark
              : Brightness.light,
      systemNavigationBarColor:
          controller.appSettings.theme == AppThemePreference.light
              ? NordColors.lightBgBottom
              : NordColors.bgBottom,
      systemNavigationBarIconBrightness:
          controller.appSettings.theme == AppThemePreference.light
              ? Brightness.dark
              : Brightness.light,
    ),
  );

  runApp(PulseApp(controller: controller));
}
