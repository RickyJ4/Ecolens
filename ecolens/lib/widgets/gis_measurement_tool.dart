import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_fonts/google_fonts.dart';

/// Professional GIS Measurement Tool
/// Measure distance and area on the map
class GISMeasurementTool extends StatefulWidget {
  final Function(bool) onMeasurementModeChanged;

  const GISMeasurementTool({
    super.key,
    required this.onMeasurementModeChanged,
  });

  @override
  State<GISMeasurementTool> createState() => _GISMeasurementToolState();
}

class _GISMeasurementToolState extends State<GISMeasurementTool> {
  bool _isActive = false;
  String _mode = 'distance'; // 'distance' or 'area'
  final List<LatLng> _points = [];
  double _totalDistance = 0;
  double _totalArea = 0;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A).withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.straighten, color: Colors.orange, size: 18),
              const SizedBox(width: 8),
              Text(
                'MEASUREMENT',
                style: GoogleFonts.orbitron(
                  color: Colors.orange,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildModeButton('Distance', Icons.timeline, 'distance'),
              const SizedBox(width: 8),
              _buildModeButton('Area', Icons.square_foot, 'area'),
            ],
          ),
          if (_isActive) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _mode == 'distance'
                        ? 'Distance: ${_formatDistance(_totalDistance)}'
                        : 'Area: ${_formatArea(_totalArea)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Points: ${_points.length}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildActionButton(
                        'Clear',
                        Icons.clear,
                        () => _clearMeasurement(),
                      ),
                      const SizedBox(width: 8),
                      _buildActionButton(
                        'Done',
                        Icons.check,
                        () => _deactivate(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildModeButton(String label, IconData icon, String mode) {
    final isSelected = _isActive && _mode == mode;
    return GestureDetector(
      onTap: () => _setMode(mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.orange.withOpacity(0.2)
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.orange : Colors.white24,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isSelected ? Colors.orange : Colors.white54, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.orange : Colors.white70,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 14),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  void _setMode(String mode) {
    setState(() {
      _mode = mode;
      _isActive = true;
      _points.clear();
      _totalDistance = 0;
      _totalArea = 0;
    });
    widget.onMeasurementModeChanged(true);
  }

  void _clearMeasurement() {
    setState(() {
      _points.clear();
      _totalDistance = 0;
      _totalArea = 0;
    });
  }

  void _deactivate() {
    setState(() {
      _isActive = false;
      _points.clear();
      _totalDistance = 0;
      _totalArea = 0;
    });
    widget.onMeasurementModeChanged(false);
  }

  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(2)} km';
    }
    return '${meters.toStringAsFixed(0)} m';
  }

  String _formatArea(double sqMeters) {
    if (sqMeters >= 10000) {
      return '${(sqMeters / 10000).toStringAsFixed(2)} ha';
    } else if (sqMeters >= 1000000) {
      return '${(sqMeters / 1000000).toStringAsFixed(2)} km²';
    }
    return '${sqMeters.toStringAsFixed(0)} m²';
  }
}
