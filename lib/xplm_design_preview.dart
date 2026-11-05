import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:pulse_vpn/app/theme/nord_signal_theme.dart';
import 'package:pulse_vpn/app/theme/xplm_colors.dart';
import 'package:pulse_vpn/core/services/settings_repository.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';
import 'package:pulse_vpn/features/shell/xplm_shell.dart';

/// Visual-only entry for design checks (no VPN plugins required).
///   flutter run -d chrome --target=lib/xplm_design_preview.dart --dart-define=BRAND=xplm
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsRepository().markOnboardingSeen();
  final controller = VpnController();
  await controller.hydrate();
  runApp(
    ChangeNotifierProvider.value(
      value: controller,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: NordSignalTheme.xplmLight,
        home: const _PhoneFrame(child: XplmShell()),
      ),
    ),
  );
}

/// Centers a 390×844 phone viewport so screenshots match the HTML mock size.
class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF070B14),
      child: Center(
        child: FittedBox(
          child: Container(
            width: 390,
            height: 844,
            decoration: BoxDecoration(
              color: XplmColors.paper,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: XplmColors.cyan.withValues(alpha: 0.28)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.55),
                  blurRadius: 40,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
        ),
      ),
    );
  }
}
