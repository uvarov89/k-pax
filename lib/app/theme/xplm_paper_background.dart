import 'package:flutter/material.dart';

import 'package:pulse_vpn/app/theme/xplm_colors.dart';

/// Warm paper backdrop matching x-plm.online site gradients.
class XplmPaperBackground extends StatelessWidget {
  const XplmPaperBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: XplmColors.paper,
        gradient: RadialGradient(
          center: Alignment(-0.85, -1.0),
          radius: 1.15,
          colors: [
            Color(0xE6F5D9C0),
            XplmColors.paper,
          ],
          stops: [0.0, 0.55],
        ),
      ),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.95, -0.85),
            radius: 0.95,
            colors: [
              Color(0xBFF2CFC0),
              Color(0x00FAF7F1),
            ],
            stops: [0.0, 0.55],
          ),
        ),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0.0, 1.1),
              radius: 1.0,
              colors: [
                Color(0x80F0E6D0),
                Color(0x00FAF7F1),
              ],
              stops: [0.0, 0.6],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
