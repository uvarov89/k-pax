import 'package:flutter/material.dart';

import 'package:pulse_vpn/app/theme/xplm_colors.dart';
import 'package:pulse_vpn/features/account/account_screen.dart';
import 'package:pulse_vpn/features/home/home_screen.dart';
import 'package:pulse_vpn/features/locations/country_picker_screen.dart';
import 'package:pulse_vpn/features/paywall/paywall_screen.dart';
import 'package:pulse_vpn/features/xplm/widgets/xplm_html_widgets.dart';

/// X-Plm root shell: bottom tabs from Codex `bottom-nav` (home/globe/crown/gear).
class XplmShell extends StatefulWidget {
  const XplmShell({super.key});

  @override
  State<XplmShell> createState() => _XplmShellState();
}

class _XplmShellState extends State<XplmShell> {
  int _index = 0;
  final _navigators = List.generate(4, (_) => GlobalKey<NavigatorState>());
  late final _observers = List.generate(4, (_) => _TabObserver(_routesChanged));

  void _routesChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  void _select(int index) {
    if (_index == index) {
      _navigators[index].currentState?.popUntil((route) => route.isFirst);
    } else {
      setState(() => _index = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _navigators[_index].currentState;
    const roots = <Widget>[
      HomeScreen(embeddedInShell: true),
      CountryPickerScreen(embeddedInShell: true),
      PaywallScreen(embeddedInShell: true),
      AccountScreen(embeddedInShell: true),
    ];
    final shell = PopScope(
      canPop: _index == 0 && !(current?.canPop() ?? false),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final navigator = _navigators[_index].currentState;
        if (navigator?.canPop() ?? false) {
          navigator!.pop();
        } else if (_index != 0) {
          setState(() => _index = 0);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF010D1E),
        body: XplmTabNavigation(
          select: _select,
          open: (index, page) {
            final navigator = _navigators[index].currentState!;
            navigator.popUntil((route) => route.isFirst);
            setState(() => _index = index);
            navigator.push(MaterialPageRoute<void>(builder: (_) => page));
          },
          child: IndexedStack(
            index: _index,
            children: [
              for (var i = 0; i < roots.length; i++)
                TickerMode(
                  enabled: _index == i,
                  child: Navigator(
                    key: _navigators[i],
                    observers: [_observers[i]],
                    onGenerateRoute: (_) =>
                        MaterialPageRoute<void>(builder: (_) => roots[i]),
                  ),
                ),
            ],
          ),
        ),
        bottomNavigationBar: XplmBottomNav(index: _index, onChanged: _select),
      ),
    );
    // Keep every desktop tab and pushed screen aligned with the Android layout.
    if (Theme.of(context).platform != TargetPlatform.windows) return shell;
    return ColoredBox(
      color: const Color(0xFF010D1E),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: shell,
        ),
      ),
    );
  }
}

class _TabObserver extends NavigatorObserver {
  _TabObserver(this.changed);
  final VoidCallback changed;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      changed();
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => changed();
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
      (Icons.person_outline_rounded, 'Профиль'),
    ];
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xEB030D1D),
        border: Border(top: BorderSide(color: Color(0xFF13243B))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: InkWell(
                    onTap: () => onChanged(i),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CustomPaint(
                            size: const Size(24, 24),
                            painter: _HtmlNavIcon(i, active: i == index),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            items[i].$2,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
                              fontFamily: 'XplmArial',
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
