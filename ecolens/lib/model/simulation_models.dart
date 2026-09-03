// ═══════════════════════════════════════════════════════════════
// SIMULATION & IMPACT ANALYSIS DATA MODELS
// Core data structures for the EcoLens simulation engine
// ═══════════════════════════════════════════════════════════════

/// Types of environmental simulations supported by EcoLens.
enum SimulationType { wildfire, flood, seaLevelRise, drought }

/// Fuel classification for wildfire simulations.
/// Based on Anderson's 13 fuel models (Anderson, 1982).
enum FuelType { grass, brush, timber, slash }

/// Drought severity levels per US Drought Monitor classification.
enum DroughtSeverity { d0, d1, d2, d3, d4 }

// ─────────────────────────────────────────────────────────────
// Extensions
// ─────────────────────────────────────────────────────────────

extension SimulationTypeExt on SimulationType {
  String get label {
    switch (this) {
      case SimulationType.wildfire:
        return 'Wildfire Spread';
      case SimulationType.flood:
        return 'Flood Inundation';
      case SimulationType.seaLevelRise:
        return 'Sea Level Rise';
      case SimulationType.drought:
        return 'Drought Projection';
    }
  }

  String get icon {
    switch (this) {
      case SimulationType.wildfire:
        return '\u{1F525}'; // fire
      case SimulationType.flood:
        return '\u{1F30A}'; // wave
      case SimulationType.seaLevelRise:
        return '\u{1F30A}'; // wave
      case SimulationType.drought:
        return '\u{2600}'; // sun
    }
  }

  String get description {
    switch (this) {
      case SimulationType.wildfire:
        return 'Simulate fire spread using simplified Rothermel model';
      case SimulationType.flood:
        return 'Model flood inundation using HAND approach';
      case SimulationType.seaLevelRise:
        return 'Project coastal inundation from sea level rise';
      case SimulationType.drought:
        return 'Forecast drought severity and agricultural impact';
    }
  }
}

extension FuelTypeExt on FuelType {
  String get label {
    switch (this) {
      case FuelType.grass:
        return 'Grass';
      case FuelType.brush:
        return 'Brush';
      case FuelType.timber:
        return 'Timber';
      case FuelType.slash:
        return 'Slash';
    }
  }

  /// Base spread rate in meters per minute (Anderson, 1982).
  double get baseSpreadRate {
    switch (this) {
      case FuelType.grass:
        return 2.0;
      case FuelType.brush:
        return 0.8;
      case FuelType.timber:
        return 0.5;
      case FuelType.slash:
        return 0.3;
    }
  }
}

extension DroughtSeverityExt on DroughtSeverity {
  String get label {
    switch (this) {
      case DroughtSeverity.d0:
        return 'D0 - Abnormally Dry';
      case DroughtSeverity.d1:
        return 'D1 - Moderate Drought';
      case DroughtSeverity.d2:
        return 'D2 - Severe Drought';
      case DroughtSeverity.d3:
        return 'D3 - Extreme Drought';
      case DroughtSeverity.d4:
        return 'D4 - Exceptional Drought';
    }
  }

  String get shortLabel {
    switch (this) {
      case DroughtSeverity.d0:
        return 'D0';
      case DroughtSeverity.d1:
        return 'D1';
      case DroughtSeverity.d2:
        return 'D2';
      case DroughtSeverity.d3:
        return 'D3';
      case DroughtSeverity.d4:
        return 'D4';
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// CONFIGURATION
// ═══════════════════════════════════════════════════════════════

/// Configuration for a simulation run.
class SimulationConfig {
  final SimulationType type;
  final double lat;
  final double lon;
  final Map<String, double> parameters;
  final int durationHours;

  const SimulationConfig({
    required this.type,
    required this.lat,
    required this.lon,
    required this.parameters,
    this.durationHours = 24,
  });

  SimulationConfig copyWith({
    SimulationType? type,
    double? lat,
    double? lon,
    Map<String, double>? parameters,
    int? durationHours,
  }) {
    return SimulationConfig(
      type: type ?? this.type,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      parameters: parameters ?? this.parameters,
      durationHours: durationHours ?? this.durationHours,
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// SIMULATION OUTPUT
// ═══════════════════════════════════════════════════════════════

/// A single frame in a time-stepping simulation (e.g., hourly fire perimeter).
class SimulationFrame {
  final int hour;
  final DateTime timestamp;
  final List<List<double>> perimeterCoords; // [lat, lon] pairs
  final double areaKm2;
  final double intensityPercent;

  const SimulationFrame({
    required this.hour,
    required this.timestamp,
    required this.perimeterCoords,
    required this.areaKm2,
    required this.intensityPercent,
  });
}

/// Complete result from a simulation run.
class SimulationResult {
  final SimulationConfig config;
  final List<SimulationFrame> frames;
  final ImpactAssessment impact;
  final List<CascadeEffect> cascades;
  final DateTime computedAt;

  const SimulationResult({
    required this.config,
    required this.frames,
    required this.impact,
    required this.cascades,
    required this.computedAt,
  });
}

// ═══════════════════════════════════════════════════════════════
// IMPACT ASSESSMENT
// ═══════════════════════════════════════════════════════════════

/// Quantified impact of a simulated hazard event.
class ImpactAssessment {
  final double areaAffectedKm2;
  final int populationExposed;
  final int hospitalsAtRisk;
  final int schoolsAtRisk;
  final int structuresAtRisk;
  final double estimatedLossUSD;
  final Map<String, double> demographicBreakdown;

  const ImpactAssessment({
    required this.areaAffectedKm2,
    required this.populationExposed,
    required this.hospitalsAtRisk,
    required this.schoolsAtRisk,
    required this.structuresAtRisk,
    required this.estimatedLossUSD,
    this.demographicBreakdown = const {},
  });
}

// ═══════════════════════════════════════════════════════════════
// CASCADING EFFECTS
// ═══════════════════════════════════════════════════════════════

/// A secondary or tertiary cascading effect from a primary hazard.
class CascadeEffect {
  final String name;
  final String description;
  final double probability;
  final String severity; // low, moderate, high, extreme
  final String timeframe; // "1-3 days", "1-2 weeks"
  final double additionalAreaKm2;
  final int additionalPopulation;
  final double additionalLossUSD;
  final String citation; // peer-reviewed source

  const CascadeEffect({
    required this.name,
    required this.description,
    required this.probability,
    required this.severity,
    required this.timeframe,
    this.additionalAreaKm2 = 0,
    this.additionalPopulation = 0,
    this.additionalLossUSD = 0,
    required this.citation,
  });
}

// ═══════════════════════════════════════════════════════════════
// IMPACT REPORT
// ═══════════════════════════════════════════════════════════════

/// A structured report generated from a simulation result.
class ImpactReport {
  final SimulationResult simulation;
  final String title;
  final DateTime generatedAt;
  final List<ReportSection> sections;

  const ImpactReport({
    required this.simulation,
    required this.title,
    required this.generatedAt,
    required this.sections,
  });
}

/// A section within an impact report (e.g., "Population Exposure").
class ReportSection {
  final String heading;
  final String body;
  final List<StatRow> stats;
  final String? citation;

  const ReportSection({
    required this.heading,
    required this.body,
    this.stats = const [],
    this.citation,
  });
}

/// A single statistic row within a report section.
class StatRow {
  final String label;
  final String value;
  final String? unit;
  final String? change; // "+15%" or "-20%"

  const StatRow({
    required this.label,
    required this.value,
    this.unit,
    this.change,
  });
}

// ═══════════════════════════════════════════════════════════════
// GRID CELL (internal, used by cellular automata)
// ═══════════════════════════════════════════════════════════════

/// State of a grid cell in the fire spread cellular automata.
enum CellState { unburned, burning, burned }

/// A single cell in the simulation grid.
class GridCell {
  CellState state;
  double elevation;
  double burnStartHour;

  GridCell({
    this.state = CellState.unburned,
    this.elevation = 0.0,
    this.burnStartHour = -1,
  });
}
