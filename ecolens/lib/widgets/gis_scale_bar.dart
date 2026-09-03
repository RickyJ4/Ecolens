import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Professional GIS Scale Bar Widget
/// Dynamically updates based on map zoom level
class GISScaleBar extends StatelessWidget {
  final double zoom;
  final double latitude; // Used for accurate distance calculation

  const GISScaleBar({
    super.key,
    required this.zoom,
    required this.latitude,
  });

  @override
  Widget build(BuildContext context) {
    final scaleData = _calculateScale();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Scale bar
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 100,
                height: 4,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white,
                      Colors.white,
                      Colors.black,
                      Colors.black,
                      Colors.white,
                      Colors.white,
                    ],
                    stops: const [0, 0.25, 0.25, 0.5, 0.5, 1],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Scale text
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '0',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 60),
              Text(
                scaleData['text']!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Scale 1:${scaleData['ratio']}',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }

  Map<String, String> _calculateScale() {
    // Calculate meters per pixel at given zoom level
    // Formula: metersPerPixel = (Earth circumference) / (256 * 2^zoom) * cos(latitude)
    const earthCircumference = 40075017.0; // meters at equator
    final latitudeRadians = latitude * math.pi / 180;
    final metersPerPixel =
        earthCircumference * math.cos(latitudeRadians) / (256 * math.pow(2, zoom));

    // Scale bar represents 100 pixels
    final meters = metersPerPixel * 100;

    String text;
    String ratio;

    if (meters >= 1000) {
      final km = (meters / 1000).toStringAsFixed(meters >= 10000 ? 0 : 1);
      text = '$km km';
      ratio = (meters / 0.0254 / 12 / 5280).toStringAsFixed(0); // Convert to map scale
    } else {
      text = '${meters.toStringAsFixed(0)} m';
      ratio = (meters / 0.0254 / 12).toStringAsFixed(0);
    }

    return {'text': text, 'ratio': ratio};
  }
}
