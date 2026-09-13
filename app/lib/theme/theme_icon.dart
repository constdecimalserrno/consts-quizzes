import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'broadcast.dart';

/// A drawn mark for each Theme.
///
/// Drawn rather than set in emoji: emoji are somebody else's artwork, they
/// render differently on every machine, and none of them belong to a 1993
/// broadcast set. These are built from the same handful of blunt shapes —
/// thick strokes, square caps, no curves where a corner will do — so that
/// twenty-four of them read as one family rather than a shelf of stickers.
class ThemeIcon extends StatelessWidget {
  const ThemeIcon({
    super.key,
    required this.theme,
    this.size = 26,
    this.color = Broadcast.gold,
  });

  final String theme;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _ThemePainter(theme: theme, color: color),
          isComplex: false,
        ),
      );
}

class _ThemePainter extends CustomPainter {
  _ThemePainter({required this.theme, required this.color});

  final String theme;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Everything is drawn on a 24x24 grid and scaled, so a mark keeps its
    // weight whether it sits in the theme strip or blown up on a card.
    canvas.scale(size.width / 24, size.height / 24);

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    _draw(canvas, stroke, fill);
  }

  void _line(Canvas c, Paint p, double x1, double y1, double x2, double y2) =>
      c.drawLine(Offset(x1, y1), Offset(x2, y2), p);

  void _box(Canvas c, Paint p, double l, double t, double r, double b) =>
      c.drawRect(Rect.fromLTRB(l, t, r, b), p);

  void _poly(Canvas c, Paint p, List<Offset> points) {
    final path = Path()..addPolygon(points, true);
    c.drawPath(path, p);
  }

  void _star(Canvas c, Paint p, Offset at, double r) {
    final points = <Offset>[];
    for (var i = 0; i < 10; i++) {
      final radius = i.isEven ? r : r * 0.44;
      final angle = -math.pi / 2 + i * math.pi / 5;
      points.add(at + Offset(math.cos(angle) * radius, math.sin(angle) * radius));
    }
    _poly(c, p, points);
  }

  void _draw(Canvas c, Paint s, Paint f) {
    switch (theme) {
      case 'General Knowledge':
        // A question mark, squared off.
        _line(c, s, 8, 7, 16, 7);
        _line(c, s, 16, 7, 16, 12);
        _line(c, s, 16, 12, 12, 12);
        _line(c, s, 12, 12, 12, 15);
        _box(c, f, 10.8, 17.5, 13.2, 20);

      case 'Entertainment: Books':
        _box(c, s, 4, 5, 12, 19);
        _box(c, s, 12, 5, 20, 19);
        _line(c, s, 12, 5, 12, 19);

      case 'Entertainment: Film':
        _box(c, s, 4, 6, 20, 18);
        for (var y = 7.5; y < 18; y += 3.4) {
          _box(c, f, 5.2, y, 7.2, y + 1.8);
          _box(c, f, 16.8, y, 18.8, y + 1.8);
        }

      case 'Entertainment: Music':
        _line(c, s, 10, 18, 10, 6);
        _line(c, s, 10, 6, 19, 4);
        _line(c, s, 19, 4, 19, 15);
        c.drawOval(Rect.fromLTWH(5, 15.5, 5.4, 4.4), f);
        c.drawOval(Rect.fromLTWH(14, 13, 5.4, 4.4), f);

      case 'Entertainment: Musicals & Theatres':
        // Two masks, reduced to their mouths.
        _poly(c, s, const [Offset(3, 5), Offset(11, 5), Offset(7, 15)]);
        _poly(c, s, const [Offset(13, 9), Offset(21, 9), Offset(17, 19)]);

      case 'Entertainment: Television':
        _box(c, s, 3, 8, 18, 19);
        _line(c, s, 18, 11, 21, 11);
        _line(c, s, 18, 16, 21, 16);
        _line(c, s, 7, 8, 4, 4);
        _line(c, s, 12, 8, 15, 4);

      case 'Entertainment: Video Games':
        _box(c, s, 3, 8, 21, 18);
        _line(c, s, 7, 11, 7, 15);
        _line(c, s, 5, 13, 9, 13);
        _box(c, f, 15, 11, 17.4, 13.4);
        _box(c, f, 11.6, 13.6, 14, 16);

      case 'Entertainment: Board Games':
        _box(c, s, 4, 4, 20, 20);
        for (var i = 0; i < 3; i++) {
          for (var j = 0; j < 3; j++) {
            if ((i + j).isEven) {
              final x = 4 + i * 5.33;
              final y = 4 + j * 5.33;
              _box(c, f, x, y, x + 5.33, y + 5.33);
            }
          }
        }

      case 'Entertainment: Comics':
        _box(c, s, 3, 5, 21, 16);
        _poly(c, s, const [Offset(7, 16), Offset(12, 16), Offset(7, 21)]);
        _line(c, s, 7, 9, 17, 9);
        _line(c, s, 7, 12.5, 14, 12.5);

      case 'Entertainment: Japanese Anime & Manga':
        // A single wide eye.
        _poly(c, s, const [Offset(3, 12), Offset(12, 5), Offset(21, 12), Offset(12, 19)]);
        c.drawCircle(const Offset(12, 12), 3.2, f);

      case 'Entertainment: Cartoon & Animations':
        c.drawCircle(const Offset(9, 12), 6, s);
        c.drawCircle(const Offset(17, 8), 3, s);
        c.drawCircle(const Offset(19, 16), 2.2, s);

      case 'Science & Nature':
        _line(c, s, 12, 21, 12, 11);
        _poly(c, s, const [Offset(12, 11), Offset(5, 8), Offset(12, 4)]);
        _poly(c, s, const [Offset(12, 11), Offset(19, 8), Offset(12, 4)]);

      case 'Science: Computers':
        _box(c, s, 4, 5, 20, 16);
        _box(c, f, 9, 18, 15, 20);
        _line(c, s, 7, 8.5, 12, 8.5);
        _line(c, s, 7, 12, 16, 12);

      case 'Science: Mathematics':
        _line(c, s, 4, 7, 10, 7);
        _line(c, s, 7, 4, 7, 10);
        _line(c, s, 14, 7, 20, 7);
        _line(c, s, 4, 14, 10, 14);
        _line(c, s, 4, 19, 10, 19);
        _line(c, s, 14, 14, 20, 20);
        _line(c, s, 20, 14, 14, 20);

      case 'Science: Gadgets':
        _box(c, s, 7, 3, 17, 21);
        _line(c, s, 9, 6.5, 15, 6.5);
        _box(c, f, 10.8, 16, 13.2, 18.4);
        _line(c, s, 17, 9, 21, 9);

      case 'Mythology':
        // A column.
        _line(c, s, 4, 5, 20, 5);
        _line(c, s, 4, 20, 20, 20);
        for (final x in <double>[7.5, 12, 16.5]) {
          _line(c, s, x, 5, x, 20);
        }

      case 'Sports':
        c.drawCircle(const Offset(12, 12), 8, s);
        _poly(c, s, const [Offset(12, 7), Offset(16, 10), Offset(14.5, 15), Offset(9.5, 15), Offset(8, 10)]);

      case 'Geography':
        c.drawCircle(const Offset(12, 12), 8.5, s);
        c.drawOval(Rect.fromCenter(center: const Offset(12, 12), width: 8, height: 17), s);
        _line(c, s, 3.5, 12, 20.5, 12);

      case 'History':
        c.drawCircle(const Offset(12, 12), 8.5, s);
        _line(c, s, 12, 6, 12, 12);
        _line(c, s, 12, 12, 16.5, 14);

      case 'Politics':
        _poly(c, s, const [Offset(3, 9), Offset(12, 3), Offset(21, 9)]);
        _line(c, s, 3, 20, 21, 20);
        for (final x in <double>[7.0, 12.0, 17.0]) {
          _line(c, s, x, 10.5, x, 18);
        }

      case 'Art':
        // A brush.
        _line(c, s, 5, 19, 14, 8);
        _poly(c, s, const [Offset(13, 6), Offset(17, 3), Offset(20, 6), Offset(16, 10)]);
        _box(c, f, 3.5, 18, 6.5, 21);

      case 'Celebrities':
        _star(c, f, const Offset(12, 11), 8);

      case 'Animals':
        // Ears and a snout.
        _poly(c, s, const [Offset(4, 4), Offset(9, 9), Offset(4, 12)]);
        _poly(c, s, const [Offset(20, 4), Offset(15, 9), Offset(20, 12)]);
        c.drawCircle(const Offset(12, 14), 6, s);
        c.drawCircle(const Offset(12, 15), 1.6, f);

      case 'Vehicles':
        _poly(c, s, const [Offset(3, 15), Offset(6, 9), Offset(17, 9), Offset(21, 15)]);
        _line(c, s, 3, 15, 21, 15);
        c.drawCircle(const Offset(7.5, 17.5), 2.6, s);
        c.drawCircle(const Offset(16.5, 17.5), 2.6, s);

      default:
        c.drawCircle(const Offset(12, 12), 7.5, s);
    }
  }

  @override
  bool shouldRepaint(_ThemePainter old) =>
      old.theme != theme || old.color != color;
}
