import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'broadcast.dart';

/// The set, with depth: a painted back wall that drifts.
///
/// Three layers, slowest and faintest at the back, so the studio has somewhere
/// to be rather than being a flat gradient. The pattern is the confetti a 1993
/// set was actually painted with — triangles, squiggles, dots — scattered on a
/// grid and nudged per cell so it does not read as wallpaper.
///
/// Motion is one slow drift, not an effect: at this speed nothing on screen
/// appears to move while you are reading, and the depth is only obvious if you
/// look away and back. Honoured off entirely when the platform asks for
/// reduced motion.
class SetBackdrop extends StatefulWidget {
  const SetBackdrop({super.key, this.child});

  final Widget? child;

  @override
  State<SetBackdrop> createState() => _SetBackdropState();
}

class _SetBackdropState extends State<SetBackdrop>
    with SingleTickerProviderStateMixin {
  /// One long cycle drives every layer; each reads it at its own rate, which
  /// is what makes the layers separate in depth.
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 90),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion stops the drift outright rather than merely hiding it:
    // an animation that never ends is also an animation a test can never wait
    // out, and a set that holds still is the honest answer to both.
    final still = MediaQuery.disableAnimationsOf(context);
    if (still && _drift.isAnimating) {
      _drift.stop();
    } else if (!still && !_drift.isAnimating) {
      _drift.repeat();
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return DecoratedBox(
      decoration: Broadcast.set,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _drift,
              builder: (context, _) => CustomPaint(
                size: Size.infinite,
                painter: _ConfettiPainter(still ? 0 : _drift.value),
              ),
            ),
          ),
          // Darkened at the edges so the middle of the set reads as the lit
          // part and the pattern falls away rather than stopping at the frame.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.25),
                radius: 1.0,
                colors: [Color(0x00000000), Color(0x66000914)],
                stops: [0.55, 1],
              ),
            ),
          ),
          if (widget.child != null) widget.child!,
          const Scanlines(),
        ],
      ),
    );
  }
}

/// Two grids of set confetti at different sizes and speeds.
class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.t);

  /// 0…1 through the drift cycle.
  final double t;

  /// Back layer first: bigger, fainter, slower.
  static const _layers = [
    (tile: 300.0, speed: 0.45, alpha: 0.030, scale: 1.15),
    (tile: 168.0, speed: 1.0, alpha: 0.042, scale: 0.62),
  ];

  static const _ink = [Broadcast.cyan, Broadcast.magenta, Broadcast.gold];

  @override
  void paint(Canvas canvas, Size size) {
    for (final layer in _layers) {
      _paintLayer(
        canvas,
        size,
        tile: layer.tile,
        alpha: layer.alpha,
        scale: layer.scale,
        // Up and to the right, the way a set's painted flats were lit to
        // travel. A whole tile per cycle, so the loop never shows a seam.
        dx: t * layer.speed * layer.tile,
        dy: -t * layer.speed * layer.tile * 0.6,
      );
    }
  }

  void _paintLayer(
    Canvas canvas,
    Size size, {
    required double tile,
    required double alpha,
    required double scale,
    required double dx,
    required double dy,
  }) {
    final ox = dx % tile;
    final oy = dy % tile;
    final cols = (size.width / tile).ceil() + 2;
    final rows = (size.height / tile).ceil() + 2;

    for (var r = -1; r < rows; r++) {
      for (var c = -1; c < cols; c++) {
        // A hash of the cell, not the screen position, so a shape keeps its
        // kind and colour as the grid slides under the window.
        final seed = (c * 73856093) ^ (r * 19349663);
        final rand = math.Random(seed);
        final x = c * tile + ox + rand.nextDouble() * tile * 0.55;
        final y = r * tile + oy + rand.nextDouble() * tile * 0.55;
        final paint = Paint()
          ..color = _ink[seed.abs() % _ink.length].withValues(alpha: alpha)
          ..style = rand.nextBool() ? PaintingStyle.stroke : PaintingStyle.fill
          ..strokeWidth = 3 * scale
          ..strokeCap = StrokeCap.square
          ..strokeJoin = StrokeJoin.miter;

        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(rand.nextInt(4) * math.pi / 2);
        canvas.scale(scale);
        switch (seed.abs() % 4) {
          case 0:
            _triangle(canvas, paint);
          case 1:
            _squiggle(canvas, paint..style = PaintingStyle.stroke);
          case 2:
            _dots(canvas, paint..style = PaintingStyle.fill);
          default:
            _bars(canvas, paint);
        }
        canvas.restore();
      }
    }
  }

  void _triangle(Canvas c, Paint p) => c.drawPath(
    Path()..addPolygon(const [
      Offset(0, -16),
      Offset(15, 12),
      Offset(-15, 12),
    ], true),
    p,
  );

  void _squiggle(Canvas c, Paint p) {
    final path = Path()..moveTo(-20, 0);
    for (var i = 0; i < 4; i++) {
      path.lineTo(-20 + i * 10 + 5, i.isEven ? -9.0 : 9.0);
      path.lineTo(-20 + i * 10 + 10, 0);
    }
    c.drawPath(path, p);
  }

  void _dots(Canvas c, Paint p) {
    for (var i = 0; i < 3; i++) {
      c.drawRect(Rect.fromLTWH(-18 + i * 14.0, -4, 8, 8), p);
    }
  }

  void _bars(Canvas c, Paint p) {
    for (var i = 0; i < 3; i++) {
      c.drawRect(Rect.fromLTWH(-15.0, -14 + i * 11.0, 30, 5), p);
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
