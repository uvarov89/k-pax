import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Full kaleid backdrop from k-pax.space: mesh prism, morph faces, stars
/// inside polygons, glare, sun flare, pointer look, scroll parallax.
class KpaxSpaceBackground extends StatefulWidget {
  const KpaxSpaceBackground({super.key, required this.child});

  final Widget child;

  @override
  State<KpaxSpaceBackground> createState() => _KpaxSpaceBackgroundState();
}

class _KpaxSpaceBackgroundState extends State<KpaxSpaceBackground>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker;
  Duration _elapsed = Duration.zero;
  Duration? _lastTick;
  Size _size = Size.zero;
  _SpaceScene? _scene;
  bool _paused = false;
  bool _reduce = false;

  double _aimX = 0;
  double _aimY = 0;
  double _lookX = 0;
  double _lookY = 0;
  double _parAim = 0;
  double _parY = 0;
  double _smooth = 0;
  double _glareAmt = 0;
  double _lastScrollY = 0;
  double _lastScrollMs = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _paused = state != AppLifecycleState.resumed;
    if (_paused) {
      _ticker.stop();
    } else if (!_ticker.isActive) {
      _lastTick = null;
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    if (!mounted || _paused) return;
    final prev = _lastTick ?? elapsed;
    _lastTick = elapsed;
    _elapsed = elapsed;
    var dtMs = (elapsed - prev).inMilliseconds.toDouble();
    if (dtMs < 0) dtMs = 0;
    if (dtMs > 34) dtMs = 34;
    final nowMs = elapsed.inMilliseconds.toDouble();
    _scene?.step(
      nowMs: nowMs,
      dtMs: dtMs,
      reduce: _reduce,
      lookX: _lookX,
      lookY: _lookY,
      parY: _parY,
      smooth: _smooth,
      glareAmt: _glareAmt,
      lastScrollMs: _lastScrollMs,
      onLook: (x, y) {
        _lookX = x;
        _lookY = y;
      },
      onPar: (v) => _parY = v,
      onGlare: (v) => _glareAmt = v,
      onSmooth: (v) => _smooth = v,
      aimX: _aimX,
      aimY: _aimY,
      parAim: _parAim,
      narrow: _size.width > 0 && _size.width < 800,
    );
    setState(() {});
  }

  void _ensureScene(Size size) {
    if (_scene != null &&
        (_size.width - size.width).abs() < 2 &&
        (_size.height - size.height).abs() < 140) {
      return;
    }
    _size = size;
    _scene = _SpaceScene.build(size, reduce: _reduce);
  }

  void _updateAim(Offset local) {
    if (_size.width <= 0 || _size.height <= 0 || _reduce) return;
    _aimX = (((local.dx / _size.width) - 0.5) * 2).clamp(-1.0, 1.0);
    _aimY = (((local.dy / _size.height) - 0.5) * 2).clamp(-1.0, 1.0);
  }

  bool _onScroll(ScrollNotification n) {
    if (_reduce || _size.height <= 0) return false;
    if (n is! ScrollUpdateNotification && n is! OverscrollNotification) {
      return false;
    }
    final now = _elapsed.inMilliseconds.toDouble();
    final y = n.metrics.pixels;
    var dt = _lastScrollMs == 0 ? 16.0 : (now - _lastScrollMs);
    if (dt < 16) dt = 16;
    final glide = _size.width < 800 ? 0.12 : 0.28;
    final denom = _size.width < 800 ? 2.4 : 1.1;
    final target = ((y - _lastScrollY) / dt / denom).clamp(-1.0, 1.0);
    _smooth += (target - _smooth) * glide;
    _lastScrollY = y;
    _lastScrollMs = now;
    final span = math.max(1.0, n.metrics.maxScrollExtent);
    _parAim = 0.5 - (y / span).clamp(0.0, 1.0);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    _reduce = MediaQuery.disableAnimationsOf(context);
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: MouseRegion(
        onHover: (e) => _updateAim(e.localPosition),
        onExit: (_) {
          _aimX = 0;
          _aimY = 0;
        },
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerHover: (e) => _updateAim(e.localPosition),
          onPointerMove: (e) => _updateAim(e.localPosition),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              if (size.width > 0 && size.height > 0) {
                _ensureScene(size);
              }
              return Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(
                    painter: _SpacePainter(
                      scene: _scene,
                      nowMs: _elapsed.inMilliseconds.toDouble(),
                      reduce: _reduce,
                      glareAmt: _glareAmt,
                      narrow: size.width < 800,
                    ),
                    size: Size.infinite,
                  ),
                  widget.child,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Star {
  _Star(this.x, this.y, this.r, this.a, this.tw, this.phase);
  final double x;
  final double y;
  final double r;
  final double a;
  final bool tw;
  final double phase;
}

class _Vert {
  _Vert(this.bx, this.by, this.phase, this.ax, this.ay)
      : x = bx,
        y = by;
  final double bx;
  final double by;
  final double phase;
  final double ax;
  final double ay;
  double x;
  double y;
}

class _Clock {
  _Clock({
    required this.morph,
    required this.morphT,
    required this.morphRate,
    required this.asQuad,
    required this.b,
    required this.e,
  }) : pivot = _Vert(b.x, b.y, 0, 0, 0);

  final bool morph;
  double morphT;
  final double morphRate;
  final bool asQuad;
  final _Vert b;
  final _Vert e;
  final _Vert pivot;
  double m = 0;
}

class _Shard {
  _Shard({
    required this.verts,
    required this.role,
    required this.clock,
    required this.layer,
    required this.cx,
    required this.cy,
    required this.baseR,
    required this.baseG,
    required this.baseB,
    required this.baseA,
    required this.shadeDir,
    required this.shadeAmp,
    required this.shadeT,
    required this.shadeRate,
    required this.baseX,
    required this.baseY,
    required this.baseZ,
    required this.ampX,
    required this.ampY,
    required this.ampZ,
    required this.dirX,
    required this.dirY,
    required this.dirZ,
    required this.phase,
    required this.glare,
    required this.glareAng,
    required this.glareU,
    required this.glareV,
    required this.glareA,
  })  : rotX = baseX,
        rotY = baseY,
        rotZ = baseZ,
        prevY = baseY,
        glint = baseY;

  final List<_Vert> verts;
  final String role;
  final _Clock clock;
  int layer;
  final double cx;
  final double cy;
  final double baseR;
  final double baseG;
  final double baseB;
  final double baseA;
  final double shadeDir;
  final double shadeAmp;
  double shadeT;
  final double shadeRate;
  final double baseX;
  final double baseY;
  final double baseZ;
  final double ampX;
  double ampY;
  final double ampZ;
  final double dirX;
  final double dirY;
  final double dirZ;
  final double phase;
  final bool glare;
  final double glareAng;
  final double glareU;
  final double glareV;
  final double glareA;
  bool sun = false;
  double glint;
  double prevY;
  double rotX;
  double rotY;
  double rotZ;
  bool hidden = false;
  double minX = 0;
  double minY = 0;
  double maxX = 0;
  double maxY = 0;
}

class _Flare {
  bool on = false;
  double t0 = 0;
  double dur = 520;
  double done = 0;
}

class _SpaceScene {
  _SpaceScene({
    required this.w,
    required this.h,
    required this.stars,
    required this.mesh,
    required this.shards,
  });

  final double w;
  final double h;
  final List<_Star> stars;
  final List<_Vert> mesh;
  final List<_Shard> shards;
  final _Flare flare = _Flare();
  _Shard? sun;

  static double rnd(double n) {
    final x = math.sin(n * 127.1 + 311.7) * 43758.5453;
    return x - x.floorToDouble();
  }

  static double clamp(double v, double a, double b) =>
      v < a ? a : (v > b ? b : v);

  static double morphM(_Clock clock, bool reduce) {
    if (!clock.morph || reduce) return clock.asQuad ? 1 : 0;
    return 0.5 + 0.5 * math.sin(clock.morphT);
  }

  static bool faceOn(_Shard s) => !(s.role == 'shrink' && s.clock.m > 0.97);

  static _SpaceScene build(Size size, {required bool reduce}) {
    final w = size.width;
    final h = size.height;
    final stars = <_Star>[];
    var count = (w * h / 48000).round();
    if (count < 18) count = 18;
    if (count > 48) count = 48;
    for (var i = 0; i < count; i++) {
      stars.add(
        _Star(
          rnd(i + 1.0) * w,
          rnd(i + 19.0) * h,
          rnd(i + 3.0) > 0.9 ? 1.8 : 0.9 + rnd(i + 8.0) * 0.7,
          0.72 + rnd(i + 5.0) * 0.28,
          rnd(i + 11.0) > 0.88,
          rnd(i + 13.0) * math.pi * 2,
        ),
      );
    }

    final cols = w < 700 ? 6 : w < 1200 ? 9 : 12;
    final pad = math.max(78.0, math.min(w, h) * 0.1);
    final gw = w + pad * 2;
    final gh = h + pad * 2;
    var rows = (cols * gh / gw).round();
    if (rows < 5) rows = 5;
    final mesh = <_Vert>[];
    for (var r = 0; r <= rows; r++) {
      for (var c = 0; c <= cols; c++) {
        var x = -pad + (c / cols) * gw;
        var y = -pad + (r / rows) * gh;
        final edge = c == 0 || r == 0 || c == cols || r == rows;
        if (!edge && c > 0 && c < cols) {
          x += (rnd(r * 40.0 + c) - 0.5) * (w / cols) * 0.58;
        }
        if (!edge && r > 0 && r < rows) {
          y += (rnd(c * 37.0 + r + 9) - 0.5) * (h / rows) * 0.58;
        }
        mesh.add(
          _Vert(
            x,
            y,
            rnd(r * 17.0 + c + 3) * 6.2832,
            edge ? 0 : (rnd(r * 9.0 + c + 5) - 0.5) * 14,
            edge ? 0 : (rnd(c * 8.0 + r + 7) - 0.5) * 14,
          ),
        );
      }
    }

    final shards = <_Shard>[];
    final stride = cols + 1;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final idx = r * stride + c;
        final a = mesh[idx];
        final b = mesh[idx + 1];
        final d = mesh[idx + stride];
        final e = mesh[idx + stride + 1];
        final n = r * cols + c + 3.0;
        final clock = _Clock(
          morph: rnd(n + 53) > 0.18,
          morphT: rnd(n + 57) * 6.2832,
          morphRate: 0.55 + rnd(n + 59) * 0.95,
          asQuad: rnd(n + 61) > 0.45,
          b: b,
          e: e,
        );
        clock.m = morphM(clock, reduce);
        shards.add(_makeShard([a, b, clock.pivot, d], 'grow', clock, shards.length + 3.0));
        shards.add(_makeShard([clock.pivot, e, d], 'shrink', clock, shards.length + 3.0));
      }
    }

    final scene = _SpaceScene(w: w, h: h, stars: stars, mesh: mesh, shards: shards);
    _Shard? best;
    var score = 1e9;
    for (final s in shards) {
      if (!faceOn(s)) continue;
      final nx = s.cx / w;
      final ny = s.cy / h;
      if (nx < 0.6 || nx > 0.9 || ny < 0.06 || ny > 0.42) continue;
      final sc = (nx - 0.76).abs() + (ny - 0.16).abs();
      if (sc < score) {
        score = sc;
        best = s;
      }
    }
    if (best != null) {
      best.sun = true;
      best.layer = 2;
      best.ampY = 6;
      best.glint = best.baseY + best.dirY * 1.15;
      best.prevY = best.baseY;
      scene.sun = best;
    }
    return scene;
  }

  static _Shard _makeShard(
    List<_Vert> refs,
    String role,
    _Clock clock,
    double n,
  ) {
    var cx = 0.0;
    var cy = 0.0;
    for (final v in refs) {
      cx += v.bx;
      cy += v.by;
    }
    cx /= refs.length;
    cy /= refs.length;
    final layer = rnd(n * 5) > 0.66 ? 2 : rnd(n + 4) > 0.5 ? 1 : 0;
    return _Shard(
      verts: refs,
      role: role,
      clock: clock,
      layer: layer,
      cx: cx,
      cy: cy,
      baseR: 8 + rnd(n + 63) * 26,
      baseG: 18 + rnd(n + 67) * 36,
      baseB: 44 + rnd(n + 71) * 54,
      baseA: 0.3 + rnd(n + 73) * 0.16,
      shadeDir: rnd(n + 51) > 0.5 ? 1 : -1,
      shadeAmp: 0.14 + rnd(n + 79) * 0.18,
      shadeT: rnd(n + 83) * math.pi * 2,
      shadeRate: 0.4 + rnd(n + 89) * 1.15,
      baseX: (rnd(n + 2) - 0.5) * 4,
      baseY: (rnd(n + 6) - 0.5) * 4,
      baseZ: (rnd(n + 8) - 0.5) * 1.6,
      ampX: 3 + rnd(n + 11) * 4,
      ampY: 3 + rnd(n + 15) * 4,
      ampZ: 1 + rnd(n + 19) * 2,
      dirX: rnd(n + 21) > 0.5 ? 1 : -1,
      dirY: rnd(n + 23) > 0.5 ? 1 : -1,
      dirZ: rnd(n + 27) > 0.5 ? 1 : -1,
      phase: rnd(n + 31) * math.pi * 2,
      glare: rnd(n + 91) > 0.72,
      glareAng: rnd(n + 93) * 6.2832,
      glareU: 0.2 + rnd(n + 97) * 0.6,
      glareV: 0.16 + rnd(n + 101) * 0.62,
      glareA: 0.34 + rnd(n + 103) * 0.4,
    );
  }

  void step({
    required double nowMs,
    required double dtMs,
    required bool reduce,
    required double lookX,
    required double lookY,
    required double parY,
    required double smooth,
    required double glareAmt,
    required double lastScrollMs,
    required double aimX,
    required double aimY,
    required double parAim,
    required bool narrow,
    required void Function(double x, double y) onLook,
    required void Function(double v) onPar,
    required void Function(double v) onGlare,
    required void Function(double v) onSmooth,
  }) {
    final step = dtMs / 16.67;
    var lx = lookX;
    var ly = lookY;
    var py = parY;
    var sm = smooth;
    var glare = glareAmt;

    if (!reduce) {
      if (nowMs - lastScrollMs > 90) {
        sm *= math.pow(0.88, step).toDouble();
      }
      if (sm.abs() < 0.012) sm = 0;
      var follow = 1 - math.pow(0.93, step).toDouble();
      var parFollow = 1 - math.pow(narrow ? 0.96 : 0.92, step).toDouble();
      if (narrow) {
        if (follow > 0.08) follow = 0.08;
        if (parFollow > 0.06) parFollow = 0.06;
      }
      lx += (aimX - lx) * follow;
      ly += (aimY - ly) * follow;
      py += (parAim - py) * parFollow;
      if (sm.abs() > 0.05) {
        glare += (1 - glare) * (1 - math.pow(0.55, step).toDouble());
      } else {
        glare *= math.pow(0.93, step).toDouble();
      }
      if (glare < 0.02) glare = 0;

      final ease = 1 - math.pow(0.925, step).toDouble();
      for (final s in shards) {
        final depth = s.layer == 2 ? 1.0 : s.layer == 1 ? 0.72 : 0.48;
        final wob = math.sin(nowMs * 0.00045 + s.phase) * 2.4;
        s.rotX += (s.baseX +
                    clamp(sm * s.ampX * s.dirX * depth, -7, 7) +
                    wob -
                    s.rotX) *
            ease;
        s.rotY += (s.baseY +
                    clamp(sm * s.ampY * s.dirY * depth, -7, 7) +
                    wob * 0.65 -
                    s.rotY) *
            ease;
        s.rotZ += (s.baseZ +
                    clamp(sm * s.ampZ * s.dirZ * depth, -3, 3) -
                    s.rotZ) *
            ease;
        if (s.role == 'grow' && s.clock.morph) {
          s.clock.morphT += 0.008 * s.clock.morphRate * step;
        }
        s.shadeT += 0.009 * s.shadeRate * step;
      }

      final sunShard = sun;
      if (sunShard != null && !flare.on) {
        final crossed = (sunShard.prevY - sunShard.glint) *
                    (sunShard.rotY - sunShard.glint) <=
                0 &&
            (sunShard.rotY - sunShard.prevY).abs() > 0.02;
        if (crossed && sm.abs() > 0.15 && nowMs - flare.done > 1700) {
          flare.on = true;
          flare.t0 = nowMs;
          flare.dur = 360 + rnd((nowMs.floor() % 97).toDouble()) * 300;
        }
      }
      if (sunShard != null) sunShard.prevY = sunShard.rotY;
      if (flare.on && nowMs - flare.t0 > flare.dur) {
        flare.on = false;
        flare.done = nowMs;
      }
    }

    onLook(lx, ly);
    onPar(py);
    onGlare(glare);
    onSmooth(sm);

    final shiftX = reduce ? 0.0 : lx * 22;
    final shiftY = reduce ? 0.0 : ly * 14 + py * 36;
    final boost = reduce ? 0.0 : (1 + sm.abs() * (narrow ? 0.2 : 1.4));
    for (final v in mesh) {
      final wob = reduce ? 0.0 : math.sin(nowMs * 0.0005 + v.phase);
      v.x = v.bx + wob * v.ax * boost + shiftX;
      v.y = v.by + wob * v.ay * boost + shiftY;
    }
    for (final s in shards) {
      if (s.role != 'grow') continue;
      final m = morphM(s.clock, reduce);
      s.clock.m = m;
      s.clock.pivot.x = s.clock.b.x + (s.clock.e.x - s.clock.b.x) * m;
      s.clock.pivot.y = s.clock.b.y + (s.clock.e.y - s.clock.b.y) * m;
    }
  }
}

class _SpacePainter extends CustomPainter {
  _SpacePainter({
    required this.scene,
    required this.nowMs,
    required this.reduce,
    required this.glareAmt,
    required this.narrow,
  });

  final _SpaceScene? scene;
  final double nowMs;
  final bool reduce;
  final double glareAmt;
  final bool narrow;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF020712));

    final scene = this.scene;
    if (scene == null) return;

    final driftX = reduce ? 0.0 : (nowMs * 0.034) % w;
    final driftY = reduce ? 0.0 : (nowMs * 0.016) % h;
    final starPaint = Paint()..style = PaintingStyle.fill;
    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeJoin = StrokeJoin.miter;

    for (final s in scene.shards) {
      s.hidden = !_SpaceScene.faceOn(s);
      if (s.hidden) continue;
      _place(s);
      final tone = _toneOf(s);
      final bend = 16.0 + s.layer * 7;
      final ox = _SpaceScene.clamp(s.rotY * bend, -120, 120);
      final oy = _SpaceScene.clamp(s.rotX * bend, -120, 120);

      final path = _polyPath(s);
      canvas.drawPath(path, tone.$1);

      for (final dot in scene.stars) {
        final sx = ((dot.x + driftX + ox) % w + w) % w;
        final sy = ((dot.y + driftY + oy) % h + h) % h;
        if (sx < s.minX || sx > s.maxX || sy < s.minY || sy > s.maxY) continue;
        if (!_hit(sx, sy, s.verts)) continue;
        var alpha = dot.a;
        if (dot.tw && !reduce) {
          alpha = dot.a * (0.55 + 0.45 * math.sin(nowMs * 0.0012 + dot.phase));
        }
        starPaint.color = Color.fromRGBO(244, 248, 255, alpha.clamp(0.0, 1.0));
        canvas.drawCircle(Offset(sx, sy), dot.r + 0.35, starPaint);
      }

      edgePaint.color = tone.$2;
      canvas.drawPath(path, edgePaint);

      if (s.glare && glareAmt > 0.02) _drawGlare(canvas, s, glareAmt);
      if (s.sun && scene.flare.on) _drawFlare(canvas, s, nowMs, scene.flare);
    }

    final vig = Paint()
      ..shader = ui.Gradient.radial(
        Offset(w * 0.5, h * 0.4),
        math.max(w, h) * 0.78,
        const [Color(0x00020712), Color(0x33020712)],
        [
          (math.min(w, h) * 0.15) / (math.max(w, h) * 0.78),
          1.0,
        ],
      );
    canvas.drawRect(Offset.zero & size, vig);
  }

  void _place(_Shard s) {
    var minX = 1e9, minY = 1e9, maxX = -1e9, maxY = -1e9;
    for (final p in s.verts) {
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
    }
    s.minX = minX;
    s.minY = minY;
    s.maxX = maxX;
    s.maxY = maxY;
  }

  Path _polyPath(_Shard s) {
    final path = Path();
    final poly = s.verts;
    path.moveTo(poly[0].x, poly[0].y);
    for (var i = 1; i < poly.length; i++) {
      path.lineTo(poly[i].x, poly[i].y);
    }
    path.close();
    return path;
  }

  (Paint, Color) _toneOf(_Shard s) {
    final wave = reduce ? 0.6 : (0.5 + 0.5 * math.sin(s.shadeT));
    final lift = s.shadeDir * (3 + s.shadeAmp * 12) * wave;
    Color rgb(double extra) {
      final t = lift + extra;
      return Color.fromARGB(
        240,
        (3 + t * 0.22).clamp(1, 16).round(),
        (8 + t * 0.38).clamp(4, 24).round(),
        (18 + t * 0.7).clamp(10, 40).round(),
      );
    }

    final edge = Color.fromRGBO(
      140,
      164,
      188,
      (0.06 + 0.04 * wave).clamp(0.0, 1.0),
    );
    if (narrow) {
      return (Paint()..color = rgb(1), edge);
    }
    final first = Offset(s.verts.first.x, s.verts.first.y);
    final last = Offset(s.verts.last.x, s.verts.last.y);
    return (
      Paint()
        ..shader = ui.Gradient.linear(first, last, [rgb(-2.5), rgb(4)]),
      edge,
    );
  }

  bool _hit(double x, double y, List<_Vert> poly) {
    final n = poly.length;
    var j = n - 1;
    var inside = false;
    for (var i = 0; i < n; i++) {
      final yi = poly[i].y;
      final yj = poly[j].y;
      final xi = poly[i].x;
      final xj = poly[j].x;
      if (((yi > y) != (yj > y)) &&
          (x < (xj - xi) * (y - yi) / ((yj - yi).abs() < 1e-4 ? 1e-4 : (yj - yi)) + xi)) {
        inside = !inside;
      }
      j = i;
    }
    return inside;
  }

  void _drawGlare(Canvas canvas, _Shard s, double glareAmt) {
    final poly = s.verts;
    final n = poly.length;
    if (n < 2) return;
    final pulse = glareAmt * (0.62 + 0.38 * math.sin(s.shadeT * 0.7 + s.phase));
    final start = (s.glareU * n).floor() % n;
    final count = s.glareV > 0.62 ? 2 : 1;
    for (var e = 0; e < count; e++) {
      final i = (start + e) % n;
      final a = poly[i];
      final b = poly[(i + 1) % n];
      final len = math.sqrt(
        (b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y),
      );
      if (len < 10) continue;
      final alpha = math.min(1.0, s.glareA * pulse);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = narrow ? 1.6 : 2.2;
      if (narrow) {
        paint.color = Color.fromRGBO(255, 255, 255, alpha);
      } else {
        paint.shader = ui.Gradient.linear(
          Offset(a.x, a.y),
          Offset(b.x, b.y),
          [
            const Color(0x00FFFFFF),
            Color.fromRGBO(210, 230, 255, 0.25 * alpha),
            Color.fromRGBO(255, 255, 255, alpha),
            Color.fromRGBO(210, 230, 255, 0.25 * alpha),
            const Color(0x00FFFFFF),
          ],
          const [0.0, 0.22, 0.5, 0.78, 1.0],
        );
      }
      canvas.drawLine(Offset(a.x, a.y), Offset(b.x, b.y), paint);
    }
  }

  void _drawFlare(Canvas canvas, _Shard s, double nowMs, _Flare flare) {
    final t = (nowMs - flare.t0) / flare.dur;
    if (t < 0 || t > 1) return;
    final poly = s.verts;
    final n = poly.length;
    var best = 0;
    var bestLen = 0.0;
    for (var i = 0; i < n; i++) {
      final a = poly[i];
      final b = poly[(i + 1) % n];
      final len = math.sqrt(
        (b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y),
      );
      if (len > bestLen) {
        bestLen = len;
        best = i;
      }
    }
    if (bestLen < 10) return;
    final a = poly[best];
    final b = poly[(best + 1) % n];
    final pulse = math.sin(t * math.pi);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..shader = ui.Gradient.linear(
        Offset(a.x, a.y),
        Offset(b.x, b.y),
        [
          const Color(0x00FFFFFF),
          Color.fromRGBO(255, 255, 255, 0.95 * pulse),
          const Color(0x00FFFFFF),
        ],
        const [0.0, 0.5, 1.0],
      );
    canvas.drawLine(Offset(a.x, a.y), Offset(b.x, b.y), paint);
  }

  @override
  bool shouldRepaint(covariant _SpacePainter oldDelegate) {
    return oldDelegate.nowMs != nowMs ||
        oldDelegate.scene != scene ||
        oldDelegate.reduce != reduce ||
        oldDelegate.glareAmt != glareAmt ||
        oldDelegate.narrow != narrow;
  }
}
