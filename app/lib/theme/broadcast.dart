import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The look of a broadcast set, circa 1993.
///
/// Not a page: a studio. Deep set-navy falling to violet, display type in
/// beveled gold, and three neon accents rather than one — the era was garish
/// and a single tasteful accent would read as a modern web page wearing a
/// costume.
abstract final class Broadcast {
  /// Set walls, lit from the middle.
  static const setDeep = Color(0xFF080C33);
  static const setNavy = Color(0xFF141B5C);
  static const setViolet = Color(0xFF3A1F6E);

  /// The display gold, used for the show's name, the clock, and bevels.
  static const gold = Color(0xFFFFC12B);
  static const goldDeep = Color(0xFFB37A00);

  /// Neon. Magenta leads; cyan supports.
  static const magenta = Color(0xFFFF2E88);
  static const cyan = Color(0xFF35E0F2);

  static const chalk = Color(0xFFF6F4EC);
  static const chalkDim = Color(0xFFA8A7C4);

  /// Podium faces.
  static const podium = Color(0xFF1D2470);
  static const podiumEdge = Color(0xFF4B56C9);

  static const wide = 720.0;

  static TextStyle display(double size, {Color color = gold}) =>
      GoogleFonts.bungee(
        fontSize: size,
        color: color,
        height: 1.05,
        letterSpacing: size * 0.01,
      );

  static TextStyle body(double size,
          {Color color = chalk, FontWeight weight = FontWeight.w600}) =>
      GoogleFonts.archivo(
        fontSize: size,
        color: color,
        fontWeight: weight,
        height: 1.25,
      );

  /// The hard offset shadow that makes a podium look like an object.
  static List<BoxShadow> get bevel => const [
        BoxShadow(color: Color(0xFF000B33), offset: Offset(0, 5), blurRadius: 0),
      ];

  static BoxDecoration get set => const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.35),
          radius: 1.1,
          colors: [setViolet, setNavy, setDeep],
          stops: [0, 0.55, 1],
        ),
      );
}

/// Scanlines over the whole set.
///
/// Three pixels apart and barely visible: enough that the screen reads as a
/// broadcast rather than a document, not so much that anyone has to read
/// through them.
class Scanlines extends StatelessWidget {
  const Scanlines({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: CustomPaint(size: Size.infinite, painter: _ScanlinePainter()),
      );
}

class _ScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.16);
    for (var y = 0.0; y < size.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), paint);
    }
  }

  @override
  bool shouldRepaint(_ScanlinePainter oldDelegate) => false;
}
