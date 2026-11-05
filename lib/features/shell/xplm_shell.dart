import 'package:flutter/material.dart';

import 'package:pulse_vpn/app/theme/nord_signal_theme.dart';
import 'package:pulse_vpn/app/theme/xplm_colors.dart';
import 'package:pulse_vpn/features/account/account_screen.dart';
import 'package:pulse_vpn/features/home/home_screen.dart';
import 'package:pulse_vpn/features/locations/country_picker_screen.dart';
import 'package:pulse_vpn/features/paywall/paywall_screen.dart';

/// X-Plm root shell: bottom tabs from Codex `bottom-nav` (home/globe/crown/gear).
class XplmShell extends StatefulWidget {
  const XplmShell({super.key});

  @override
  State<XplmShell> createState() => _XplmShellState();
}

class _XplmShellState extends State<XplmShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return NordBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: IndexedStack(
          index: _index,
          children: [
            TickerMode(
              enabled: _index == 0,
              child: const HomeScreen(embeddedInShell: true),
            ),
            const CountryPickerScreen(embeddedInShell: true),
            const PaywallScreen(embeddedInShell: true),
            const AccountScreen(embeddedInShell: true),
          ],
        ),
        bottomNavigationBar: XplmBottomNav(
          index: _index,
          onChanged: (i) => setState(() => _index = i),
        ),
      ),
    );
  }
}

class XplmBottomNav extends StatelessWidget {
  const XplmBottomNav({
    super.key,
    required this.index,
    required this.onChanged,
  });

  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const items = <(IconData, String)>[
      (Icons.home_outlined, 'Главная'),
      (Icons.public_outlined, 'Серверы'),
      (Icons.workspace_premium_outlined, 'Подписка'),
      (Icons.settings_outlined, 'Профиль'),
    ];
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xEB030D1D),
        border: Border(top: BorderSide(color: Color(0xFF13243B))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: index == 0 ? 72 : 56,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: InkWell(
                    onTap: () => onChanged(i),
                    child: Padding(
                      padding: EdgeInsets.only(bottom: index == 0 ? 10 : 0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (index == 0)
                            CustomPaint(
                              size: const Size(24, 24),
                              painter: _HtmlNavIcon(i, active: i == index),
                            )
                          else
                            Icon(
                              items[i].$1,
                              size: index == 0 ? 24 : 22,
                              color: i == index
                                  ? const Color(0xFF00B8FF)
                                  : XplmColors.navMuted,
                              shadows: i == index
                                  ? const [
                                      Shadow(
                                        color: Color(0xFF00AAFF),
                                        blurRadius: 6,
                                      ),
                                    ]
                                  : null,
                            ),
                          const SizedBox(height: 3),
                          Text(
                            items[i].$2,
                            style: TextStyle(
                              fontSize: index == 0 ? 11 : 10,
                              fontWeight: FontWeight.w400,
                              fontFamily: index == 0 ? 'XplmArial' : null,
                              color: i == index
                                  ? const Color(0xFF00B8FF)
                                  : XplmColors.navMuted,
                              shadows: i == index
                                  ? const [
                                      Shadow(
                                        color: Color(0xFF00AEFF),
                                        blurRadius: 6,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Paths copied from the approved HTML's home/globe/crown/gear symbols.
class _HtmlNavIcon extends CustomPainter {
  const _HtmlNavIcon(this.index, {required this.active});
  final int index;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    switch (index) {
      case 0:
        path
          ..moveTo(3, 11)
          ..lineTo(12, 3)
          ..lineTo(21, 11)
          ..moveTo(5, 10)
          ..lineTo(5, 21)
          ..lineTo(10, 21)
          ..lineTo(10, 14)
          ..lineTo(14, 14)
          ..lineTo(14, 21)
          ..lineTo(19, 21)
          ..lineTo(19, 10);
      case 1:
        path
          ..addOval(const Rect.fromLTWH(3, 3, 18, 18))
          ..addOval(const Rect.fromLTWH(8, 3, 8, 18))
          ..moveTo(3, 12)
          ..lineTo(21, 12)
          ..moveTo(5, 7)
          ..lineTo(19, 7)
          ..moveTo(5, 17)
          ..lineTo(19, 17);
      case 2:
        path
          ..moveTo(3, 6)
          ..lineTo(8, 11)
          ..lineTo(12, 3)
          ..lineTo(16, 11)
          ..lineTo(21, 6)
          ..lineTo(19, 20)
          ..lineTo(5, 20)
          ..close()
          ..moveTo(5, 17)
          ..lineTo(19, 17);
      default:
        path
          ..moveTo(9, 3)
          ..lineTo(15, 3)
          ..lineTo(16, 6)
          ..lineTo(19, 7)
          ..lineTo(21, 12)
          ..lineTo(19, 14)
          ..lineTo(19, 18)
          ..lineTo(15, 21)
          ..lineTo(12, 20)
          ..lineTo(9, 21)
          ..lineTo(5, 18)
          ..lineTo(5, 14)
          ..lineTo(3, 12)
          ..lineTo(5, 7)
          ..lineTo(8, 6)
          ..close()
          ..addOval(const Rect.fromLTWH(9, 9, 6, 6));
    }
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (active) {
      canvas.drawPath(
        path,
        paint
          ..color = const Color(0xFF00AAFF)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      paint.maskFilter = null;
    }
    canvas.drawPath(
      path,
      paint..color = active ? const Color(0xFF00B8FF) : XplmColors.navMuted,
    );
  }

  @override
  bool shouldRepaint(covariant _HtmlNavIcon oldDelegate) =>
      oldDelegate.index != index || oldDelegate.active != active;
}
