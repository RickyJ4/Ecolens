import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'package:ecolens/model/hazard_models.dart';
import 'package:ecolens/model/cartographic_models.dart';

// ═══════════════════════════════════════════════════════════════
// CARTOGRAPHIC ENGINE
// Generates professional static cartographic maps from hazard
// data using Flutter's Canvas API.
//
// Pipeline:
//   1. computeRiskSurface  → 2D grid of RiskCell
//   2. renderMap            → CartographicMap (data + layout)
//   3. CartographicMapPainter paints the map via CustomPaint
//   4. exportAsPng          → Uint8List PNG bytes
// ═══════════════════════════════════════════════════════════════

class CartographicEngine {
  // ─────────────────────────────────────────────────────────────
  // Constants
  // ─────────────────────────────────────────────────────────────

  /// Professional RdBu diverging color ramp (ColorBrewer 2.0).
  static const riskColors = <RiskLevel, Color>{
    RiskLevel.low: Color(0xFF2166AC),
    RiskLevel.moderate: Color(0xFF67A9CF),
    RiskLevel.high: Color(0xFFFDDBC7),
    RiskLevel.extreme: Color(0xFFEF8A62),
    RiskLevel.critical: Color(0xFFB2182B),
  };

  static const _earthRadiusKm = 6371.0;

  // ─────────────────────────────────────────────────────────────
  // 1. RISK SURFACE COMPUTATION
  // ─────────────────────────────────────────────────────────────

  /// Computes a spatial risk grid for a bounding box.
  ///
  /// For each cell in the [gridSize] x [gridSize] grid:
  ///   1. Query proximity to active hazards (fires, floods, earthquakes)
  ///   2. Compute terrain vulnerability (slope proxy from elevation)
  ///   3. Compute population exposure (proximity to known cities)
  ///   4. Combine into a weighted risk score (0-1)
  ///   5. Classify into risk zones: LOW through CRITICAL
  ///
  /// [hazardData] should come from HazardViewModel.hazardData.
  /// [weights] defaults to balanced preset.
  static List<List<RiskCell>> computeRiskSurface(
    LatLngBounds bbox, {
    int gridSize = 50,
    Map<HazardType, double>? weights,
    Map<HazardType, List<dynamic>>? hazardData,
  }) {
    final w = weights ?? RiskWeightPresets.balanced;
    final rng = math.Random(42); // deterministic seed for reproducibility

    final latStep = (bbox.north - bbox.south) / gridSize;
    final lonStep = (bbox.east - bbox.west) / gridSize;

    // Pre-extract hazard locations for proximity queries
    final firePoints = _extractPoints(hazardData, HazardType.wildfire);
    final floodPoints = _extractPoints(hazardData, HazardType.flood);
    final droughtPoints = _extractPoints(hazardData, HazardType.drought);

    // Compute the grid
    final grid = <List<RiskCell>>[];

    for (int row = 0; row < gridSize; row++) {
      final cellRow = <RiskCell>[];
      final cellLat = bbox.south + (row + 0.5) * latStep;

      for (int col = 0; col < gridSize; col++) {
        final cellLon = bbox.west + (col + 0.5) * lonStep;

        // --- Per-hazard risk scores (0-1) ---

        // Fire risk: inverse distance to nearest fire, capped
        final fireRisk = _proximityRisk(cellLat, cellLon, firePoints,
            decayKm: 80.0);

        // Flood risk: inverse distance to nearest flood
        final floodRisk = _proximityRisk(cellLat, cellLon, floodPoints,
            decayKm: 60.0);

        // Drought risk: from drought layer or baseline
        final droughtRisk = _proximityRisk(cellLat, cellLon, droughtPoints,
            decayKm: 200.0);

        // Seismic risk: simple latitude-band model (ring of fire proxy)
        final seismicRisk = _seismicRiskModel(cellLat, cellLon);

        // --- Terrain vulnerability proxy ---
        // Simple model: higher elevation variance = higher vulnerability
        final elevation = _estimateElevation(cellLat, cellLon, rng);

        // --- Population density proxy ---
        final popDensity = _estimatePopulation(cellLat, cellLon);

        // --- Composite weighted risk ---
        final wFire = w[HazardType.wildfire] ?? 0.30;
        final wFlood = w[HazardType.flood] ?? 0.30;
        final wDrought = w[HazardType.drought] ?? 0.20;
        // Use remaining weight for seismic
        final wSeismic = 1.0 - wFire - wFlood - wDrought;

        double composite = wFire * fireRisk +
            wFlood * floodRisk +
            wDrought * droughtRisk +
            wSeismic.clamp(0.0, 1.0) * seismicRisk;

        // Boost risk in high-population cells (exposure factor)
        final popBoost = (popDensity / 5000.0).clamp(0.0, 0.15);
        composite = (composite + popBoost).clamp(0.0, 1.0);

        cellRow.add(RiskCell(
          lat: cellLat,
          lon: cellLon,
          fireRisk: fireRisk,
          floodRisk: floodRisk,
          seismicRisk: seismicRisk,
          droughtRisk: droughtRisk,
          compositeRisk: composite,
          level: RiskCell.classify(composite),
          populationDensity: popDensity,
          elevationM: elevation,
        ));
      }
      grid.add(cellRow);
    }

    return grid;
  }

  // ─────────────────────────────────────────────────────────────
  // 2. MAP RENDERING (builds data object for painter)
  // ─────────────────────────────────────────────────────────────

  /// Builds a [CartographicMap] from a computed risk grid.
  ///
  /// This object is consumed by [CartographicMapPainter] to render
  /// the map on a Canvas.
  static CartographicMap renderMap(
    List<List<RiskCell>> grid,
    LatLngBounds bounds, {
    String? title,
    bool showLegend = true,
    bool showGrid = true,
    bool showLabels = true,
    Map<HazardType, List<dynamic>>? hazardData,
  }) {
    final gridHeight = grid.length;
    final gridWidth = grid.isNotEmpty ? grid.first.length : 0;

    // Build hazard markers from the raw data
    final markers = <HazardMarker>[];
    if (hazardData != null) {
      for (final entry in hazardData.entries) {
        for (final item in entry.value) {
          if (item is HazardFeature) {
            markers.add(HazardMarker(
              lat: item.latitude,
              lon: item.longitude,
              type: item.type,
              label: item.properties['name'] as String? ??
                  item.properties['title'] as String? ??
                  item.type.label,
              severity: item.severity,
            ));
          }
        }
      }
    }

    final report = generateReport(grid, bounds, hazardData: hazardData);

    // Auto-generate title
    final mapTitle = title ?? 'Multi-Hazard Risk Assessment';
    final dateStr = DateFormat('d MMM yyyy, HH:mm').format(DateTime.now());
    final coordStr =
        '${bounds.south.toStringAsFixed(2)}\u00B0 to '
        '${bounds.north.toStringAsFixed(2)}\u00B0N, '
        '${bounds.west.toStringAsFixed(2)}\u00B0 to '
        '${bounds.east.toStringAsFixed(2)}\u00B0E';
    final subtitle = '$dateStr  |  $coordStr';

    return CartographicMap(
      title: mapTitle,
      subtitle: subtitle,
      bounds: bounds,
      grid: grid,
      gridWidth: gridWidth,
      gridHeight: gridHeight,
      generatedAt: DateTime.now(),
      report: report,
      hazardMarkers: markers,
      showLegend: showLegend,
      showGrid: showGrid,
      showLabels: showLabels,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 3. PNG EXPORT
  // ─────────────────────────────────────────────────────────────

  /// Renders the cartographic map to a PNG image.
  ///
  /// Uses an offscreen [ui.PictureRecorder] and [Canvas] to paint
  /// the entire map, then encodes it as PNG bytes.
  static Future<Uint8List> exportAsPng(
    CartographicMap map, {
    int width = 1920,
    int height = 1080,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));

    final painter = CartographicMapPainter(map: map);
    painter.paint(canvas, Size(width.toDouble(), height.toDouble()));

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    image.dispose();

    if (byteData == null) {
      throw Exception('Failed to encode cartographic map as PNG');
    }

    return byteData.buffer.asUint8List();
  }

  // ─────────────────────────────────────────────────────────────
  // 4. REPORT GENERATION
  // ─────────────────────────────────────────────────────────────

  /// Generates summary statistics from the risk grid.
  static MapReport generateReport(
    List<List<RiskCell>> grid,
    LatLngBounds bounds, {
    Map<HazardType, List<dynamic>>? hazardData,
  }) {
    final gridHeight = grid.length;
    final gridWidth = grid.isNotEmpty ? grid.first.length : 0;
    final totalCells = gridHeight * gridWidth;
    if (totalCells == 0) {
      return MapReport(
        totalAreaKm2: 0,
        areaByRisk: {},
        populationByRisk: {},
        totalPopulationExposed: 0,
        topHazards: [],
        hazardCounts: {},
        dataTimestamp: DateTime.now(),
      );
    }

    // Total area in km2
    final latSpan = bounds.north - bounds.south;
    final lonSpan = bounds.east - bounds.west;
    final midLat = (bounds.north + bounds.south) / 2.0;
    final latKm = latSpan * 111.32;
    final lonKm = lonSpan * 111.32 * math.cos(midLat * math.pi / 180.0);
    final totalArea = latKm * lonKm;
    final cellAreaKm2 = totalArea / totalCells;

    // Aggregate by risk level
    final areaByRisk = <RiskLevel, double>{};
    final popByRisk = <RiskLevel, int>{};
    for (final level in RiskLevel.values) {
      areaByRisk[level] = 0.0;
      popByRisk[level] = 0;
    }

    for (final row in grid) {
      for (final cell in row) {
        areaByRisk[cell.level] = (areaByRisk[cell.level] ?? 0) + cellAreaKm2;
        // Population in cell ~ density * cell area
        final pop = (cell.populationDensity * cellAreaKm2).round();
        popByRisk[cell.level] = (popByRisk[cell.level] ?? 0) + pop;
      }
    }

    final totalPopExposed = (popByRisk[RiskLevel.high] ?? 0) +
        (popByRisk[RiskLevel.extreme] ?? 0) +
        (popByRisk[RiskLevel.critical] ?? 0);

    // Hazard counts
    final hazardCounts = <HazardType, int>{};
    if (hazardData != null) {
      for (final entry in hazardData.entries) {
        final count =
            entry.value.where((item) => item is HazardFeature).length;
        if (count > 0) hazardCounts[entry.key] = count;
      }
    }

    // Top hazards by area affected
    final hazardAreas = <String, double>{};
    for (final row in grid) {
      for (final cell in row) {
        if (cell.fireRisk > 0.3) {
          hazardAreas['Wildfire'] =
              (hazardAreas['Wildfire'] ?? 0) + cellAreaKm2;
        }
        if (cell.floodRisk > 0.3) {
          hazardAreas['Flood'] = (hazardAreas['Flood'] ?? 0) + cellAreaKm2;
        }
        if (cell.droughtRisk > 0.3) {
          hazardAreas['Drought'] =
              (hazardAreas['Drought'] ?? 0) + cellAreaKm2;
        }
        if (cell.seismicRisk > 0.3) {
          hazardAreas['Seismic'] =
              (hazardAreas['Seismic'] ?? 0) + cellAreaKm2;
        }
      }
    }
    final sorted = hazardAreas.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topHazards = sorted.take(3).map((e) => e.key).toList();

    return MapReport(
      totalAreaKm2: totalArea,
      areaByRisk: areaByRisk,
      populationByRisk: popByRisk,
      totalPopulationExposed: totalPopExposed,
      topHazards: topHazards,
      hazardCounts: hazardCounts,
      dataTimestamp: DateTime.now(),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // INTERNAL HELPERS
  // ═══════════════════════════════════════════════════════════════

  /// Extract lat/lon pairs from hazard data for a specific type.
  static List<_LatLon> _extractPoints(
    Map<HazardType, List<dynamic>>? data,
    HazardType type,
  ) {
    if (data == null || !data.containsKey(type)) return [];
    final items = data[type]!;
    final points = <_LatLon>[];
    for (final item in items) {
      if (item is HazardFeature) {
        points.add(_LatLon(item.latitude, item.longitude));
      }
    }
    return points;
  }

  /// Proximity risk: inversely proportional to distance to nearest hazard.
  ///
  /// Returns 0 if no hazards exist, 1 if directly on a hazard.
  /// [decayKm] is the distance at which risk drops to ~0.
  static double _proximityRisk(
    double lat,
    double lon,
    List<_LatLon> hazardPoints, {
    double decayKm = 100.0,
  }) {
    if (hazardPoints.isEmpty) return 0.0;

    double minDistKm = double.infinity;
    for (final p in hazardPoints) {
      final d = _haversineKm(lat, lon, p.lat, p.lon);
      if (d < minDistKm) minDistKm = d;
    }

    // Exponential decay: risk = exp(-distance / decay)
    final risk = math.exp(-minDistKm / (decayKm * 0.33));
    return risk.clamp(0.0, 1.0);
  }

  /// Simple seismic risk model based on tectonic proximity.
  ///
  /// Higher risk near known plate boundaries (Ring of Fire, etc.).
  static double _seismicRiskModel(double lat, double lon) {
    // Simplified tectonic zones (lat/lon corridors with elevated seismicity)
    final zones = <_TectonicZone>[
      // Pacific Ring of Fire - west coast Americas
      _TectonicZone(-60, -80, 60, -70, 0.7),
      // Pacific Ring of Fire - east Asia/Japan
      _TectonicZone(10, 120, 50, 150, 0.75),
      // Himalayan belt
      _TectonicZone(25, 65, 40, 100, 0.6),
      // Mediterranean-Trans-Asiatic belt
      _TectonicZone(30, -10, 45, 75, 0.5),
      // Mid-Atlantic ridge (simplified)
      _TectonicZone(-60, -35, 60, -10, 0.3),
      // Indonesia / Sunda arc
      _TectonicZone(-10, 95, 10, 140, 0.7),
      // East African Rift
      _TectonicZone(-15, 28, 15, 42, 0.4),
    ];

    double maxRisk = 0.0;
    for (final zone in zones) {
      if (lat >= zone.minLat &&
          lat <= zone.maxLat &&
          lon >= zone.minLon &&
          lon <= zone.maxLon) {
        if (zone.risk > maxRisk) maxRisk = zone.risk;
      }
    }

    // Add some gradient at zone edges
    if (maxRisk == 0.0) {
      for (final zone in zones) {
        final latDist = _clampedDist(lat, zone.minLat, zone.maxLat);
        final lonDist = _clampedDist(lon, zone.minLon, zone.maxLon);
        final edgeDist = math.sqrt(latDist * latDist + lonDist * lonDist);
        if (edgeDist < 10.0) {
          final edgeRisk = zone.risk * (1.0 - edgeDist / 10.0);
          if (edgeRisk > maxRisk) maxRisk = edgeRisk;
        }
      }
    }

    return maxRisk.clamp(0.0, 1.0);
  }

  /// Estimate elevation (simple model — no API).
  ///
  /// Uses latitude/longitude to provide a rough elevation estimate:
  /// mountains near known ranges, coastal areas lower.
  static double _estimateElevation(double lat, double lon, math.Random rng) {
    double baseElevation = 200.0;

    // Higher elevations near major mountain ranges
    // Himalayas
    if (lat > 27 && lat < 37 && lon > 72 && lon < 100) {
      baseElevation = 3000.0 + rng.nextDouble() * 2000;
    }
    // Andes
    else if (lat > -55 && lat < 10 && lon > -80 && lon < -65) {
      baseElevation = 2000.0 + rng.nextDouble() * 2500;
    }
    // Rockies
    else if (lat > 35 && lat < 60 && lon > -120 && lon < -105) {
      baseElevation = 1500.0 + rng.nextDouble() * 2000;
    }
    // Alps
    else if (lat > 43 && lat < 48 && lon > 5 && lon < 17) {
      baseElevation = 1200.0 + rng.nextDouble() * 2500;
    }
    // Coastal areas (within ~2 degrees of typical coastlines)
    else if (lat.abs() < 5) {
      baseElevation = 50.0 + rng.nextDouble() * 200;
    } else {
      baseElevation = 100.0 + rng.nextDouble() * 500;
    }

    return baseElevation;
  }

  /// Estimate population density (people/km2) without API call.
  ///
  /// Uses a simple model: higher density near the equatorial band
  /// and known high-density corridors (South/East Asia, Europe, etc.).
  static double _estimatePopulation(double lat, double lon) {
    double density = 25.0; // global average baseline

    // South/Southeast Asia corridor
    if (lat > 5 && lat < 35 && lon > 68 && lon < 140) {
      density = 200.0 + 300.0 * math.exp(-((lat - 22).abs() / 15.0));
    }
    // Europe
    else if (lat > 38 && lat < 58 && lon > -10 && lon < 40) {
      density = 120.0;
    }
    // Eastern US / coast
    else if (lat > 25 && lat < 48 && lon > -90 && lon < -70) {
      density = 100.0;
    }
    // Western US
    else if (lat > 30 && lat < 48 && lon > -125 && lon < -110) {
      density = 30.0;
    }
    // Coastal Brazil
    else if (lat > -25 && lat < 0 && lon > -50 && lon < -34) {
      density = 80.0;
    }
    // Nigeria / West Africa
    else if (lat > 4 && lat < 14 && lon > 2 && lon < 15) {
      density = 180.0;
    }
    // Nile corridor
    else if (lat > 22 && lat < 32 && lon > 29 && lon < 34) {
      density = 500.0;
    }

    return density;
  }

  /// Haversine distance in kilometres.
  static double _haversineKm(
      double lat1, double lon1, double lat2, double lon2) {
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return _earthRadiusKm * c;
  }

  static double _deg2rad(double deg) => deg * math.pi / 180.0;

  /// Distance from [value] to the nearest edge of [min]..[max] range,
  /// or 0 if value is within the range.
  static double _clampedDist(double value, double min, double max) {
    if (value < min) return min - value;
    if (value > max) return value - max;
    return 0.0;
  }
}

// ─────────────────────────────────────────────────────────────
// Internal helper types
// ─────────────────────────────────────────────────────────────

class _LatLon {
  final double lat;
  final double lon;
  const _LatLon(this.lat, this.lon);
}

class _TectonicZone {
  final double minLat, minLon, maxLat, maxLon;
  final double risk;
  const _TectonicZone(
      this.minLat, this.minLon, this.maxLat, this.maxLon, this.risk);
}

// ═══════════════════════════════════════════════════════════════
// CARTOGRAPHIC MAP PAINTER
// Renders the full cartographic map on a Flutter Canvas.
//
// Layout (top to bottom):
//   ┌──────────────────────────────────────┐
//   │            TITLE BLOCK               │
//   ├──────────────────────┬───────────────┤
//   │                      │               │
//   │     MAP BODY         │   LEGEND      │
//   │  (grid + markers     │   (colors,    │
//   │   + graticule)       │    scale,     │
//   │                      │    north)     │
//   ├──────────────────────┴───────────────┤
//   │          STATISTICS PANEL            │
//   └──────────────────────────────────────┘
// ═══════════════════════════════════════════════════════════════

class CartographicMapPainter extends CustomPainter {
  final CartographicMap map;

  CartographicMapPainter({required this.map});

  // Layout proportions
  static const _titleFraction = 0.10;
  static const _statsFraction = 0.14;
  static const _legendWidthFraction = 0.18;
  static const _mapPadding = 12.0;

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF0D1117),
    );

    final titleH = size.height * _titleFraction;
    final statsH = size.height * _statsFraction;
    final legendW = map.showLegend ? size.width * _legendWidthFraction : 0.0;
    final mapRect = Rect.fromLTWH(
      _mapPadding,
      titleH,
      size.width - legendW - _mapPadding * 2,
      size.height - titleH - statsH - _mapPadding,
    );
    final legendRect = Rect.fromLTWH(
      size.width - legendW,
      titleH,
      legendW,
      size.height - titleH - statsH,
    );
    final statsRect = Rect.fromLTWH(
      0,
      size.height - statsH,
      size.width,
      statsH,
    );

    _paintTitleBlock(canvas, Size(size.width, titleH));
    _paintMapBody(canvas, mapRect);
    if (map.showLegend) _paintLegend(canvas, legendRect);
    _paintStatsPanel(canvas, statsRect);

    // Border around entire map
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..color = const Color(0xFF30363D)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // TITLE BLOCK
  // ─────────────────────────────────────────────────────────────

  void _paintTitleBlock(Canvas canvas, Size size) {
    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF161B22),
    );

    // Divider line
    canvas.drawLine(
      Offset(0, size.height - 1),
      Offset(size.width, size.height - 1),
      Paint()
        ..color = const Color(0xFF30363D)
        ..strokeWidth = 1,
    );

    // EcoLens branding badge
    final badgePaint = Paint()..color = const Color(0xFF238636);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(16, size.height * 0.18, 80, 22),
        const Radius.circular(4),
      ),
      badgePaint,
    );

    _drawText(
      canvas,
      'EcoLens',
      Offset(20, size.height * 0.18 + 2),
      fontSize: 13,
      color: Colors.white,
      bold: true,
    );

    // Title
    _drawText(
      canvas,
      map.title,
      Offset(16, size.height * 0.45),
      fontSize: math.min(20, size.width / 50).toDouble(),
      color: const Color(0xFFF0F6FC),
      bold: true,
    );

    // Subtitle
    _drawText(
      canvas,
      map.subtitle,
      Offset(16, size.height * 0.73),
      fontSize: 11,
      color: const Color(0xFF8B949E),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // MAP BODY
  // ─────────────────────────────────────────────────────────────

  void _paintMapBody(Canvas canvas, Rect rect) {
    canvas.save();
    canvas.clipRect(rect);

    // Map background (dark ocean)
    canvas.drawRect(rect, Paint()..color = const Color(0xFF0A1628));

    final grid = map.grid;
    if (grid.isEmpty || grid.first.isEmpty) {
      canvas.restore();
      return;
    }

    final rows = grid.length;
    final cols = grid.first.length;
    final cellW = rect.width / cols;
    final cellH = rect.height / rows;

    // --- Risk surface cells ---
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final cell = grid[r][c];
        final x = rect.left + c * cellW;
        final y = rect.top + (rows - 1 - r) * cellH; // north up

        canvas.drawRect(
          Rect.fromLTWH(x, y, cellW + 0.5, cellH + 0.5),
          Paint()..color = cell.level.fillColor,
        );
      }
    }

    // --- Graticule (lat/lon grid lines) ---
    if (map.showGrid) {
      _paintGraticule(canvas, rect);
    }

    // --- Hazard markers ---
    _paintHazardMarkers(canvas, rect);

    // --- Labels ---
    if (map.showLabels) {
      _paintCoordinateLabels(canvas, rect);
    }

    // Map border
    canvas.drawRect(
      rect,
      Paint()
        ..color = const Color(0xFF30363D)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    canvas.restore();
  }

  void _paintGraticule(Canvas canvas, Rect rect) {
    final bounds = map.bounds;
    final latSpan = bounds.north - bounds.south;
    final lonSpan = bounds.east - bounds.west;

    // Choose nice graticule interval
    final latInterval = _niceInterval(latSpan);
    final lonInterval = _niceInterval(lonSpan);

    final linePaint = Paint()
      ..color = const Color(0xFF30363D).withValues(alpha: 0.5)
      ..strokeWidth = 0.5;

    // Latitude lines
    final firstLat =
        (bounds.south / latInterval).ceil() * latInterval;
    for (double lat = firstLat; lat <= bounds.north; lat += latInterval) {
      final y = rect.bottom -
          ((lat - bounds.south) / latSpan) * rect.height;
      canvas.drawLine(
        Offset(rect.left, y),
        Offset(rect.right, y),
        linePaint,
      );
      // Label
      if (map.showLabels) {
        _drawText(
          canvas,
          '${lat.toStringAsFixed(1)}\u00B0',
          Offset(rect.left + 2, y - 12),
          fontSize: 9,
          color: const Color(0xFF6E7681),
        );
      }
    }

    // Longitude lines
    final firstLon =
        (bounds.west / lonInterval).ceil() * lonInterval;
    for (double lon = firstLon; lon <= bounds.east; lon += lonInterval) {
      final x = rect.left +
          ((lon - bounds.west) / lonSpan) * rect.width;
      canvas.drawLine(
        Offset(x, rect.top),
        Offset(x, rect.bottom),
        linePaint,
      );
      if (map.showLabels) {
        _drawText(
          canvas,
          '${lon.toStringAsFixed(1)}\u00B0',
          Offset(x + 2, rect.bottom - 14),
          fontSize: 9,
          color: const Color(0xFF6E7681),
        );
      }
    }
  }

  void _paintHazardMarkers(Canvas canvas, Rect rect) {
    final bounds = map.bounds;
    final latSpan = bounds.north - bounds.south;
    final lonSpan = bounds.east - bounds.west;

    for (final marker in map.hazardMarkers) {
      // Project to pixel coordinates
      final x =
          rect.left + ((marker.lon - bounds.west) / lonSpan) * rect.width;
      final y = rect.bottom -
          ((marker.lat - bounds.south) / latSpan) * rect.height;

      if (x < rect.left || x > rect.right || y < rect.top || y > rect.bottom) {
        continue; // outside map bounds
      }

      // Marker colors by hazard type
      final Color markerColor;
      switch (marker.type) {
        case HazardType.wildfire:
          markerColor = const Color(0xFFFF4500);
          break;
        case HazardType.flood:
          markerColor = const Color(0xFF1E90FF);
          break;
        case HazardType.drought:
          markerColor = const Color(0xFFDAA520);
          break;
        case HazardType.glacier:
          markerColor = const Color(0xFF87CEEB);
          break;
        default:
          markerColor = const Color(0xFFFF6347);
      }

      // Outer glow
      canvas.drawCircle(
        Offset(x, y),
        8,
        Paint()
          ..color = markerColor.withValues(alpha: 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );

      // Inner circle
      canvas.drawCircle(
        Offset(x, y),
        5,
        Paint()..color = markerColor,
      );

      // White border
      canvas.drawCircle(
        Offset(x, y),
        5,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );

      // Icon indicator (small character)
      final String iconChar;
      switch (marker.type) {
        case HazardType.wildfire:
          iconChar = 'F';
          break;
        case HazardType.flood:
          iconChar = 'W';
          break;
        case HazardType.drought:
          iconChar = 'D';
          break;
        case HazardType.glacier:
          iconChar = 'G';
          break;
        default:
          iconChar = '!';
      }
      _drawText(
        canvas,
        iconChar,
        Offset(x - 3, y - 5),
        fontSize: 8,
        color: Colors.white,
        bold: true,
      );
    }
  }

  void _paintCoordinateLabels(Canvas canvas, Rect rect) {
    // Place name labels at grid midpoint
    final bounds = map.bounds;
    final midLat = (bounds.north + bounds.south) / 2.0;
    final midLon = (bounds.east + bounds.west) / 2.0;

    _drawText(
      canvas,
      '${midLat.toStringAsFixed(2)}\u00B0N, ${midLon.toStringAsFixed(2)}\u00B0E',
      Offset(rect.left + rect.width * 0.35, rect.top + 4),
      fontSize: 10,
      color: const Color(0xFF8B949E),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // LEGEND
  // ─────────────────────────────────────────────────────────────

  void _paintLegend(Canvas canvas, Rect rect) {
    // Background
    canvas.drawRect(rect, Paint()..color = const Color(0xFF161B22));
    // Left divider
    canvas.drawLine(
      Offset(rect.left, rect.top),
      Offset(rect.left, rect.bottom),
      Paint()
        ..color = const Color(0xFF30363D)
        ..strokeWidth = 1,
    );

    final padding = 12.0;
    var y = rect.top + padding;

    // Title
    _drawText(canvas, 'LEGEND', Offset(rect.left + padding, y),
        fontSize: 12, color: const Color(0xFFF0F6FC), bold: true);
    y += 24;

    // Divider
    canvas.drawLine(
      Offset(rect.left + padding, y),
      Offset(rect.right - padding, y),
      Paint()
        ..color = const Color(0xFF30363D)
        ..strokeWidth = 0.5,
    );
    y += 12;

    // Risk level swatches
    _drawText(canvas, 'Risk Level', Offset(rect.left + padding, y),
        fontSize: 10, color: const Color(0xFF8B949E));
    y += 16;

    for (final level in RiskLevel.values) {
      // Color swatch
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(rect.left + padding, y, 16, 12),
          const Radius.circular(2),
        ),
        Paint()..color = level.color,
      );
      // Label
      _drawText(
        canvas,
        level.label,
        Offset(rect.left + padding + 22, y),
        fontSize: 10,
        color: const Color(0xFFC9D1D9),
      );
      y += 18;
    }

    y += 8;

    // Divider
    canvas.drawLine(
      Offset(rect.left + padding, y),
      Offset(rect.right - padding, y),
      Paint()
        ..color = const Color(0xFF30363D)
        ..strokeWidth = 0.5,
    );
    y += 12;

    // Hazard type icons
    _drawText(canvas, 'Hazard Types', Offset(rect.left + padding, y),
        fontSize: 10, color: const Color(0xFF8B949E));
    y += 16;

    // Count hazard types present
    final presentTypes = <HazardType, int>{};
    for (final marker in map.hazardMarkers) {
      presentTypes[marker.type] = (presentTypes[marker.type] ?? 0) + 1;
    }

    if (presentTypes.isEmpty) {
      _drawText(canvas, 'No active hazards', Offset(rect.left + padding, y),
          fontSize: 9, color: const Color(0xFF6E7681));
      y += 16;
    } else {
      for (final entry in presentTypes.entries) {
        final typeColor = entry.key.color;
        canvas.drawCircle(
          Offset(rect.left + padding + 6, y + 6),
          5,
          Paint()..color = typeColor,
        );
        _drawText(
          canvas,
          '${entry.key.label} (${entry.value})',
          Offset(rect.left + padding + 16, y),
          fontSize: 9,
          color: const Color(0xFFC9D1D9),
        );
        y += 18;
      }
    }

    y += 12;

    // North arrow
    _paintNorthArrow(canvas, Offset(rect.left + rect.width / 2, y + 10));
    y += 40;

    // Scale bar
    _paintScaleBar(canvas, Offset(rect.left + padding, y), rect.width - padding * 2);
    y += 30;

    // Data sources
    _drawText(canvas, 'Data Sources', Offset(rect.left + padding, y),
        fontSize: 10, color: const Color(0xFF8B949E));
    y += 14;
    final sources = ['FIRMS/NASA', 'NWS/NOAA', 'USGS', 'WorldPop (est.)'];
    for (final src in sources) {
      _drawText(canvas, '\u2022 $src', Offset(rect.left + padding, y),
          fontSize: 8, color: const Color(0xFF6E7681));
      y += 12;
    }
  }

  void _paintNorthArrow(Canvas canvas, Offset center) {
    final arrowPaint = Paint()
      ..color = const Color(0xFFF0F6FC)
      ..style = PaintingStyle.fill;
    final path = Path();
    path.moveTo(center.dx, center.dy - 14);
    path.lineTo(center.dx - 6, center.dy + 6);
    path.lineTo(center.dx, center.dy + 2);
    path.lineTo(center.dx + 6, center.dy + 6);
    path.close();
    canvas.drawPath(path, arrowPaint);

    _drawText(
      canvas,
      'N',
      Offset(center.dx - 4, center.dy - 28),
      fontSize: 11,
      color: const Color(0xFFF0F6FC),
      bold: true,
    );
  }

  void _paintScaleBar(Canvas canvas, Offset origin, double maxWidth) {
    final bounds = map.bounds;
    final midLat = (bounds.north + bounds.south) / 2.0;
    final lonSpan = bounds.east - bounds.west;
    final totalKm =
        lonSpan * 111.32 * math.cos(midLat * math.pi / 180.0);

    // Choose a nice round scale distance
    final scaleKm = _niceScaleDistance(totalKm * 0.3);
    final barWidth = (scaleKm / totalKm) * maxWidth;

    final paint = Paint()
      ..color = const Color(0xFFF0F6FC)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // Bar
    canvas.drawLine(origin, Offset(origin.dx + barWidth, origin.dy), paint);
    // End ticks
    canvas.drawLine(
        origin, Offset(origin.dx, origin.dy - 5), paint);
    canvas.drawLine(
        Offset(origin.dx + barWidth, origin.dy),
        Offset(origin.dx + barWidth, origin.dy - 5),
        paint);

    // Label
    final label = scaleKm >= 1 ? '${scaleKm.round()} km' : '${(scaleKm * 1000).round()} m';
    _drawText(
      canvas,
      label,
      Offset(origin.dx + barWidth / 2 - 12, origin.dy + 4),
      fontSize: 9,
      color: const Color(0xFFC9D1D9),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // STATISTICS PANEL
  // ─────────────────────────────────────────────────────────────

  void _paintStatsPanel(Canvas canvas, Rect rect) {
    // Background
    canvas.drawRect(rect, Paint()..color = const Color(0xFF161B22));

    // Top divider
    canvas.drawLine(
      Offset(rect.left, rect.top),
      Offset(rect.right, rect.top),
      Paint()
        ..color = const Color(0xFF30363D)
        ..strokeWidth = 1,
    );

    final report = map.report;
    final padding = 16.0;
    final colWidth = (rect.width - padding * 2) / 4;

    // Stat columns
    final stats = <_StatItem>[
      _StatItem(
        'Total Area',
        '${_formatNumber(report.totalAreaKm2)} km\u00B2',
      ),
      _StatItem(
        'Population Exposed',
        _formatNumber(report.totalPopulationExposed.toDouble()),
      ),
      _StatItem(
        'Critical Zone',
        '${report.areaPercentByRisk[RiskLevel.critical]?.toStringAsFixed(1) ?? '0.0'}%',
      ),
      _StatItem(
        'Top Hazard',
        report.topHazards.isNotEmpty ? report.topHazards.first : 'None',
      ),
    ];

    for (int i = 0; i < stats.length; i++) {
      final x = rect.left + padding + i * colWidth;
      final y = rect.top + 12;

      _drawText(canvas, stats[i].label, Offset(x, y),
          fontSize: 9, color: const Color(0xFF8B949E));
      _drawText(canvas, stats[i].value, Offset(x, y + 16),
          fontSize: 14, color: const Color(0xFFF0F6FC), bold: true);
    }

    // Risk distribution bar (bottom of stats panel)
    final barY = rect.top + rect.height * 0.6;
    final barHeight = 8.0;
    var barX = rect.left + padding;
    final barTotalWidth = rect.width - padding * 2;
    final total = report.areaByRisk.values.fold<double>(0, (a, b) => a + b);

    if (total > 0) {
      _drawText(canvas, 'Risk Distribution', Offset(rect.left + padding, barY - 14),
          fontSize: 9, color: const Color(0xFF8B949E));

      for (final level in RiskLevel.values) {
        final area = report.areaByRisk[level] ?? 0;
        final fraction = area / total;
        final segmentW = fraction * barTotalWidth;
        if (segmentW > 0) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(barX, barY, segmentW, barHeight),
              const Radius.circular(2),
            ),
            Paint()..color = level.color,
          );
          barX += segmentW;
        }
      }
    }

    // Attribution at very bottom
    _drawText(
      canvas,
      'Generated by EcoLens Cartographic Engine  |  '
          'Data may not reflect real-time conditions  |  '
          'For informational purposes only',
      Offset(rect.left + padding, rect.bottom - 16),
      fontSize: 7,
      color: const Color(0xFF484F58),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // TEXT DRAWING HELPER
  // ─────────────────────────────────────────────────────────────

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset, {
    double fontSize = 12,
    Color color = Colors.white,
    bool bold = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          color: color,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          fontFamily: 'monospace',
          letterSpacing: 0.3,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, offset);
  }

  // ─────────────────────────────────────────────────────────────
  // NUMERICAL HELPERS
  // ─────────────────────────────────────────────────────────────

  /// Choose a "nice" interval for graticule lines (1, 2, 5, 10...).
  static double _niceInterval(double span) {
    if (span <= 0) return 1.0;
    final rough = span / 5.0;
    final magnitude = math.pow(10, (math.log(rough) / math.ln10).floor());
    final residual = rough / magnitude;
    double nice;
    if (residual <= 1.5) {
      nice = 1.0;
    } else if (residual <= 3.0) {
      nice = 2.0;
    } else if (residual <= 7.0) {
      nice = 5.0;
    } else {
      nice = 10.0;
    }
    return nice * magnitude;
  }

  /// Choose a nice round distance for scale bar.
  static double _niceScaleDistance(double km) {
    if (km <= 0) return 1.0;
    final candidates = [
      0.1, 0.2, 0.5, 1, 2, 5, 10, 20, 50, 100, 200,
      500, 1000, 2000, 5000
    ];
    double best = candidates.first.toDouble();
    double bestDiff = double.infinity;
    for (final c in candidates) {
      final diff = (c - km).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = c.toDouble();
      }
    }
    return best;
  }

  /// Format a large number with commas.
  static String _formatNumber(double n) {
    if (n >= 1e6) return '${(n / 1e6).toStringAsFixed(1)}M';
    if (n >= 1e3) return '${(n / 1e3).toStringAsFixed(1)}K';
    return n.toStringAsFixed(0);
  }

  @override
  bool shouldRepaint(covariant CartographicMapPainter oldDelegate) {
    return oldDelegate.map != map;
  }
}

// ─────────────────────────────────────────────────────────────
// Small helper for stats panel
// ─────────────────────────────────────────────────────────────

class _StatItem {
  final String label;
  final String value;
  const _StatItem(this.label, this.value);
}
