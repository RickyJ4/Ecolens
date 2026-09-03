import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:ecolens/core/gis_theme.dart';
import 'package:ecolens/model/cartographic_models.dart';
import 'package:ecolens/model/hazard_models.dart';

/// Full-screen viewer for generated cartographic risk maps.
/// Supports zoom/pan, legend toggle, grid toggle, and PNG export.
class CartographicMapViewer extends StatefulWidget {
  final CartographicMap mapData;

  const CartographicMapViewer({super.key, required this.mapData});

  @override
  State<CartographicMapViewer> createState() => _CartographicMapViewerState();
}

class _CartographicMapViewerState extends State<CartographicMapViewer> {
  bool _showLegend = true;
  bool _showGrid = true;
  bool _showLabels = true;
  bool _showStats = true;
  final TransformationController _transformCtrl = TransformationController();
  final GlobalKey _repaintKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a1a),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0d1117),
        title: Text(
          'Cartographic Map',
          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: Icon(_showLegend ? Icons.legend_toggle : Icons.legend_toggle_outlined,
                color: _showLegend ? GISTheme.accentGreen : Colors.white54),
            tooltip: 'Toggle Legend',
            onPressed: () => setState(() => _showLegend = !_showLegend),
          ),
          IconButton(
            icon: Icon(_showGrid ? Icons.grid_on : Icons.grid_off,
                color: _showGrid ? GISTheme.accentGreen : Colors.white54),
            tooltip: 'Toggle Grid',
            onPressed: () => setState(() => _showGrid = !_showGrid),
          ),
          IconButton(
            icon: Icon(_showLabels ? Icons.label : Icons.label_off,
                color: _showLabels ? GISTheme.accentGreen : Colors.white54),
            tooltip: 'Toggle Labels',
            onPressed: () => setState(() => _showLabels = !_showLabels),
          ),
          IconButton(
            icon: const Icon(Icons.save_alt, color: Colors.white70),
            tooltip: 'Export PNG',
            onPressed: _exportPng,
          ),
        ],
      ),
      body: Column(
        children: [
          // Map viewer with zoom/pan
          Expanded(
            child: InteractiveViewer(
              transformationController: _transformCtrl,
              minScale: 0.5,
              maxScale: 5.0,
              boundaryMargin: const EdgeInsets.all(200),
              child: RepaintBoundary(
                key: _repaintKey,
                child: CustomPaint(
                  size: const Size(1920, 1080),
                  painter: _CartographicPainter(
                    mapData: widget.mapData,
                    showLegend: _showLegend,
                    showGrid: _showGrid,
                    showLabels: _showLabels,
                  ),
                ),
              ),
            ),
          ),

          // Stats bar
          if (_showStats) _buildStatsBar(),
        ],
      ),
    );
  }

  Widget _buildStatsBar() {
    final r = widget.mapData.report;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF0d1117),
        border: Border(top: BorderSide(color: Color(0xFF1e2a3a))),
      ),
      child: Row(
        children: [
          _statChip('Area', '${r.totalAreaKm2.toStringAsFixed(0)} km\u00B2'),
          _statChip('Pop. Exposed', _formatPop(r.totalPopulationExposed)),
          _statChip('Critical', '${(r.areaByRisk[RiskLevel.critical] ?? 0).toStringAsFixed(0)} km\u00B2'),
          _statChip('Extreme', '${(r.areaByRisk[RiskLevel.extreme] ?? 0).toStringAsFixed(0)} km\u00B2'),
          _statChip('Hazards', '${r.hazardCounts.values.fold(0, (a, b) => a + b)}'),
          const Spacer(),
          Text(
            'Generated ${_formatTime(widget.mapData.generatedAt)}',
            style: GoogleFonts.inter(fontSize: 10, color: Colors.white30),
          ),
        ],
      ),
    );
  }

  Widget _statChip(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
          Text(label, style: GoogleFonts.inter(fontSize: 9, color: Colors.white38)),
        ],
      ),
    );
  }

  String _formatPop(int pop) {
    if (pop >= 1000000) return '${(pop / 1000000).toStringAsFixed(1)}M';
    if (pop >= 1000) return '${(pop / 1000).toStringAsFixed(0)}K';
    return pop.toString();
  }

  String _formatTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _exportPng() async {
    try {
      final boundary = _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final bytes = byteData.buffer.asUint8List();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Map exported (${bytes.length ~/ 1024} KB)',
                style: GoogleFonts.inter()),
            backgroundColor: GISTheme.accentGreen,
          ),
        );
      }
    } catch (e) {
      debugPrint('Export failed: $e');
    }
  }
}

/// Custom painter that renders a professional cartographic map.
class _CartographicPainter extends CustomPainter {
  final CartographicMap mapData;
  final bool showLegend;
  final bool showGrid;
  final bool showLabels;

  _CartographicPainter({
    required this.mapData,
    required this.showLegend,
    required this.showGrid,
    required this.showLabels,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFF0a0a1a);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bg);

    // Layout regions
    const titleH = 60.0;
    const margin = 20.0;
    final legendW = showLegend ? 220.0 : 0.0;
    final mapRect = Rect.fromLTRB(
      margin, titleH + margin,
      size.width - margin - legendW, size.height - margin - 80,
    );

    _drawTitleBlock(canvas, size, titleH);
    _drawMapBody(canvas, mapRect);
    if (showGrid) _drawGraticule(canvas, mapRect);
    if (showLabels) _drawLabels(canvas, mapRect);
    _drawHazardMarkers(canvas, mapRect);
    if (showLegend) _drawLegend(canvas, size, mapRect, legendW);
    _drawScaleBar(canvas, mapRect);
    _drawNorthArrow(canvas, mapRect);
    _drawAttribution(canvas, size);
  }

  void _drawTitleBlock(Canvas canvas, Size size, double h) {
    final titlePaint = Paint()..color = const Color(0xFF0d1117);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, h), titlePaint);

    final border = Paint()
      ..color = const Color(0xFF1e2a3a)
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(0, h), Offset(size.width, h), border);

    _drawText(canvas, mapData.title, 20, h / 2 - 12,
        fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white);
    _drawText(canvas, mapData.subtitle, 20, h / 2 + 8,
        fontSize: 11, color: Colors.white54);
    _drawText(canvas, 'EcoLens Environmental Intelligence',
        size.width - 240, h / 2 - 4,
        fontSize: 10, color: const Color(0xFF4CAF50));
  }

  void _drawMapBody(Canvas canvas, Rect r) {
    // Map background
    final mapBg = Paint()..color = const Color(0xFF0f1520);
    canvas.drawRect(r, mapBg);

    // Map border
    final borderPaint = Paint()
      ..color = const Color(0xFF2a3a4a)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(r, borderPaint);

    // Render risk grid cells
    final grid = mapData.grid;
    if (grid.isEmpty || grid[0].isEmpty) return;

    final rows = grid.length;
    final cols = grid[0].length;
    final cellW = r.width / cols;
    final cellH = r.height / rows;

    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        final cell = grid[row][col];
        final color = _riskColor(cell.level, cell.compositeRisk);

        final cellPaint = Paint()..color = color;
        canvas.drawRect(
          Rect.fromLTWH(r.left + col * cellW, r.top + row * cellH, cellW + 0.5, cellH + 0.5),
          cellPaint,
        );
      }
    }
  }

  void _drawGraticule(Canvas canvas, Rect r) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 0.5;

    final bounds = mapData.bounds;
    final latRange = bounds.north - bounds.south;
    final lonRange = bounds.east - bounds.west;

    // Adaptive grid spacing
    double spacing;
    if (latRange > 10) spacing = 5;
    else if (latRange > 2) spacing = 1;
    else if (latRange > 0.5) spacing = 0.25;
    else spacing = 0.1;

    // Latitude lines
    double lat = (bounds.south / spacing).ceil() * spacing;
    while (lat < bounds.north) {
      final y = r.top + (1 - (lat - bounds.south) / latRange) * r.height;
      canvas.drawLine(Offset(r.left, y), Offset(r.right, y), gridPaint);
      _drawText(canvas, '${lat.toStringAsFixed(2)}\u00B0', r.left + 4, y - 12,
          fontSize: 8, color: Colors.white24);
      lat += spacing;
    }

    // Longitude lines
    double lon = (bounds.west / spacing).ceil() * spacing;
    while (lon < bounds.east) {
      final x = r.left + (lon - bounds.west) / lonRange * r.width;
      canvas.drawLine(Offset(x, r.top), Offset(x, r.bottom), gridPaint);
      _drawText(canvas, '${lon.toStringAsFixed(2)}\u00B0', x + 2, r.bottom - 14,
          fontSize: 8, color: Colors.white24);
      lon += spacing;
    }
  }

  void _drawLabels(Canvas canvas, Rect r) {
    // Draw hazard count labels at map corners
    final report = mapData.report;
    final counts = report.hazardCounts;
    if (counts.isEmpty) return;

    double y = r.top + 8;
    for (final entry in counts.entries) {
      _drawText(canvas, '${entry.key.label}: ${entry.value}',
          r.left + 8, y, fontSize: 9, color: Colors.white38);
      y += 14;
    }
  }

  void _drawHazardMarkers(Canvas canvas, Rect r) {
    final bounds = mapData.bounds;
    final latRange = bounds.north - bounds.south;
    final lonRange = bounds.east - bounds.west;

    for (final marker in mapData.hazardMarkers) {
      final x = r.left + (marker.lon - bounds.west) / lonRange * r.width;
      final y = r.top + (1 - (marker.lat - bounds.south) / latRange) * r.height;

      if (x < r.left || x > r.right || y < r.top || y > r.bottom) continue;

      final color = _hazardColor(marker.type);
      final markerPaint = Paint()..color = color;
      final glowPaint = Paint()..color = color.withValues(alpha: 0.3);

      canvas.drawCircle(Offset(x, y), 6, glowPaint);
      canvas.drawCircle(Offset(x, y), 3, markerPaint);

      if (showLabels && marker.label.isNotEmpty) {
        _drawText(canvas, marker.label, x + 8, y - 5,
            fontSize: 8, color: Colors.white54);
      }
    }
  }

  void _drawLegend(Canvas canvas, Size size, Rect mapRect, double legendW) {
    final lx = size.width - legendW - 10;
    final ly = mapRect.top;
    final lw = legendW;
    final lh = mapRect.height;

    // Legend background
    final bg = Paint()..color = const Color(0xFF0d1117);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(lx, ly, lw, lh), const Radius.circular(8)),
      bg,
    );

    final border = Paint()
      ..color = const Color(0xFF1e2a3a)
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(lx, ly, lw, lh), const Radius.circular(8)),
      border,
    );

    double y = ly + 16;
    _drawText(canvas, 'RISK LEVEL', lx + 16, y,
        fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white70);
    y += 24;

    for (final level in RiskLevel.values) {
      final color = RiskLevelExt(level).color;
      final swatch = Paint()..color = color;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(lx + 16, y, 20, 14), const Radius.circular(3)),
        swatch,
      );
      _drawText(canvas, level.label, lx + 44, y + 1,
          fontSize: 10, color: Colors.white60);
      y += 22;
    }

    y += 16;
    _drawText(canvas, 'HAZARD TYPES', lx + 16, y,
        fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white70);
    y += 22;

    for (final entry in mapData.report.hazardCounts.entries) {
      final color = _hazardColor(entry.key);
      final dot = Paint()..color = color;
      canvas.drawCircle(Offset(lx + 26, y + 6), 5, dot);
      _drawText(canvas, '${entry.key.label} (${entry.value})', lx + 40, y,
          fontSize: 10, color: Colors.white54);
      y += 20;
    }

    y += 16;
    _drawText(canvas, 'SUMMARY', lx + 16, y,
        fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white70);
    y += 20;

    final r = mapData.report;
    _drawText(canvas, 'Total area: ${r.totalAreaKm2.toStringAsFixed(0)} km\u00B2',
        lx + 16, y, fontSize: 9, color: Colors.white38);
    y += 16;
    _drawText(canvas, 'Pop. exposed: ${_formatPop(r.totalPopulationExposed)}',
        lx + 16, y, fontSize: 9, color: Colors.white38);
    y += 16;
    _drawText(canvas, 'Critical area: ${(r.areaByRisk[RiskLevel.critical] ?? 0).toStringAsFixed(0)} km\u00B2',
        lx + 16, y, fontSize: 9, color: const Color(0xFFB2182B));
  }

  void _drawScaleBar(Canvas canvas, Rect r) {
    final bounds = mapData.bounds;
    final lonRange = bounds.east - bounds.west;
    final kmPerDeg = 111.32 * _cos((bounds.north + bounds.south) / 2);
    final totalKm = lonRange * kmPerDeg;

    // Find a nice round number for scale
    double scaleKm;
    if (totalKm > 500) scaleKm = 100;
    else if (totalKm > 100) scaleKm = 50;
    else if (totalKm > 50) scaleKm = 20;
    else if (totalKm > 10) scaleKm = 5;
    else scaleKm = 1;

    final barW = (scaleKm / totalKm) * r.width;
    final x = r.left + 20;
    final y = r.bottom - 20;

    final barPaint = Paint()
      ..color = Colors.white70
      ..strokeWidth = 2;
    canvas.drawLine(Offset(x, y), Offset(x + barW, y), barPaint);
    canvas.drawLine(Offset(x, y - 4), Offset(x, y + 4), barPaint);
    canvas.drawLine(Offset(x + barW, y - 4), Offset(x + barW, y + 4), barPaint);

    _drawText(canvas, '${scaleKm.toStringAsFixed(0)} km', x + barW / 2 - 10, y - 14,
        fontSize: 9, color: Colors.white60);
  }

  void _drawNorthArrow(Canvas canvas, Rect r) {
    final cx = r.right - 30;
    final cy = r.top + 30;

    final arrowPaint = Paint()
      ..color = Colors.white70
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(cx, cy - 15)
      ..lineTo(cx - 6, cy + 5)
      ..lineTo(cx, cy)
      ..lineTo(cx + 6, cy + 5)
      ..close();
    canvas.drawPath(path, arrowPaint);

    _drawText(canvas, 'N', cx - 3, cy - 28,
        fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white70);
  }

  void _drawAttribution(Canvas canvas, Size size) {
    _drawText(canvas, 'Data: NASA FIRMS \u00B7 NOAA \u00B7 USGS \u00B7 USDM \u00B7 WorldPop  |  Generated by EcoLens',
        20, size.height - 22, fontSize: 8, color: Colors.white.withValues(alpha: 0.2));
  }

  // ─── HELPERS ───────────────────────────────────────

  Color _riskColor(RiskLevel level, double value) {
    return RiskLevelExt(level).color.withValues(alpha: 0.5 + value * 0.5);
  }

  Color _hazardColor(HazardType type) {
    switch (type) {
      case HazardType.wildfire: return const Color(0xFFFF4500);
      case HazardType.flood: return const Color(0xFF1E90FF);
      case HazardType.drought: return const Color(0xFFDAA520);
      case HazardType.glacier: return const Color(0xFF87CEEB);
      case HazardType.ndvi: return const Color(0xFF32CD32);
      default: return Colors.white54;
    }
  }

  String _formatPop(int pop) {
    if (pop >= 1000000) return '${(pop / 1000000).toStringAsFixed(1)}M';
    if (pop >= 1000) return '${(pop / 1000).toStringAsFixed(0)}K';
    return pop.toString();
  }

  double _cos(double deg) => _cosRad(deg * 3.14159265 / 180);
  double _cosRad(double rad) {
    // Simple cosine approximation
    rad = rad % (2 * 3.14159265);
    double x2 = rad * rad;
    return 1 - x2 / 2 + x2 * x2 / 24 - x2 * x2 * x2 / 720;
  }

  void _drawText(Canvas canvas, String text, double x, double y, {
    double fontSize = 12,
    FontWeight fontWeight = FontWeight.w400,
    Color color = Colors.white,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: color,
          fontFamily: 'Inter',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(x, y));
  }

  @override
  bool shouldRepaint(covariant _CartographicPainter old) {
    return old.showLegend != showLegend ||
        old.showGrid != showGrid ||
        old.showLabels != showLabels;
  }
}

/// Extension to provide the RiskLevel color without repeating the map.
extension RiskLevelExt on RiskLevel {
  Color get color {
    switch (this) {
      case RiskLevel.low: return const Color(0xFF2166AC);
      case RiskLevel.moderate: return const Color(0xFF67A9CF);
      case RiskLevel.high: return const Color(0xFFFDDBC7);
      case RiskLevel.extreme: return const Color(0xFFEF8A62);
      case RiskLevel.critical: return const Color(0xFFB2182B);
    }
  }
}
