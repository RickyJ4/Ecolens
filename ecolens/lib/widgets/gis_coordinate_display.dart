import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Professional GIS Coordinate Display
/// Shows current map center or cursor position
class GISCoordinateDisplay extends StatelessWidget {
  final double latitude;
  final double longitude;
  final double zoom;

  const GISCoordinateDisplay({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.zoom,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.cyan.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.my_location, color: Colors.cyan, size: 14),
              const SizedBox(width: 6),
              Text(
                'COORDINATES',
                style: TextStyle(
                  color: Colors.cyan,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => _copyCoordinates(context),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCoordRow('LAT', _formatCoordinate(latitude, true)),
                    const SizedBox(height: 2),
                    _buildCoordRow('LON', _formatCoordinate(longitude, false)),
                    const SizedBox(height: 2),
                    _buildCoordRow('ZOOM', zoom.toStringAsFixed(1)),
                  ],
                ),
                const SizedBox(width: 8),
                Icon(Icons.copy, color: Colors.white38, size: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoordRow(String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 38,
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  String _formatCoordinate(double coord, bool isLatitude) {
    final direction = isLatitude
        ? (coord >= 0 ? 'N' : 'S')
        : (coord >= 0 ? 'E' : 'W');
    return '${coord.abs().toStringAsFixed(5)}° $direction';
  }

  void _copyCoordinates(BuildContext context) {
    final text = '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Coordinates copied: $text'),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.cyan.withOpacity(0.9),
      ),
    );
  }
}
