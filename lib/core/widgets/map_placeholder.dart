import 'package:flutter/material.dart';

/// Drop-in replacement for [GoogleMap] when the Maps API key is unavailable.
/// Renders a styled pseudo-map background with a centred notice.
class MapPlaceholder extends StatelessWidget {
  const MapPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Map-like painted background ──────────────────────────────
        CustomPaint(painter: _MapGridPainter()),

        // ── Centre notice ────────────────────────────────────────────
        Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.90),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.10),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.map_outlined, size: 52, color: Colors.grey[400]),
                const SizedBox(height: 10),
                Text(
                  'Maps API not available',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'A valid Google Maps API key is required\nto display the interactive map.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey[500], height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Painter ────────────────────────────────────────────────────────────────────

class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Base tile colour (Google Maps light style)
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = const Color(0xFFE8EBE4),
    );

    // "Park" blocks
    final parkPaint = Paint()..color = const Color(0xFFC8D8C0);
    canvas.drawRect(Rect.fromLTWH(w * 0.05, h * 0.55, w * 0.18, h * 0.30), parkPaint);
    canvas.drawRect(Rect.fromLTWH(w * 0.70, h * 0.10, w * 0.25, h * 0.22), parkPaint);

    // Building blocks
    final buildPaint = Paint()..color = const Color(0xFFCDD0CA);
    final blocks = [
      Rect.fromLTWH(w * 0.08, h * 0.08, w * 0.12, h * 0.10),
      Rect.fromLTWH(w * 0.24, h * 0.05, w * 0.10, h * 0.14),
      Rect.fromLTWH(w * 0.40, h * 0.08, w * 0.14, h * 0.08),
      Rect.fromLTWH(w * 0.60, h * 0.35, w * 0.12, h * 0.12),
      Rect.fromLTWH(w * 0.76, h * 0.40, w * 0.18, h * 0.10),
      Rect.fromLTWH(w * 0.12, h * 0.28, w * 0.10, h * 0.18),
      Rect.fromLTWH(w * 0.30, h * 0.30, w * 0.16, h * 0.10),
      Rect.fromLTWH(w * 0.55, h * 0.60, w * 0.14, h * 0.16),
      Rect.fromLTWH(w * 0.76, h * 0.62, w * 0.18, h * 0.20),
      Rect.fromLTWH(w * 0.08, h * 0.72, w * 0.12, h * 0.12),
      Rect.fromLTWH(w * 0.28, h * 0.68, w * 0.16, h * 0.18),
    ];
    for (final b in blocks) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(b, const Radius.circular(2)),
        buildPaint,
      );
    }

    // Main roads (wide, light)
    final mainRoad = Paint()
      ..color = Colors.white
      ..strokeWidth = w * 0.035
      ..strokeCap = StrokeCap.round;

    // Horizontal main roads
    canvas.drawLine(Offset(0, h * 0.22), Offset(w, h * 0.22), mainRoad);
    canvas.drawLine(Offset(0, h * 0.52), Offset(w, h * 0.52), mainRoad);
    canvas.drawLine(Offset(0, h * 0.82), Offset(w, h * 0.82), mainRoad);

    // Vertical main roads
    canvas.drawLine(Offset(w * 0.22, 0), Offset(w * 0.22, h), mainRoad);
    canvas.drawLine(Offset(w * 0.55, 0), Offset(w * 0.55, h), mainRoad);
    canvas.drawLine(Offset(w * 0.82, 0), Offset(w * 0.82, h), mainRoad);

    // Secondary roads (narrower)
    final secRoad = Paint()
      ..color = Colors.white
      ..strokeWidth = w * 0.018
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(0, h * 0.37), Offset(w, h * 0.37), secRoad);
    canvas.drawLine(Offset(0, h * 0.67), Offset(w, h * 0.67), secRoad);
    canvas.drawLine(Offset(w * 0.38, 0), Offset(w * 0.38, h), secRoad);
    canvas.drawLine(Offset(w * 0.68, 0), Offset(w * 0.68, h), secRoad);

    // Diagonal arterial
    final diagRoad = Paint()
      ..color = const Color(0xFFF5E9C8)
      ..strokeWidth = w * 0.028
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, h * 0.15), Offset(w * 0.45, h * 0.88), diagRoad);
    canvas.drawLine(Offset(w * 0.35, 0), Offset(w, h * 0.70), diagRoad);

    // Water body
    final waterPaint = Paint()..color = const Color(0xFFBDD5E8);
    final waterPath = Path()
      ..moveTo(w * 0.82, h)
      ..lineTo(w * 0.88, h * 0.80)
      ..quadraticBezierTo(w * 0.95, h * 0.72, w, h * 0.75)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(waterPath, waterPaint);

    // Location pin at centre
    final pinPaint = Paint()..color = const Color(0xFF0A6E57);
    canvas.drawCircle(Offset(w / 2, h / 2), w * 0.025, pinPaint);
    canvas.drawCircle(
      Offset(w / 2, h / 2),
      w * 0.025,
      Paint()
        ..color = const Color(0xFF0A6E57).withOpacity(0.25)
        ..strokeWidth = w * 0.02
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
