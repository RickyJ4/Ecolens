import 'package:flutter/material.dart';

import 'package:ecolens/model/hazard_models.dart';

// ═══════════════════════════════════════════════════════════════
// CARTOGRAPHIC MAP MODELS
// Data structures for the static cartographic map generation engine
// ═══════════════════════════════════════════════════════════════

/// Risk classification levels used for the risk surface color ramp.
enum RiskLevel {
  low,
  moderate,
  high,
  extreme,
  critical,
}

extension RiskLevelExt on RiskLevel {
  String get label {
    switch (this) {
      case RiskLevel.low:
        return 'Low';
      case RiskLevel.moderate:
        return 'Moderate';
      case RiskLevel.high:
        return 'High';
      case RiskLevel.extreme:
        return 'Extreme';
      case RiskLevel.critical:
        return 'Critical';
    }
  }

  /// Professional RdBu diverging color ramp (ColorBrewer).
  Color get color {
    switch (this) {
      case RiskLevel.low:
        return const Color(0xFF2166AC); // Blue
      case RiskLevel.moderate:
        return const Color(0xFF67A9CF); // Light blue
      case RiskLevel.high:
        return const Color(0xFFFDDBC7); // Light orange
      case RiskLevel.extreme:
        return const Color(0xFFEF8A62); // Orange
      case RiskLevel.critical:
        return const Color(0xFFB2182B); // Dark red
    }
  }

  /// Opacity-adjusted fill color for map cells.
  Color get fillColor => color.withValues(alpha: 0.75);
}

// ─────────────────────────────────────────────────────────────
// Risk Cell — one grid cell in the risk surface
// ─────────────────────────────────────────────────────────────

/// A single cell in the computed risk grid.
///
/// Each cell holds per-hazard risk scores (0-1), a composite weighted
/// score, and ancillary data (population density, elevation).
class RiskCell {
  final double lat;
  final double lon;
  final double fireRisk;
  final double floodRisk;
  final double seismicRisk;
  final double droughtRisk;
  final double compositeRisk;
  final RiskLevel level;
  final double populationDensity;
  final double elevationM;

  const RiskCell({
    required this.lat,
    required this.lon,
    this.fireRisk = 0.0,
    this.floodRisk = 0.0,
    this.seismicRisk = 0.0,
    this.droughtRisk = 0.0,
    required this.compositeRisk,
    required this.level,
    this.populationDensity = 0.0,
    this.elevationM = 0.0,
  });

  /// Classify a composite risk score (0-1) into a [RiskLevel].
  static RiskLevel classify(double score) {
    if (score >= 0.85) return RiskLevel.critical;
    if (score >= 0.65) return RiskLevel.extreme;
    if (score >= 0.40) return RiskLevel.high;
    if (score >= 0.20) return RiskLevel.moderate;
    return RiskLevel.low;
  }
}

// ─────────────────────────────────────────────────────────────
// Hazard Marker — point symbol for a specific hazard event
// ─────────────────────────────────────────────────────────────

class HazardMarker {
  final double lat;
  final double lon;
  final HazardType type;
  final String label;
  final Severity severity;

  const HazardMarker({
    required this.lat,
    required this.lon,
    required this.type,
    required this.label,
    required this.severity,
  });

  /// Map hazard type to a Unicode symbol used on the rendered map.
  String get symbol {
    switch (type) {
      case HazardType.wildfire:
        return '\u{1F525}'; // fire emoji fallback, painter uses icon
      case HazardType.flood:
        return '\u{1F30A}';
      case HazardType.drought:
        return '\u{2600}';
      case HazardType.glacier:
        return '\u{2744}';
      case HazardType.ndvi:
        return '\u{1F33F}';
      default:
        return '\u{26A0}';
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Map Report — summary statistics for the generated map
// ─────────────────────────────────────────────────────────────

class MapReport {
  final double totalAreaKm2;
  final Map<RiskLevel, double> areaByRisk; // km2 per level
  final Map<RiskLevel, int> populationByRisk; // people per level
  final int totalPopulationExposed;
  final List<String> topHazards;
  final Map<HazardType, int> hazardCounts;
  final DateTime dataTimestamp;

  const MapReport({
    required this.totalAreaKm2,
    required this.areaByRisk,
    required this.populationByRisk,
    required this.totalPopulationExposed,
    required this.topHazards,
    required this.hazardCounts,
    required this.dataTimestamp,
  });

  /// Percentage of total area at each risk level.
  Map<RiskLevel, double> get areaPercentByRisk {
    if (totalAreaKm2 <= 0) return {};
    return areaByRisk.map(
      (level, area) => MapEntry(level, (area / totalAreaKm2) * 100),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Cartographic Map — the full rendered map container
// ─────────────────────────────────────────────────────────────

/// Complete cartographic map produced by the engine.
///
/// Contains the risk grid, hazard markers, metadata, and the
/// pre-computed report. The [CartographicMapPainter] uses this
/// to render the map via Flutter Canvas.
class CartographicMap {
  final String title;
  final String subtitle;
  final LatLngBounds bounds;
  final List<List<RiskCell>> grid;
  final int gridWidth;
  final int gridHeight;
  final DateTime generatedAt;
  final MapReport report;
  final List<HazardMarker> hazardMarkers;

  /// Rendering options (can be toggled by the viewer widget).
  final bool showLegend;
  final bool showGrid;
  final bool showLabels;

  const CartographicMap({
    required this.title,
    required this.subtitle,
    required this.bounds,
    required this.grid,
    required this.gridWidth,
    required this.gridHeight,
    required this.generatedAt,
    required this.report,
    required this.hazardMarkers,
    this.showLegend = true,
    this.showGrid = true,
    this.showLabels = true,
  });

  /// Create a copy with toggled display flags.
  CartographicMap copyWith({
    String? title,
    String? subtitle,
    bool? showLegend,
    bool? showGrid,
    bool? showLabels,
  }) {
    return CartographicMap(
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      bounds: bounds,
      grid: grid,
      gridWidth: gridWidth,
      gridHeight: gridHeight,
      generatedAt: generatedAt,
      report: report,
      hazardMarkers: hazardMarkers,
      showLegend: showLegend ?? this.showLegend,
      showGrid: showGrid ?? this.showGrid,
      showLabels: showLabels ?? this.showLabels,
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Weight presets for risk computation
// ─────────────────────────────────────────────────────────────

/// Default hazard weight presets for common scenarios.
class RiskWeightPresets {
  static const Map<HazardType, double> balanced = {
    HazardType.wildfire: 0.30,
    HazardType.flood: 0.30,
    HazardType.drought: 0.20,
    HazardType.glacier: 0.10,
    HazardType.ndvi: 0.10,
  };

  static const Map<HazardType, double> fireEmphasis = {
    HazardType.wildfire: 0.55,
    HazardType.flood: 0.15,
    HazardType.drought: 0.20,
    HazardType.glacier: 0.05,
    HazardType.ndvi: 0.05,
  };

  static const Map<HazardType, double> floodEmphasis = {
    HazardType.wildfire: 0.10,
    HazardType.flood: 0.55,
    HazardType.drought: 0.15,
    HazardType.glacier: 0.10,
    HazardType.ndvi: 0.10,
  };
}
