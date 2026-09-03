import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Professional GIS Compass Rose / North Arrow
class GISCompassRose extends StatelessWidget {
  final double bearing; // Map rotation in degrees

  const GISCompassRose({
    super.key,
    this.bearing = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white24, width: 2),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Compass circle
          CustomPaint(
            size: const Size(60, 60),
            painter: _CompassPainter(bearing: bearing),
          ),
          // North indicator
          Transform.rotate(
            angle: -bearing * math.pi / 180,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.arrow_drop_up,
                  color: Colors.red,
                  size: 24,
                ),
                Text(
                  'N',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompassPainter extends CustomPainter {
  final double bearing;

  _CompassPainter({required this.bearing});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;

    final paint = Paint()
      ..color = Colors.white54
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // Draw cardinal direction ticks
    for (int i = 0; i < 4; i++) {
      final angle = (i * 90 - bearing) * math.pi / 180;
      final start = Offset(
        center.dx + radius * 0.8 * math.cos(angle),
        center.dy + radius * 0.8 * math.sin(angle),
      );
      final end = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      canvas.drawLine(start, end, paint..strokeWidth = 2);
    }

    // Draw minor ticks
    for (int i = 0; i < 8; i++) {
      if (i % 2 == 1) {
        // Only draw NE, SE, SW, NW
        final angle = (i * 45 - bearing) * math.pi / 180;
        final start = Offset(
          center.dx + radius * 0.9 * math.cos(angle),
          center.dy + radius * 0.9 * math.sin(angle),
        );
        final end = Offset(
          center.dx + radius * math.cos(angle),
          center.dy + radius * math.sin(angle),
        );
        canvas.drawLine(start, end, paint..strokeWidth = 1);
      }
    }
  }

  @override
  bool shouldRepaint(_CompassPainter oldDelegate) =>
      bearing != oldDelegate.bearing;
}
