import 'package:flutter/material.dart';

/// Types of spatial analysis available
enum SpatialAnalysisType {
  changeDetection,
  vegetationIndex,
  bufferAnalysis,
  proximityAnalysis,
  hotspotAnalysis,
  patternAnalysis,
  riskModeling,
  predictiveRiskMap,
  fragmentationAnalysis,
}

/// Extension for display properties
extension SpatialAnalysisTypeExtension on SpatialAnalysisType {
  String get displayName {
    switch (this) {
      case SpatialAnalysisType.changeDetection:
        return 'Change Detection';
      case SpatialAnalysisType.vegetationIndex:
        return 'Vegetation Index';
      case SpatialAnalysisType.bufferAnalysis:
        return 'Buffer Analysis';
      case SpatialAnalysisType.proximityAnalysis:
        return 'Proximity Analysis';
      case SpatialAnalysisType.hotspotAnalysis:
        return 'Hotspot Analysis';
      case SpatialAnalysisType.patternAnalysis:
        return 'Pattern Analysis';
      case SpatialAnalysisType.riskModeling:
        return 'Risk Modeling';
      case SpatialAnalysisType.predictiveRiskMap:
        return 'Predictive Risk Map';
      case SpatialAnalysisType.fragmentationAnalysis:
        return 'Fragmentation Analysis';
    }
  }

  IconData get icon {
    switch (this) {
      case SpatialAnalysisType.changeDetection:
        return Icons.compare_arrows;
      case SpatialAnalysisType.vegetationIndex:
        return Icons.eco;
      case SpatialAnalysisType.bufferAnalysis:
        return Icons.radio_button_unchecked;
      case SpatialAnalysisType.proximityAnalysis:
        return Icons.near_me;
      case SpatialAnalysisType.hotspotAnalysis:
        return Icons.local_fire_department;
      case SpatialAnalysisType.patternAnalysis:
        return Icons.bubble_chart;
      case SpatialAnalysisType.riskModeling:
        return Icons.trending_up;
      case SpatialAnalysisType.predictiveRiskMap:
        return Icons.map;
      case SpatialAnalysisType.fragmentationAnalysis:
        return Icons.dashboard;
    }
  }

  Color get color {
    switch (this) {
      case SpatialAnalysisType.changeDetection:
        return const Color(0xFFFF6B6B);
      case SpatialAnalysisType.vegetationIndex:
        return const Color(0xFF00E676);
      case SpatialAnalysisType.bufferAnalysis:
        return const Color(0xFF64B5F6);
      case SpatialAnalysisType.proximityAnalysis:
        return const Color(0xFFFFB74D);
      case SpatialAnalysisType.hotspotAnalysis:
        return const Color(0xFFFF5722);
      case SpatialAnalysisType.patternAnalysis:
        return const Color(0xFF9C27B0);
      case SpatialAnalysisType.riskModeling:
        return const Color(0xFFE91E63);
      case SpatialAnalysisType.predictiveRiskMap:
        return const Color(0xFFD32F2F);
      case SpatialAnalysisType.fragmentationAnalysis:
        return const Color(0xFF00BCD4);
    }
  }
}

/// A single statistic from analysis
class AnalysisStatistic {
  final String label;
  final String value;
  final String? unit;
  final Color? color;
  final IconData? icon;

  const AnalysisStatistic({
    required this.label,
    required this.value,
    this.unit,
    this.color,
    this.icon,
  });
}

/// Legend item for map visualization
class LegendItem {
  final String label;
  final Color color;
  final double? minValue;
  final double? maxValue;

  const LegendItem({
    required this.label,
    required this.color,
    this.minValue,
    this.maxValue,
  });
}

/// Result of a spatial analysis operation
class SpatialAnalysisResult {
  final SpatialAnalysisType type;
  final Map<String, dynamic> summary;
  final Map<String, dynamic> geoJson;
  final List<AnalysisStatistic> statistics;
  final List<LegendItem> legend;
  final DateTime timestamp;
  final String? errorMessage;
  final bool isSuccess;
  final int nodeCount;
  final Duration processingTime;

  const SpatialAnalysisResult({
    required this.type,
    required this.summary,
    required this.geoJson,
    required this.statistics,
    required this.legend,
    required this.timestamp,
    this.errorMessage,
    this.isSuccess = true,
    this.nodeCount = 0,
    this.processingTime = Duration.zero,
  });

  factory SpatialAnalysisResult.error(SpatialAnalysisType type, String message) {
    return SpatialAnalysisResult(
      type: type,
      summary: {},
      geoJson: {'type': 'FeatureCollection', 'features': []},
      statistics: [],
      legend: [],
      timestamp: DateTime.now(),
      errorMessage: message,
      isSuccess: false,
    );
  }

  factory SpatialAnalysisResult.empty(SpatialAnalysisType type) {
    return SpatialAnalysisResult(
      type: type,
      summary: {},
      geoJson: {'type': 'FeatureCollection', 'features': []},
      statistics: [
        const AnalysisStatistic(
          label: 'Status',
          value: 'No data available',
        ),
      ],
      legend: [],
      timestamp: DateTime.now(),
      nodeCount: 0,
    );
  }
}

/// Configuration for analysis operations
class AnalysisConfig {
  final int? startYear;
  final int? endYear;
  final double? bufferDistanceKm;
  final String? infrastructureType;
  final String? vegetationIndex;
  final String? patternVariable;
  final int? forecastYears;
  final double? significanceLevel;
  final double? bandwidthKm;
  final double? riskThresholdKm; // For predictive risk mapping
  final double? minPatchSizeHa; // For fragmentation analysis

  const AnalysisConfig({
    this.startYear,
    this.endYear,
    this.bufferDistanceKm,
    this.infrastructureType,
    this.vegetationIndex,
    this.patternVariable,
    this.forecastYears,
    this.significanceLevel = 0.05,
    this.bandwidthKm = 50.0,
    this.riskThresholdKm = 2.0,
    this.minPatchSizeHa = 100.0,
  });

  /// Default config for each analysis type
  factory AnalysisConfig.defaultFor(SpatialAnalysisType type) {
    switch (type) {
      case SpatialAnalysisType.changeDetection:
        return const AnalysisConfig(startYear: 2015, endYear: 2024);
      case SpatialAnalysisType.vegetationIndex:
        return const AnalysisConfig(vegetationIndex: 'ndvi');
      case SpatialAnalysisType.bufferAnalysis:
        return const AnalysisConfig(bufferDistanceKm: 5.0);
      case SpatialAnalysisType.proximityAnalysis:
        return const AnalysisConfig(infrastructureType: 'roads');
      case SpatialAnalysisType.hotspotAnalysis:
        return const AnalysisConfig(bandwidthKm: 50.0, significanceLevel: 0.05);
      case SpatialAnalysisType.patternAnalysis:
        return const AnalysisConfig(patternVariable: 'riskScore');
      case SpatialAnalysisType.riskModeling:
        return const AnalysisConfig(forecastYears: 5);
      case SpatialAnalysisType.predictiveRiskMap:
        return const AnalysisConfig(riskThresholdKm: 2.0, infrastructureType: 'roads');
      case SpatialAnalysisType.fragmentationAnalysis:
        return const AnalysisConfig(minPatchSizeHa: 100.0);
    }
  }
}

/// LISA (Local Indicators of Spatial Association) result
class LISAResult {
  final String nodeId;
  final double lat;
  final double lng;
  final double localI;
  final double zScore;
  final double pValue;
  final LISAQuadrant quadrant;

  const LISAResult({
    required this.nodeId,
    required this.lat,
    required this.lng,
    required this.localI,
    required this.zScore,
    required this.pValue,
    required this.quadrant,
  });
}

/// LISA quadrant classification
enum LISAQuadrant {
  highHigh, // Cluster of high values
  lowLow, // Cluster of low values
  highLow, // High outlier among low values
  lowHigh, // Low outlier among high values
  notSignificant,
}

extension LISAQuadrantExtension on LISAQuadrant {
  String get label {
    switch (this) {
      case LISAQuadrant.highHigh:
        return 'High-High';
      case LISAQuadrant.lowLow:
        return 'Low-Low';
      case LISAQuadrant.highLow:
        return 'High-Low';
      case LISAQuadrant.lowHigh:
        return 'Low-High';
      case LISAQuadrant.notSignificant:
        return 'Not Significant';
    }
  }

  Color get color {
    switch (this) {
      case LISAQuadrant.highHigh:
        return const Color(0xFFFF0000); // Red
      case LISAQuadrant.lowLow:
        return const Color(0xFF0000FF); // Blue
      case LISAQuadrant.highLow:
        return const Color(0xFFFFA500); // Orange
      case LISAQuadrant.lowHigh:
        return const Color(0xFF87CEEB); // Light Blue
      case LISAQuadrant.notSignificant:
        return const Color(0xFFCCCCCC); // Gray
    }
  }
}

/// Getis-Ord Gi* result for a single point
class HotspotResult {
  final String nodeId;
  final double lat;
  final double lng;
  final double giStar;
  final double zScore;
  final double pValue;
  final HotspotClassification classification;

  const HotspotResult({
    required this.nodeId,
    required this.lat,
    required this.lng,
    required this.giStar,
    required this.zScore,
    required this.pValue,
    required this.classification,
  });
}

/// Hotspot classification based on z-score
enum HotspotClassification {
  hotspot99, // z > 2.58 (99% confidence)
  hotspot95, // z > 1.96 (95% confidence)
  hotspot90, // z > 1.65 (90% confidence)
  notSignificant,
  coldspot90, // z < -1.65
  coldspot95, // z < -1.96
  coldspot99, // z < -2.58
}

extension HotspotClassificationExtension on HotspotClassification {
  String get label {
    switch (this) {
      case HotspotClassification.hotspot99:
        return 'Hot Spot (99%)';
      case HotspotClassification.hotspot95:
        return 'Hot Spot (95%)';
      case HotspotClassification.hotspot90:
        return 'Hot Spot (90%)';
      case HotspotClassification.notSignificant:
        return 'Not Significant';
      case HotspotClassification.coldspot90:
        return 'Cold Spot (90%)';
      case HotspotClassification.coldspot95:
        return 'Cold Spot (95%)';
      case HotspotClassification.coldspot99:
        return 'Cold Spot (99%)';
    }
  }

  Color get color {
    switch (this) {
      case HotspotClassification.hotspot99:
        return const Color(0xFFB30000); // Dark Red
      case HotspotClassification.hotspot95:
        return const Color(0xFFFF0000); // Red
      case HotspotClassification.hotspot90:
        return const Color(0xFFFF8C00); // Orange
      case HotspotClassification.notSignificant:
        return const Color(0xFF888888); // Gray
      case HotspotClassification.coldspot90:
        return const Color(0xFF87CEEB); // Light Blue
      case HotspotClassification.coldspot95:
        return const Color(0xFF0000FF); // Blue
      case HotspotClassification.coldspot99:
        return const Color(0xFF00008B); // Dark Blue
    }
  }
}

/// Global Moran's I result
class MoransIResult {
  final double moransI;
  final double expectedI;
  final double variance;
  final double zScore;
  final double pValue;
  final SpatialPattern pattern;

  const MoransIResult({
    required this.moransI,
    required this.expectedI,
    required this.variance,
    required this.zScore,
    required this.pValue,
    required this.pattern,
  });
}

/// Spatial pattern interpretation
enum SpatialPattern {
  clustered, // Positive spatial autocorrelation
  dispersed, // Negative spatial autocorrelation
  random, // No significant pattern
}

extension SpatialPatternExtension on SpatialPattern {
  String get description {
    switch (this) {
      case SpatialPattern.clustered:
        return 'Clustered - similar values are grouped together';
      case SpatialPattern.dispersed:
        return 'Dispersed - dissimilar values are near each other';
      case SpatialPattern.random:
        return 'Random - no significant spatial pattern';
    }
  }
}
