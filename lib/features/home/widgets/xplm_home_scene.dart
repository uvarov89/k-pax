import 'package:flutter/material.dart';

/// Original HTML artwork in separate layers. Only the shield moves;
/// VPN state and all interactive controls remain outside this decoration.
class XplmHomeScene extends StatefulWidget {
  const XplmHomeScene({super.key, required this.connected, this.busy = false});
  final bool connected;
  final bool busy;

  @override
  State<XplmHomeScene> createState() => _XplmHomeSceneState();
}

class _XplmHomeSceneState extends State<XplmHomeScene>
    with TickerProviderStateMixin {
  late final AnimationController _tone;
  late final AnimationController _pulse;
  bool _pulsing = false;
  bool _reduceMotion = false;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _tone = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
      value: widget.connected ? 1 : 0,
    );
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _visible = TickerMode.valuesOf(context).enabled;
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant XplmHomeScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connected != widget.connected ||
        oldWidget.busy != widget.busy) {
      _syncMotion();
    }
  }

  void _syncMotion() {
    final target = widget.connected ? 1.0 : 0.0;
    if (_reduceMotion || !_visible) {
      _tone.stop();
      _tone.value = target;
      _pulse.stop();
      _pulse.value = 0;
      _pulsing = false;
      return;
    }
    _tone.animateTo(target, curve: Curves.easeInOutCubic);
    if (widget.busy && !_pulsing) {
      _pulsing = true;
      _pulse.repeat(reverse: true);
    } else if (!widget.busy && _pulsing) {
      _pulsing = false;
      _pulse.stop();
      _pulse.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _tone.dispose();
    _pulse.dispose();
    super.dispose();
  }

  ColorFilter _color(double tone, {double pulse = 0}) {
    final saturation = .4 + .6 * tone;
    final brightness = .84 + .16 * tone + .04 * pulse;
    final r = (1 - saturation) * .2126;
    final g = (1 - saturation) * .7152;
    final b = (1 - saturation) * .0722;
    return ColorFilter.matrix([
      (r + saturation) * brightness,
      g * brightness,
      b * brightness,
      0,
      0,
      r * brightness,
      (g + saturation) * brightness,
      b * brightness,
      0,
      0,
      r * brightness,
      g * brightness,
      (b + saturation) * brightness,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ]);
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final earth = Image.asset(
            'assets/brand/xplm_home_earth.png',
            width: 600,
            height: 500,
            fit: BoxFit.fill,
            gaplessPlayback: true,
          );
          final shield = Image.asset(
            'assets/brand/xplm_home_shield.png',
            width: 600,
            height: 500,
            fit: BoxFit.fill,
            gaplessPlayback: true,
          );
          return AnimatedBuilder(
            animation: Listenable.merge([_tone, _pulse]),
            builder: (context, child) {
              final pulse = Curves.easeInOut.transform(_pulse.value);
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    top: 0,
                    left: (constraints.maxWidth - 600) / 2,
                    width: 600,
                    height: 500,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ColorFiltered(
                          colorFilter: _color(_tone.value),
                          child: earth,
                        ),
                        Positioned(
                          left: 185,
                          top: 0,
                          width: 230,
                          height: 225,
                          child: Opacity(
                            opacity: .28 * pulse,
                            child: const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: RadialGradient(
                                  colors: [
                                    Color(0xFF00AAFF),
                                    Color(0x0000AAFF),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Transform.scale(
                          key: const ValueKey('xplm-shield-motion'),
                          scale: 1 + .018 * pulse,
                          alignment: const Alignment(0, -.562),
                          child: ColorFiltered(
                            colorFilter: _color(_tone.value, pulse: pulse),
                            child: shield,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    ),
  );
}
