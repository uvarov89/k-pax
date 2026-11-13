import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pulse_vpn/app/brand/app_brand.dart';
import 'package:pulse_vpn/app/pulse_app.dart';
import 'package:pulse_vpn/app/theme/nord_signal_theme.dart';
import 'package:pulse_vpn/app/theme/xplm_colors.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppBrand.init();
  final controller = VpnController();
  await controller.hydrate();

  final brand = AppBrand.current;
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor:
          brand.isXplm ? XplmColors.paper : NordColors.bgBottom,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(PulseApp(controller: controller));
}
