import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════
// HAZARD DATA MODELS
// Multi-hazard monitoring system data structures
// ═══════════════════════════════════════════════════════════════

/// Types of environmental hazards tracked by the monitoring system.
enum HazardType {
  wildfire,
  flood,
  drought,
  glacier,
  ndvi,
  watershed,
  riskSurface,
}

/// Severity classification for hazard events.
enum Severity { low, moderate, high, extreme }

// ─────────────────────────────────────────────────────────────
// Helper extensions
// ─────────────────────────────────────────────────────────────

extension HazardTypeExt on HazardType {
  String get label {
    switch (this) {
      case HazardType.wildfire:
        return 'Wildfire';
      case HazardType.flood:
        return 'Flood';
      case HazardType.drought:
        return 'Drought';
      case HazardType.glacier:
        return 'Glacier';
      case HazardType.ndvi:
        return 'NDVI';
      case HazardType.watershed:
        return 'Watershed';
      case HazardType.riskSurface:
        return 'Risk Surface';
    }
  }

  IconData get icon {
    switch (this) {
      case HazardType.wildfire:
        return Icons.local_fire_department;
      case HazardType.flood:
        return Icons.water;
      case HazardType.drought:
        return Icons.wb_sunny;
      case HazardType.glacier:
        return Icons.ac_unit;
      case HazardType.ndvi:
        return Icons.eco;
      case HazardType.watershed:
        return Icons.waves;
      case HazardType.riskSurface:
        return Icons.warning;
    }
  }

  Color get color {
    switch (this) {
      case HazardType.wildfire:
        return const Color(0xFFFF4500);
      case HazardType.flood:
        return const Color(0xFF1E90FF);
      case HazardType.drought:
        return const Color(0xFFDAA520);
      case HazardType.glacier:
        return const Color(0xFF87CEEB);
      case HazardType.ndvi:
        return const Color(0xFF32CD32);
      case HazardType.watershed:
        return const Color(0xFF4682B4);
      case HazardType.riskSurface:
        return const Color(0xFFFF6347);
    }
  }
}

extension SeverityExt on Severity {
  String get label {
    switch (this) {
      case Severity.low:
        return 'Low';
      case Severity.moderate:
        return 'Moderate';
      case Severity.high:
        return 'High';
      case Severity.extreme:
        return 'Extreme';
    }
  }

  Color get color {
    switch (this) {
      case Severity.low:
        return const Color(0xFF56D364);
      case Severity.moderate:
        return const Color(0xFFD29922);
      case Severity.high:
        return const Color(0xFFDB6D28);
      case Severity.extreme:
        return const Color(0xFFDA3633);
    }
  }

  int get index {
    switch (this) {
      case Severity.low:
        return 0;
      case Severity.moderate:
        return 1;
      case Severity.high:
        return 2;
      case Severity.extreme:
        return 3;
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Parsing helpers
// ─────────────────────────────────────────────────────────────

HazardType _parseHazardType(String value) {
  switch (value.toLowerCase()) {
    case 'wildfire':
      return HazardType.wildfire;
    case 'flood':
      return HazardType.flood;
    case 'drought':
      return HazardType.drought;
    case 'glacier':
      return HazardType.glacier;
    case 'ndvi':
      return HazardType.ndvi;
    case 'watershed':
      return HazardType.watershed;
    case 'risksurface':
    case 'risk_surface':
      return HazardType.riskSurface;
    default:
      return HazardType.wildfire;
  }
}

Severity _parseSeverity(String value) {
  switch (value.toLowerCase()) {
    case 'low':
      return Severity.low;
    case 'moderate':
      return Severity.moderate;
    case 'high':
      return Severity.high;
    case 'extreme':
      return Severity.extreme;
    default:
      return Severity.low;
  }
}

// ═══════════════════════════════════════════════════════════════
// CORE MODELS
// ═══════════════════════════════════════════════════════════════

/// A single hazard feature on the map.
class HazardFeature {
  final String id;
  final HazardType type;
  final Severity severity;
  final double latitude;
  final double longitude;
  final Map<String, dynamic> properties;
  final DateTime timestamp;
  final Map<String, dynamic>? geometry;

  const HazardFeature({
    required this.id,
    required this.type,
    required this.severity,
    required this.latitude,
    required this.longitude,
    required this.properties,
    required this.timestamp,
    this.geometry,
  });

  factory HazardFeature.fromJson(Map<String, dynamic> json) {
    return HazardFeature(
      id: json['id'] as String? ?? '',
      type: _parseHazardType(json['type'] as String? ?? 'wildfire'),
      severity: _parseSeverity(json['severity'] as String? ?? 'low'),
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      properties: Map<String, dynamic>.from(json['properties'] as Map? ?? {}),
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
      geometry: json['geometry'] as Map<String, dynamic>?,
    );
  }

  factory HazardFeature.fromGeoJSON(Map<String, dynamic> feature) {
    final props = Map<String, dynamic>.from(
      feature['properties'] as Map? ?? {},
    );
    final geom = feature['geometry'] as Map<String, dynamic>?;
    double lat = 0.0;
    double lon = 0.0;

    if (geom != null && geom['type'] == 'Point') {
      final coords = geom['coordinates'] as List;
      lon = (coords[0] as num).toDouble();
      lat = (coords[1] as num).toDouble();
    } else if (props.containsKey('latitude') && props.containsKey('longitude')) {
      lat = (props['latitude'] as num).toDouble();
      lon = (props['longitude'] as num).toDouble();
    }

    return HazardFeature(
      id: feature['id'] as String? ?? props['id'] as String? ?? '',
      type: _parseHazardType(props['hazardType'] as String? ?? 'wildfire'),
      severity: _parseSeverity(props['severity'] as String? ?? 'low'),
      latitude: lat,
      longitude: lon,
      properties: props,
      timestamp: props['timestamp'] != null
          ? DateTime.parse(props['timestamp'] as String)
          : DateTime.now(),
      geometry: geom,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'severity': severity.name,
      'latitude': latitude,
      'longitude': longitude,
      'properties': properties,
      'timestamp': timestamp.toIso8601String(),
      'geometry': geometry,
    };
  }

  Map<String, dynamic> toGeoJSON() {
    return {
      'type': 'Feature',
      'id': id,
      'geometry': geometry ??
          {
            'type': 'Point',
            'coordinates': [longitude, latitude],
          },
      'properties': {
        ...properties,
        'hazardType': type.name,
        'severity': severity.name,
        'timestamp': timestamp.toIso8601String(),
      },
    };
  }

  HazardFeature copyWith({
    String? id,
    HazardType? type,
    Severity? severity,
    double? latitude,
    double? longitude,
    Map<String, dynamic>? properties,
    DateTime? timestamp,
    Map<String, dynamic>? geometry,
  }) {
    return HazardFeature(
      id: id ?? this.id,
      type: type ?? this.type,
      severity: severity ?? this.severity,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      properties: properties ?? this.properties,
      timestamp: timestamp ?? this.timestamp,
      geometry: geometry ?? this.geometry,
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// FIRE HOTSPOT
// ═══════════════════════════════════════════════════════════════

class FireHotspot extends HazardFeature {
  final double brightness;
  final double frp;
  final String satellite;
  final double confidence;

  const FireHotspot({
    required super.id,
    required super.severity,
    required super.latitude,
    required super.longitude,
    required super.properties,
    required super.timestamp,
    super.geometry,
    required this.brightness,
    required this.frp,
    required this.satellite,
    required this.confidence,
  }) : super(type: HazardType.wildfire);

  factory FireHotspot.fromJson(Map<String, dynamic> json) {
    return FireHotspot(
      id: json['id'] as String? ?? '',
      severity: _parseSeverity(json['severity'] as String? ?? 'low'),
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      properties: Map<String, dynamic>.from(json['properties'] as Map? ?? {}),
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
      geometry: json['geometry'] as Map<String, dynamic>?,
      brightness: (json['brightness'] as num?)?.toDouble() ?? 0.0,
      frp: (json['frp'] as num?)?.toDouble() ?? 0.0,
      satellite: json['satellite'] as String? ?? 'unknown',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
    );
  }

  factory FireHotspot.fromGeoJSON(Map<String, dynamic> feature) {
    final props = Map<String, dynamic>.from(
      feature['properties'] as Map? ?? {},
    );
    final geom = feature['geometry'] as Map<String, dynamic>?;
    double lat = 0.0;
    double lon = 0.0;

    if (geom != null && geom['type'] == 'Point') {
      final coords = geom['coordinates'] as List;
      lon = (coords[0] as num).toDouble();
      lat = (coords[1] as num).toDouble();
    }

    return FireHotspot(
      id: feature['id'] as String? ?? props['id'] as String? ?? '',
      severity: _parseSeverity(props['severity'] as String? ?? 'low'),
      latitude: lat,
      longitude: lon,
      properties: props,
      timestamp: props['timestamp'] != null
          ? DateTime.parse(props['timestamp'] as String)
          : DateTime.now(),
      geometry: geom,
      brightness: (props['brightness'] as num?)?.toDouble() ?? 0.0,
      frp: (props['frp'] as num?)?.toDouble() ?? 0.0,
      satellite: props['satellite'] as String? ?? 'unknown',
      confidence: (props['confidence'] as num?)?.toDouble() ?? 0.0,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final base = super.toJson();
    base['brightness'] = brightness;
    base['frp'] = frp;
    base['satellite'] = satellite;
    base['confidence'] = confidence;
    return base;
  }

  @override
  FireHotspot copyWith({
    String? id,
    HazardType? type,
    Severity? severity,
    double? latitude,
    double? longitude,
    Map<String, dynamic>? properties,
    DateTime? timestamp,
    Map<String, dynamic>? geometry,
    double? brightness,
    double? frp,
    String? satellite,
    double? confidence,
  }) {
    return FireHotspot(
      id: id ?? this.id,
      severity: severity ?? this.severity,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      properties: properties ?? this.properties,
      timestamp: timestamp ?? this.timestamp,
      geometry: geometry ?? this.geometry,
      brightness: brightness ?? this.brightness,
      frp: frp ?? this.frp,
      satellite: satellite ?? this.satellite,
      confidence: confidence ?? this.confidence,
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// FLOOD ALERT
// ═══════════════════════════════════════════════════════════════

class FloodAlert extends HazardFeature {
  final double observedStage;
  final double floodStage;
  final String status;
  final List<double>? forecast;

  const FloodAlert({
    required super.id,
    required super.severity,
    required super.latitude,
    required super.longitude,
    required super.properties,
    required super.timestamp,
    super.geometry,
    required this.observedStage,
    required this.floodStage,
    required this.status,
    this.forecast,
  }) : super(type: HazardType.flood);

  factory FloodAlert.fromJson(Map<String, dynamic> json) {
    return FloodAlert(
      id: json['id'] as String? ?? '',
      severity: _parseSeverity(json['severity'] as String? ?? 'low'),
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      properties: Map<String, dynamic>.from(json['properties'] as Map? ?? {}),
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
      geometry: json['geometry'] as Map<String, dynamic>?,
      observedStage: (json['observedStage'] as num?)?.toDouble() ?? 0.0,
      floodStage: (json['floodStage'] as num?)?.toDouble() ?? 0.0,
      status: json['status'] as String? ?? 'unknown',
      forecast: (json['forecast'] as List?)
          ?.map((e) => (e as num).toDouble())
          .toList(),
    );
  }

  factory FloodAlert.fromGeoJSON(Map<String, dynamic> feature) {
    final props = Map<String, dynamic>.from(
      feature['properties'] as Map? ?? {},
    );
    final geom = feature['geometry'] as Map<String, dynamic>?;
    double lat = 0.0;
    double lon = 0.0;

    if (geom != null && geom['type'] == 'Point') {
      final coords = geom['coordinates'] as List;
      lon = (coords[0] as num).toDouble();
      lat = (coords[1] as num).toDouble();
    }

    return FloodAlert(
      id: feature['id'] as String? ?? props['id'] as String? ?? '',
      severity: _parseSeverity(props['severity'] as String? ?? 'low'),
      latitude: lat,
      longitude: lon,
      properties: props,
      timestamp: props['timestamp'] != null
          ? DateTime.parse(props['timestamp'] as String)
          : DateTime.now(),
      geometry: geom,
      observedStage: (props['observedStage'] as num?)?.toDouble() ?? 0.0,
      floodStage: (props['floodStage'] as num?)?.toDouble() ?? 0.0,
      status: props['status'] as String? ?? 'unknown',
      forecast: (props['forecast'] as List?)
          ?.map((e) => (e as num).toDouble())
          .toList(),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final base = super.toJson();
    base['observedStage'] = observedStage;
    base['floodStage'] = floodStage;
    base['status'] = status;
    base['forecast'] = forecast;
    return base;
  }

  @override
  FloodAlert copyWith({
    String? id,
    HazardType? type,
    Severity? severity,
    double? latitude,
    double? longitude,
    Map<String, dynamic>? properties,
    DateTime? timestamp,
    Map<String, dynamic>? geometry,
    double? observedStage,
    double? floodStage,
    String? status,
    List<double>? forecast,
  }) {
    return FloodAlert(
      id: id ?? this.id,
      severity: severity ?? this.severity,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      properties: properties ?? this.properties,
      timestamp: timestamp ?? this.timestamp,
      geometry: geometry ?? this.geometry,
      observedStage: observedStage ?? this.observedStage,
      floodStage: floodStage ?? this.floodStage,
      status: status ?? this.status,
      forecast: forecast ?? this.forecast,
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// DROUGHT STATUS
// ═══════════════════════════════════════════════════════════════

class DroughtStatus {
  final Map<String, double> severityPercentages;
  final String dominantSeverity;
  final DateTime reportDate;
  final List<Map<String, dynamic>> countyData;

  const DroughtStatus({
    required this.severityPercentages,
    required this.dominantSeverity,
    required this.reportDate,
    required this.countyData,
  });

  factory DroughtStatus.fromJson(Map<String, dynamic> json) {
    return DroughtStatus(
      severityPercentages: Map<String, double>.from(
        (json['severityPercentages'] as Map? ?? {}).map(
          (key, value) => MapEntry(key as String, (value as num).toDouble()),
        ),
      ),
      dominantSeverity: json['dominantSeverity'] as String? ?? 'D0',
      reportDate: json['reportDate'] != null
          ? DateTime.parse(json['reportDate'] as String)
          : DateTime.now(),
      countyData: (json['countyData'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'severityPercentages': severityPercentages,
      'dominantSeverity': dominantSeverity,
      'reportDate': reportDate.toIso8601String(),
      'countyData': countyData,
    };
  }

  DroughtStatus copyWith({
    Map<String, double>? severityPercentages,
    String? dominantSeverity,
    DateTime? reportDate,
    List<Map<String, dynamic>>? countyData,
  }) {
    return DroughtStatus(
      severityPercentages: severityPercentages ?? this.severityPercentages,
      dominantSeverity: dominantSeverity ?? this.dominantSeverity,
      reportDate: reportDate ?? this.reportDate,
      countyData: countyData ?? this.countyData,
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// GLACIER OUTLINE
// ═══════════════════════════════════════════════════════════════

class GlacierOutline extends HazardFeature {
  final double areaKm2;
  final String glacierName;
  final double? retreatRateKm2PerYear;

  const GlacierOutline({
    required super.id,
    required super.severity,
    required super.latitude,
    required super.longitude,
    required super.properties,
    required super.timestamp,
    super.geometry,
    required this.areaKm2,
    required this.glacierName,
    this.retreatRateKm2PerYear,
  }) : super(type: HazardType.glacier);

  factory GlacierOutline.fromJson(Map<String, dynamic> json) {
    return GlacierOutline(
      id: json['id'] as String? ?? '',
      severity: _parseSeverity(json['severity'] as String? ?? 'low'),
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      properties: Map<String, dynamic>.from(json['properties'] as Map? ?? {}),
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
      geometry: json['geometry'] as Map<String, dynamic>?,
      areaKm2: (json['areaKm2'] as num?)?.toDouble() ?? 0.0,
      glacierName: json['glacierName'] as String? ?? 'Unknown',
      retreatRateKm2PerYear:
          (json['retreatRateKm2PerYear'] as num?)?.toDouble(),
    );
  }

  factory GlacierOutline.fromGeoJSON(Map<String, dynamic> feature) {
    final props = Map<String, dynamic>.from(
      feature['properties'] as Map? ?? {},
    );
    final geom = feature['geometry'] as Map<String, dynamic>?;
    double lat = 0.0;
    double lon = 0.0;

    if (geom != null && geom['type'] == 'Point') {
      final coords = geom['coordinates'] as List;
      lon = (coords[0] as num).toDouble();
      lat = (coords[1] as num).toDouble();
    }

    return GlacierOutline(
      id: feature['id'] as String? ?? props['id'] as String? ?? '',
      severity: _parseSeverity(props['severity'] as String? ?? 'low'),
      latitude: lat,
      longitude: lon,
      properties: props,
      timestamp: props['timestamp'] != null
          ? DateTime.parse(props['timestamp'] as String)
          : DateTime.now(),
      geometry: geom,
      areaKm2: (props['areaKm2'] as num?)?.toDouble() ?? 0.0,
      glacierName: props['glacierName'] as String? ?? 'Unknown',
      retreatRateKm2PerYear:
          (props['retreatRateKm2PerYear'] as num?)?.toDouble(),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final base = super.toJson();
    base['areaKm2'] = areaKm2;
    base['glacierName'] = glacierName;
    base['retreatRateKm2PerYear'] = retreatRateKm2PerYear;
    return base;
  }

  @override
  GlacierOutline copyWith({
    String? id,
    HazardType? type,
    Severity? severity,
    double? latitude,
    double? longitude,
    Map<String, dynamic>? properties,
    DateTime? timestamp,
    Map<String, dynamic>? geometry,
    double? areaKm2,
    String? glacierName,
    double? retreatRateKm2PerYear,
  }) {
    return GlacierOutline(
      id: id ?? this.id,
      severity: severity ?? this.severity,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      properties: properties ?? this.properties,
      timestamp: timestamp ?? this.timestamp,
      geometry: geometry ?? this.geometry,
      areaKm2: areaKm2 ?? this.areaKm2,
      glacierName: glacierName ?? this.glacierName,
      retreatRateKm2PerYear:
          retreatRateKm2PerYear ?? this.retreatRateKm2PerYear,
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// NDVI RESULT
// ═══════════════════════════════════════════════════════════════

class NDVIResult {
  final double meanNDVI;
  final double anomaly;
  final String stressLevel;
  final Map<String, dynamic> gridGeoJSON;

  const NDVIResult({
    required this.meanNDVI,
    required this.anomaly,
    required this.stressLevel,
    required this.gridGeoJSON,
  });

  factory NDVIResult.fromJson(Map<String, dynamic> json) {
    return NDVIResult(
      meanNDVI: (json['meanNDVI'] as num?)?.toDouble() ?? 0.0,
      anomaly: (json['anomaly'] as num?)?.toDouble() ?? 0.0,
      stressLevel: json['stressLevel'] as String? ?? 'normal',
      gridGeoJSON:
          Map<String, dynamic>.from(json['gridGeoJSON'] as Map? ?? {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'meanNDVI': meanNDVI,
      'anomaly': anomaly,
      'stressLevel': stressLevel,
      'gridGeoJSON': gridGeoJSON,
    };
  }

  NDVIResult copyWith({
    double? meanNDVI,
    double? anomaly,
    String? stressLevel,
    Map<String, dynamic>? gridGeoJSON,
  }) {
    return NDVIResult(
      meanNDVI: meanNDVI ?? this.meanNDVI,
      anomaly: anomaly ?? this.anomaly,
      stressLevel: stressLevel ?? this.stressLevel,
      gridGeoJSON: gridGeoJSON ?? this.gridGeoJSON,
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// RISK SURFACE
// ═══════════════════════════════════════════════════════════════

class RiskSurface {
  final Map<String, dynamic> gridGeoJSON;
  final double maxRisk;
  final double meanRisk;
  final Map<HazardType, double> weights;

  const RiskSurface({
    required this.gridGeoJSON,
    required this.maxRisk,
    required this.meanRisk,
    required this.weights,
  });

  factory RiskSurface.fromJson(Map<String, dynamic> json) {
    final rawWeights = json['weights'] as Map? ?? {};
    final parsedWeights = <HazardType, double>{};
    for (final entry in rawWeights.entries) {
      parsedWeights[_parseHazardType(entry.key as String)] =
          (entry.value as num).toDouble();
    }

    return RiskSurface(
      gridGeoJSON:
          Map<String, dynamic>.from(json['gridGeoJSON'] as Map? ?? {}),
      maxRisk: (json['maxRisk'] as num?)?.toDouble() ?? 0.0,
      meanRisk: (json['meanRisk'] as num?)?.toDouble() ?? 0.0,
      weights: parsedWeights,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'gridGeoJSON': gridGeoJSON,
      'maxRisk': maxRisk,
      'meanRisk': meanRisk,
      'weights': weights.map((key, value) => MapEntry(key.name, value)),
    };
  }

  RiskSurface copyWith({
    Map<String, dynamic>? gridGeoJSON,
    double? maxRisk,
    double? meanRisk,
    Map<HazardType, double>? weights,
  }) {
    return RiskSurface(
      gridGeoJSON: gridGeoJSON ?? this.gridGeoJSON,
      maxRisk: maxRisk ?? this.maxRisk,
      meanRisk: meanRisk ?? this.meanRisk,
      weights: weights ?? this.weights,
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// DEM DATA
// ═══════════════════════════════════════════════════════════════

class DEMData {
  final String heightmapUrl;
  final double minElevation;
  final double maxElevation;
  final int resolution;
  final Map<String, double> bbox;

  /// Real-world E-W extent in metres (computed from bbox at actual latitude).
  final double terrainWidthM;

  /// Real-world N-S extent in metres (computed from bbox).
  final double terrainHeightM;

  /// Geographic centre latitude (WGS84) — the origin for Unity coordinate system.
  final double originLat;

  /// Geographic centre longitude (WGS84) — the origin for Unity coordinate system.
  final double originLon;

  const DEMData({
    required this.heightmapUrl,
    required this.minElevation,
    required this.maxElevation,
    required this.resolution,
    required this.bbox,
    this.terrainWidthM = 0,
    this.terrainHeightM = 0,
    this.originLat = 0,
    this.originLon = 0,
  });

  factory DEMData.fromJson(Map<String, dynamic> json) {
    return DEMData(
      heightmapUrl: json['heightmapUrl'] as String? ?? json['heightmap_url'] as String? ?? '',
      minElevation: (json['minElevation'] ?? json['min_elevation'] as num?)?.toDouble() ?? 0.0,
      maxElevation: (json['maxElevation'] ?? json['max_elevation'] as num?)?.toDouble() ?? 0.0,
      resolution: json['resolution'] as int? ?? 256,
      bbox: Map<String, double>.from(
        (json['bbox'] as Map? ?? {}).map(
          (key, value) => MapEntry(key as String, (value as num).toDouble()),
        ),
      ),
      terrainWidthM: (json['terrain_width_m'] as num?)?.toDouble() ?? 0,
      terrainHeightM: (json['terrain_height_m'] as num?)?.toDouble() ?? 0,
      originLat: (json['origin_lat'] as num?)?.toDouble() ?? 0,
      originLon: (json['origin_lon'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'heightmapUrl': heightmapUrl,
      'minElevation': minElevation,
      'maxElevation': maxElevation,
      'resolution': resolution,
      'bbox': bbox,
      'terrain_width_m': terrainWidthM,
      'terrain_height_m': terrainHeightM,
      'origin_lat': originLat,
      'origin_lon': originLon,
    };
  }

  DEMData copyWith({
    String? heightmapUrl,
    double? minElevation,
    double? maxElevation,
    int? resolution,
    Map<String, double>? bbox,
    double? terrainWidthM,
    double? terrainHeightM,
    double? originLat,
    double? originLon,
  }) {
    return DEMData(
      heightmapUrl: heightmapUrl ?? this.heightmapUrl,
      minElevation: minElevation ?? this.minElevation,
      maxElevation: maxElevation ?? this.maxElevation,
      resolution: resolution ?? this.resolution,
      bbox: bbox ?? this.bbox,
      terrainWidthM: terrainWidthM ?? this.terrainWidthM,
      terrainHeightM: terrainHeightM ?? this.terrainHeightM,
      originLat: originLat ?? this.originLat,
      originLon: originLon ?? this.originLon,
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// HAZARD COLLECTION
// ═══════════════════════════════════════════════════════════════

class HazardCollection {
  final Map<HazardType, List<HazardFeature>> features;
  final int totalCount;
  final DateTime fetchedAt;

  const HazardCollection({
    required this.features,
    required this.totalCount,
    required this.fetchedAt,
  });

  factory HazardCollection.fromJson(Map<String, dynamic> json) {
    final rawFeatures = json['features'] as Map? ?? {};
    final parsedFeatures = <HazardType, List<HazardFeature>>{};

    for (final entry in rawFeatures.entries) {
      final hazardType = _parseHazardType(entry.key as String);
      final featureList = (entry.value as List?)
              ?.map((e) =>
                  HazardFeature.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          [];
      parsedFeatures[hazardType] = featureList;
    }

    return HazardCollection(
      features: parsedFeatures,
      totalCount: json['totalCount'] as int? ?? 0,
      fetchedAt: json['fetchedAt'] != null
          ? DateTime.parse(json['fetchedAt'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'features': features.map(
        (key, value) => MapEntry(
          key.name,
          value.map((e) => e.toJson()).toList(),
        ),
      ),
      'totalCount': totalCount,
      'fetchedAt': fetchedAt.toIso8601String(),
    };
  }

  HazardCollection copyWith({
    Map<HazardType, List<HazardFeature>>? features,
    int? totalCount,
    DateTime? fetchedAt,
  }) {
    return HazardCollection(
      features: features ?? this.features,
      totalCount: totalCount ?? this.totalCount,
      fetchedAt: fetchedAt ?? this.fetchedAt,
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// FILTER STATE
// ═══════════════════════════════════════════════════════════════

class FilterState {
  Severity? minSeverity;
  DateTimeRange? dateRange;
  double opacity;
  bool visible;

  FilterState({
    this.minSeverity,
    this.dateRange,
    this.opacity = 1.0,
    this.visible = true,
  });

  factory FilterState.fromJson(Map<String, dynamic> json) {
    return FilterState(
      minSeverity: json['minSeverity'] != null
          ? _parseSeverity(json['minSeverity'] as String)
          : null,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      visible: json['visible'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'minSeverity': minSeverity?.name,
      'opacity': opacity,
      'visible': visible,
    };
  }

  FilterState copyWith({
    Severity? minSeverity,
    DateTimeRange? dateRange,
    double? opacity,
    bool? visible,
  }) {
    return FilterState(
      minSeverity: minSeverity ?? this.minSeverity,
      dateRange: dateRange ?? this.dateRange,
      opacity: opacity ?? this.opacity,
      visible: visible ?? this.visible,
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// BOUNDING BOX HELPER
// ═══════════════════════════════════════════════════════════════

/// Lightweight bounding box used for hazard queries (no dependency on
/// flutter_map's LatLngBounds so the model layer stays framework-agnostic).
class LatLngBounds {
  final double south;
  final double west;
  final double north;
  final double east;

  const LatLngBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  Map<String, double> toJson() => {
        'south': south,
        'west': west,
        'north': north,
        'east': east,
      };

  factory LatLngBounds.fromJson(Map<String, dynamic> json) {
    return LatLngBounds(
      south: (json['south'] as num).toDouble(),
      west: (json['west'] as num).toDouble(),
      north: (json['north'] as num).toDouble(),
      east: (json['east'] as num).toDouble(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// LOCATION MONITOR
// ═══════════════════════════════════════════════════════════════

class LocationMonitor {
  final String monitorId;
  final double latitude;
  final double longitude;
  final double radiusKm;
  final DateTime createdAt;
  final List<HazardType> watchTypes;

  const LocationMonitor({
    required this.monitorId,
    required this.latitude,
    required this.longitude,
    required this.radiusKm,
    required this.createdAt,
    required this.watchTypes,
  });

  factory LocationMonitor.fromJson(Map<String, dynamic> json) {
    return LocationMonitor(
      monitorId: json['monitorId'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      radiusKm: (json['radiusKm'] as num?)?.toDouble() ?? 10.0,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      watchTypes: (json['watchTypes'] as List?)
              ?.map((e) => _parseHazardType(e as String))
              .toList() ??
          HazardType.values,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'monitorId': monitorId,
      'latitude': latitude,
      'longitude': longitude,
      'radiusKm': radiusKm,
      'createdAt': createdAt.toIso8601String(),
      'watchTypes': watchTypes.map((e) => e.name).toList(),
    };
  }

  LocationMonitor copyWith({
    String? monitorId,
    double? latitude,
    double? longitude,
    double? radiusKm,
    DateTime? createdAt,
    List<HazardType>? watchTypes,
  }) {
    return LocationMonitor(
      monitorId: monitorId ?? this.monitorId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      radiusKm: radiusKm ?? this.radiusKm,
      createdAt: createdAt ?? this.createdAt,
      watchTypes: watchTypes ?? this.watchTypes,
    );
  }
}
