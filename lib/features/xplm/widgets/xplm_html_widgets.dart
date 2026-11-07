import 'package:flutter/material.dart';
import 'xplm_codex_widgets.dart';

/// Keeps tab navigation independent of the screens' VPN/account logic.
class XplmTabNavigation extends InheritedWidget {
  const XplmTabNavigation({
    super.key,
    required this.select,
    this.open,
    required super.child,
  });
  final ValueChanged<int> select;
  final void Function(int, Widget)? open;
  static bool openInTab(BuildContext context, int index, Widget page) {
    final tabs = context
        .dependOnInheritedWidgetOfExactType<XplmTabNavigation>();
    if (tabs?.open == null) return false;
    tabs!.open!(index, page);
    return true;
  }

  static bool go(BuildContext context, int index) {
    final tabs = context
        .dependOnInheritedWidgetOfExactType<XplmTabNavigation>();
    if (tabs == null) return false;
    tabs.select(index);
    return true;
  }

  static void back(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    context.dependOnInheritedWidgetOfExactType<XplmTabNavigation>()?.select(0);
  }

  @override
  bool updateShouldNotify(XplmTabNavigation oldWidget) =>
      select != oldWidget.select || open != oldWidget.open;
}

class XplmHtmlPage extends StatelessWidget {
  const XplmHtmlPage({
    super.key,
    required this.title,
    required this.child,
    this.action,
    this.showBack = true,
  });
  final String title;
  final Widget child;
  final Widget? action;
  final bool showBack;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF010D1E),
    body: SafeArea(
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: DefaultTextStyle.merge(
            style: const TextStyle(
              fontFamily: 'XplmArial',
              fontSize: 14,
              color: Color(0xFFEEF6FF),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: SizedBox(
                    height: 48,
                    child: Row(
                      children: [
                        if (showBack)
                          XplmHtmlIconButton(
                            icon: Icons.chevron_left_rounded,
                            tooltip: 'Назад',
                            onPressed: () => XplmTabNavigation.back(context),
                          )
                        else
                          const SizedBox(width: 28),
                        Expanded(
                          child: Text(
                            title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        action ?? const SizedBox(width: 28),
                      ],
                    ),
                  ),
                ),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class XplmHtmlIconButton extends StatelessWidget {
  const XplmHtmlIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });
  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 28,
    height: 40,
    child: IconButton(
      padding: EdgeInsets.zero,
      tooltip: tooltip,
      onPressed: onPressed,
      icon: icon == Icons.chevron_left_rounded
          ? const Text(
              '‹',
              style: TextStyle(
                fontFamily: 'XplmArial',
                fontSize: 32,
                height: 1,
                color: Color(0xFF96B3D1),
              ),
            )
          : Icon(icon, size: 22, color: const Color(0xFF96B3D1)),
    ),
  );
}

class XplmHtmlGlass extends StatelessWidget {
  const XplmHtmlGlass({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: const _HtmlSurfacePainter(),
    child: Padding(padding: padding.add(const EdgeInsets.all(1)), child: child),
  );
}

class XplmHtmlButton extends StatelessWidget {
  const XplmHtmlButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.height = 45,
    this.fontSize = 14,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final double height;
  final double fontSize;
  final bool busy;
  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onPressed == null && !busy ? .45 : 1,
    child: CustomPaint(
      painter: const _HtmlSurfacePainter(primary: true),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(25),
          onTap: busy ? null : onPressed,
          child: SizedBox(
            width: double.infinity,
            height: height,
            child: Center(
              child: busy
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        value: MediaQuery.of(context).disableAnimations
                            ? .75
                            : null,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      label,
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w400,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Transparent CSS Earth layer, rasterized from the HTML at 3x.
class XplmHtmlEarth extends StatelessWidget {
  const XplmHtmlEarth({super.key, required this.screen});
  final String screen;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: (constraints.maxWidth - 600) / 2,
          bottom: screen == 'servers' ? -172 : -221,
          width: 600,
          height: 400,
          child: IgnorePointer(
            child: Image.asset(
              'assets/brand/xplm_${screen}_earth.png',
              fit: BoxFit.fill,
              excludeFromSemantics: true,
            ),
          ),
        ),
      ],
    ),
  );
}

class _HtmlSurfacePainter extends CustomPainter {
  const _HtmlSurfacePainter({this.primary = false});
  final bool primary;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = Radius.circular(primary ? 25 : 17);
    final shape = RRect.fromRectAndRadius(rect.deflate(.5), radius);
    canvas.drawRRect(
      shape,
      Paint()
        ..color = primary ? const Color(0x30007CFF) : const Color(0x16008EFF)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, primary ? 8 : 4),
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..shader =
            (primary
                    ? const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF00ADFF), Color(0xFF0074F6)],
                      )
                    : const LinearGradient(
                        begin: Alignment(-.819, -.574),
                        end: Alignment(.819, .574),
                        colors: [
                          Color(0xFF06203C),
                          Color(0xFF06172D),
                          Color(0xFF092B50),
                        ],
                        stops: [0, .55, 1],
                      ))
                .createShader(rect),
    );
    canvas.save();
    canvas.clipRRect(shape);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.inflate(4).shift(const Offset(0, 2)),
        radius,
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = primary ? const Color(0x448DEEFF) : const Color(0x281A84DC)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.restore();
    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = primary ? const Color(0xFF008CFF) : const Color(0xFF1B466B),
    );
  }

  @override
  bool shouldRepaint(covariant _HtmlSurfacePainter oldDelegate) =>
      primary != oldDelegate.primary;
}

/// Original CSS flags. Other countries retain the existing native fallback.
class XplmHtmlFlag extends StatelessWidget {
  const XplmHtmlFlag({super.key, required this.code});
  final String code;
  @override
  Widget build(BuildContext context) {
    final normalized = code.toLowerCase();
    if (!const {
      'de',
      'fi',
      'bg',
      'fr',
      'nl',
      'us',
      'gb',
      'sg',
    }.contains(normalized)) {
      return XplmFlagCircle(code: code, size: 38);
    }
    return SizedBox(
      width: 38,
      height: 38,
      child: OverflowBox(
        maxWidth: 64,
        maxHeight: 64,
        child: Image.asset(
          'assets/brand/xplm_flags/$normalized.png',
          width: 64,
          height: 64,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}
