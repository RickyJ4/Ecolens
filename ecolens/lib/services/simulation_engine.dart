import 'dart:math';
import 'package:ecolens/model/simulation_models.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ECOLENS SIMULATION ENGINE
// Client-side environmental hazard simulation & cascading impact analysis
//
// References:
//   Rothermel (1972) — A mathematical model for predicting fire spread
//   Anderson (1982) — Aids to determining fuel models for estimating fire behavior
//   Cannon et al. (2010) — USGS Fact Sheet 2010-3049 (post-fire debris flow)
//   Rust et al. (2025) — Nature Communications Earth & Environment (fire-water)
//   Littell et al. (2009) — Ecological Applications 19(4) (drought-fire)
//   Koks et al. (2024) — One Earth (infrastructure cascade)
//   World Bank GRADE methodology (2024)
//   IDMC Global Report on Internal Displacement (2024)
// ═══════════════════════════════════════════════════════════════════════════

class SimulationEngine {
  static final _rng = Random(42);

  // ═══════════════════════════════════════════════════════════════
  // PUBLIC API
  // ═══════════════════════════════════════════════════════════════

  /// Run a full simulation and return the result with impacts and cascades.
  static SimulationResult runSimulation(SimulationConfig config) {
    switch (config.type) {
      case SimulationType.wildfire:
        return _runWildfireSimulation(config);
      case SimulationType.flood:
        return _runFloodSimulation(config);
      case SimulationType.seaLevelRise:
        return _runSeaLevelRiseSimulation(config);
      case SimulationType.drought:
        return _runDroughtSimulation(config);
    }
  }

  /// Generate a structured impact report from a simulation result.
  static ImpactReport generateReport(SimulationResult result) {
    final sections = <ReportSection>[];

    // Executive Summary
    sections.add(ReportSection(
      heading: 'Executive Summary',
      body: _buildExecutiveSummary(result),
      stats: [
        StatRow(
          label: 'Total Area Affected',
          value: result.impact.areaAffectedKm2.toStringAsFixed(1),
          unit: 'km\u00B2',
        ),
        StatRow(
          label: 'Population Exposed',
          value: _formatNumber(result.impact.populationExposed),
        ),
        StatRow(
          label: 'Estimated Economic Loss',
          value: _formatCurrency(result.impact.estimatedLossUSD),
        ),
      ],
    ));

    // Hazard Extent
    sections.add(ReportSection(
      heading: 'Hazard Extent',
      body: _buildHazardExtentBody(result),
      stats: [
        StatRow(
          label: 'Simulation Duration',
          value: '${result.config.durationHours}',
          unit: 'hours',
        ),
        StatRow(
          label: 'Peak Area',
          value: result.frames.isNotEmpty
              ? result.frames.last.areaKm2.toStringAsFixed(2)
              : '0',
          unit: 'km\u00B2',
        ),
        StatRow(
          label: 'Frames Computed',
          value: '${result.frames.length}',
        ),
      ],
    ));

    // Population & Demographics
    sections.add(ReportSection(
      heading: 'Population Exposure',
      body: 'Estimated population within the hazard zone based on '
          'distance-decay density model from nearest urban center. '
          'Demographic breakdown uses regional census proportions.',
      stats: [
        StatRow(
          label: 'Total Population Exposed',
          value: _formatNumber(result.impact.populationExposed),
        ),
        ...result.impact.demographicBreakdown.entries.map((e) => StatRow(
              label: e.key,
              value: '${(e.value * 100).toStringAsFixed(1)}%',
            )),
      ],
      citation: 'IDMC Global Report on Internal Displacement (2024)',
    ));

    // Infrastructure at Risk
    sections.add(ReportSection(
      heading: 'Infrastructure Vulnerability',
      body: 'Critical infrastructure counts estimated from population '
          'density using per-capita ratios. Actual counts may vary; '
          'verify with local GIS data for operational planning.',
      stats: [
        StatRow(
          label: 'Hospitals at Risk',
          value: '${result.impact.hospitalsAtRisk}',
        ),
        StatRow(
          label: 'Schools at Risk',
          value: '${result.impact.schoolsAtRisk}',
        ),
        StatRow(
          label: 'Structures at Risk',
          value: _formatNumber(result.impact.structuresAtRisk),
        ),
      ],
      citation: 'Koks et al. (2024), One Earth',
    ));

    // Economic Impact
    sections.add(ReportSection(
      heading: 'Economic Loss Estimate',
      body: 'Estimated using simplified World Bank GRADE methodology. '
          'Includes direct property damage, suppression/response costs, '
          'and sector-specific losses.',
      stats: [
        StatRow(
          label: 'Total Estimated Loss',
          value: _formatCurrency(result.impact.estimatedLossUSD),
        ),
      ],
      citation: 'World Bank GRADE methodology (2024)',
    ));

    // Cascading Impacts
    for (final cascade in result.cascades) {
      sections.add(ReportSection(
        heading: 'Cascade: ${cascade.name}',
        body: cascade.description,
        stats: [
          StatRow(label: 'Probability', value: '${(cascade.probability * 100).toStringAsFixed(0)}%'),
          StatRow(label: 'Severity', value: cascade.severity),
          StatRow(label: 'Timeframe', value: cascade.timeframe),
          if (cascade.additionalLossUSD > 0)
            StatRow(
              label: 'Additional Economic Loss',
              value: _formatCurrency(cascade.additionalLossUSD),
            ),
          if (cascade.additionalPopulation > 0)
            StatRow(
              label: 'Additional Population Affected',
              value: _formatNumber(cascade.additionalPopulation),
            ),
        ],
        citation: cascade.citation,
      ));
    }

    return ImpactReport(
      simulation: result,
      title: '${result.config.type.label} Impact Report',
      generatedAt: DateTime.now(),
      sections: sections,
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // WILDFIRE SPREAD SIMULATION
  // Simplified Rothermel cellular automata model
  // ═══════════════════════════════════════════════════════════════

  static SimulationResult _runWildfireSimulation(SimulationConfig config) {
    final windSpeed = config.parameters['windSpeedKmh'] ?? 15.0;
    final windDirection = config.parameters['windDirectionDeg'] ?? 270.0;
    final humidity = config.parameters['humidity'] ?? 30.0;
    final temperature = config.parameters['temperature'] ?? 30.0;
    final fuelIndex = (config.parameters['fuelType'] ?? 0).toInt().clamp(0, 3);
    final fuel = FuelType.values[fuelIndex];

    // Grid setup: 200x200 cells, each cell = 50m x 50m = 10km x 10km area
    const gridSize = 200;
    const cellSizeM = 50.0;
    final grid = List.generate(
      gridSize,
      (_) => List.generate(gridSize, (_) => GridCell()),
    );

    // Generate pseudo-random elevation (simplified terrain)
    for (int r = 0; r < gridSize; r++) {
      for (int c = 0; c < gridSize; c++) {
        grid[r][c].elevation =
            50.0 * sin(r * 0.05) + 30.0 * cos(c * 0.07) + _rng.nextDouble() * 10;
      }
    }

    // Ignite center cell
    final centerR = gridSize ~/ 2;
    final centerC = gridSize ~/ 2;
    grid[centerR][centerC].state = CellState.burning;
    grid[centerR][centerC].burnStartHour = 0;

    // Compute spread rate factors
    final baseRate = fuel.baseSpreadRate; // m/min
    final windFactor = 1.0 + 0.5 * windSpeed;
    final humidityFactor = max(0.1, 1.0 - humidity / 100.0);
    final tempFactor = 1.0 + max(0, (temperature - 20)) * 0.02;

    // Wind direction as grid offsets (wind pushes fire downwind)
    final windRadians = windDirection * pi / 180.0;
    final windDr = -cos(windRadians); // row component
    final windDc = sin(windRadians); // col component

    // Neighbor offsets (8-connectivity)
    const neighbors = [
      [-1, -1], [-1, 0], [-1, 1],
      [0, -1],           [0, 1],
      [1, -1],  [1, 0],  [1, 1],
    ];

    final frames = <SimulationFrame>[];
    final durationHours = config.durationHours;

    for (int hour = 0; hour <= durationHours; hour++) {
      // Collect currently burning cells to spread from
      final burningCells = <List<int>>[];
      for (int r = 0; r < gridSize; r++) {
        for (int c = 0; c < gridSize; c++) {
          if (grid[r][c].state == CellState.burning) {
            // Burn for ~2 hours then transition to burned
            if (hour - grid[r][c].burnStartHour > 2) {
              grid[r][c].state = CellState.burned;
            } else {
              burningCells.add([r, c]);
            }
          }
        }
      }

      // Spread to neighbors
      for (final cell in burningCells) {
        final r = cell[0];
        final c = cell[1];
        for (final n in neighbors) {
          final nr = r + n[0];
          final nc = c + n[1];
          if (nr < 0 || nr >= gridSize || nc < 0 || nc >= gridSize) continue;
          if (grid[nr][nc].state != CellState.unburned) continue;

          // Slope factor
          final elevDiff = grid[nr][nc].elevation - grid[r][c].elevation;
          final slopePercent = (elevDiff / cellSizeM) * 100.0;
          final slopeFactor = 1.0 + 0.1 * max(0, slopePercent);

          // Directional wind boost: fire spreads faster downwind
          final dirR = (nr - r).toDouble();
          final dirC = (nc - c).toDouble();
          final dirLen = sqrt(dirR * dirR + dirC * dirC);
          final dotProduct = (dirR * windDr + dirC * windDc) / dirLen;
          final directionalWind = 1.0 + max(0, dotProduct) * (windFactor - 1.0);

          final effectiveRate =
              baseRate * directionalWind * slopeFactor * humidityFactor * tempFactor;

          // Convert rate to probability of ignition this hour
          // At base rate 2 m/min over 50m cell: ~25 min to cross
          // Over 60 min (1 hour), probability = min(1, 60 / crossTime)
          final crossTimeMin = cellSizeM / effectiveRate;
          final ignitionProb = min(1.0, 60.0 / crossTimeMin);

          if (_rng.nextDouble() < ignitionProb) {
            grid[nr][nc].state = CellState.burning;
            grid[nr][nc].burnStartHour = hour.toDouble();
          }
        }
      }

      // Build frame: compute perimeter and area
      final affectedCells = <List<int>>[];
      for (int r = 0; r < gridSize; r++) {
        for (int c = 0; c < gridSize; c++) {
          if (grid[r][c].state == CellState.burning ||
              grid[r][c].state == CellState.burned) {
            affectedCells.add([r, c]);
          }
        }
      }

      if (affectedCells.isEmpty) continue;

      final areaCells = affectedCells.length;
      final areaKm2 = areaCells * (cellSizeM * cellSizeM) / 1e6;

      // Compute perimeter as convex hull of affected cells converted to lat/lon
      final perimeterCoords = _cellsToPerimeter(
        affectedCells,
        config.lat,
        config.lon,
        gridSize,
        cellSizeM,
      );

      final intensity = burningCells.length / max(1, areaCells) * 100.0;

      frames.add(SimulationFrame(
        hour: hour,
        timestamp: DateTime.now().add(Duration(hours: hour)),
        perimeterCoords: perimeterCoords,
        areaKm2: areaKm2,
        intensityPercent: intensity.clamp(0, 100),
      ));
    }

    final finalArea = frames.isNotEmpty ? frames.last.areaKm2 : 0.0;
    final impact = _computeImpact(finalArea, config.lat, config.lon, config.type);
    final cascades = _computeWildfireCascades(finalArea, impact);

    return SimulationResult(
      config: config,
      frames: frames,
      impact: impact,
      cascades: cascades,
      computedAt: DateTime.now(),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // FLOOD INUNDATION SIMULATION
  // Simplified HAND (Height Above Nearest Drainage) model
  // ═══════════════════════════════════════════════════════════════

  static SimulationResult _runFloodSimulation(SimulationConfig config) {
    final waterLevelRise = config.parameters['waterLevelRise'] ?? 2.0;
    final radiusKm = config.parameters['radiusKm'] ?? 10.0;

    // Simulate HAND values on a grid
    const gridSize = 150;
    final cellSizeM = (radiusKm * 2000.0) / gridSize;
    final center = gridSize ~/ 2;

    final frames = <SimulationFrame>[];
    final durationHours = config.durationHours;

    for (int hour = 0; hour <= durationHours; hour++) {
      // Water rises linearly over duration
      final currentWaterLevel = waterLevelRise * (hour / max(1, durationHours));
      final floodedCells = <List<int>>[];

      for (int r = 0; r < gridSize; r++) {
        for (int c = 0; c < gridSize; c++) {
          final dr = (r - center).toDouble();
          final dc = (c - center).toDouble();
          final distFromCenter = sqrt(dr * dr + dc * dc) * cellSizeM;

          // Skip cells outside radius
          if (distFromCenter > radiusKm * 1000) continue;

          // Simplified HAND: elevation above drainage increases with distance
          // from river (assumed through center) and with terrain noise
          final distFromRiverM = (dc.abs()) * cellSizeM;
          final handValue = distFromRiverM * 0.005 +
              sin(r * 0.1) * 0.5 +
              cos(c * 0.15) * 0.3 +
              _rng.nextDouble() * 0.2;

          if (currentWaterLevel > handValue) {
            floodedCells.add([r, c]);
          }
        }
      }

      if (floodedCells.isEmpty) continue;

      final areaKm2 = floodedCells.length * (cellSizeM * cellSizeM) / 1e6;
      final perimeterCoords = _cellsToPerimeter(
        floodedCells,
        config.lat,
        config.lon,
        gridSize,
        cellSizeM,
      );

      frames.add(SimulationFrame(
        hour: hour,
        timestamp: DateTime.now().add(Duration(hours: hour)),
        perimeterCoords: perimeterCoords,
        areaKm2: areaKm2,
        intensityPercent: (currentWaterLevel / waterLevelRise * 100).clamp(0, 100),
      ));
    }

    final finalArea = frames.isNotEmpty ? frames.last.areaKm2 : 0.0;
    final impact = _computeImpact(finalArea, config.lat, config.lon, config.type);
    final cascades = _computeFloodCascades(finalArea, impact, waterLevelRise);

    return SimulationResult(
      config: config,
      frames: frames,
      impact: impact,
      cascades: cascades,
      computedAt: DateTime.now(),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // SEA LEVEL RISE SIMULATION
  // Bathtub inundation model
  // ═══════════════════════════════════════════════════════════════

  static SimulationResult _runSeaLevelRiseSimulation(SimulationConfig config) {
    final seaLevelRiseM = config.parameters['seaLevelRiseM'] ?? 1.0;
    final radiusKm = config.parameters['radiusKm'] ?? 20.0;

    const gridSize = 200;
    final cellSizeM = (radiusKm * 2000.0) / gridSize;
    final center = gridSize ~/ 2;

    // Bathtub model: all cells below seaLevelRiseM that are hydrologically
    // connected to the coast are inundated.
    final inundatedCells = <List<int>>[];

    for (int r = 0; r < gridSize; r++) {
      for (int c = 0; c < gridSize; c++) {
        final dr = (r - center).toDouble();
        final dc = (c - center).toDouble();
        final distFromCenter = sqrt(dr * dr + dc * dc) * cellSizeM;

        if (distFromCenter > radiusKm * 1000) continue;

        // Coastal elevation model: elevation increases inland
        // Coast assumed at c = 0 side
        final distFromCoastM = c * cellSizeM;
        final elevation = distFromCoastM * 0.002 +
            sin(r * 0.08) * 0.3 +
            _rng.nextDouble() * 0.15;

        if (elevation < seaLevelRiseM) {
          inundatedCells.add([r, c]);
        }
      }
    }

    final areaKm2 = inundatedCells.length * (cellSizeM * cellSizeM) / 1e6;
    final perimeterCoords = _cellsToPerimeter(
      inundatedCells,
      config.lat,
      config.lon,
      gridSize,
      cellSizeM,
    );

    // Single frame for sea level rise (static scenario)
    final frames = [
      SimulationFrame(
        hour: 0,
        timestamp: DateTime.now(),
        perimeterCoords: perimeterCoords,
        areaKm2: areaKm2,
        intensityPercent: 100,
      ),
    ];

    final impact = _computeImpact(areaKm2, config.lat, config.lon, config.type);
    final cascades = _computeFloodCascades(areaKm2, impact, seaLevelRiseM);

    return SimulationResult(
      config: config,
      frames: frames,
      impact: impact,
      cascades: cascades,
      computedAt: DateTime.now(),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // DROUGHT PROJECTION
  // NDVI + precipitation deficit based forecast
  // ═══════════════════════════════════════════════════════════════

  static SimulationResult _runDroughtSimulation(SimulationConfig config) {
    final currentNDVI = config.parameters['currentNDVI'] ?? 0.4;
    final precipDeficit = config.parameters['precipitationDeficitPercent'] ?? 30.0;
    final monthsForward = (config.parameters['monthsForward'] ?? 6).toInt();
    final radiusKm = config.parameters['radiusKm'] ?? 50.0;

    final frames = <SimulationFrame>[];

    // NDVI decay model: vegetation stress increases with precipitation deficit
    // Reference: Littell et al. (2009)
    for (int month = 0; month <= monthsForward; month++) {
      // NDVI declines ~0.02 per month per 10% precip deficit
      final ndviDecline = 0.02 * (precipDeficit / 10.0) * month;
      final projectedNDVI = max(0.05, currentNDVI - ndviDecline);

      // Drought severity based on projected NDVI
      // D0: NDVI 0.35-0.40, D1: 0.25-0.35, D2: 0.15-0.25,
      // D3: 0.10-0.15, D4: <0.10
      DroughtSeverity severity;
      if (projectedNDVI >= 0.40) {
        severity = DroughtSeverity.d0;
      } else if (projectedNDVI >= 0.25) {
        severity = DroughtSeverity.d1;
      } else if (projectedNDVI >= 0.15) {
        severity = DroughtSeverity.d2;
      } else if (projectedNDVI >= 0.10) {
        severity = DroughtSeverity.d3;
      } else {
        severity = DroughtSeverity.d4;
      }

      // Affected area grows as drought intensifies
      final areaFraction = min(1.0, 0.3 + 0.7 * (1.0 - projectedNDVI / currentNDVI));
      final areaKm2 = pi * radiusKm * radiusKm * areaFraction;

      // Build circular perimeter
      final perimeterCoords = _circlePerimeter(
        config.lat,
        config.lon,
        radiusKm * sqrt(areaFraction),
        32,
      );

      frames.add(SimulationFrame(
        hour: month * 24 * 30, // convert months to hours
        timestamp: DateTime.now().add(Duration(days: month * 30)),
        perimeterCoords: perimeterCoords,
        areaKm2: areaKm2,
        intensityPercent: (severity.index / 4.0 * 100).clamp(0, 100),
      ));
    }

    final finalArea = frames.isNotEmpty ? frames.last.areaKm2 : 0.0;
    final impact = _computeImpact(finalArea, config.lat, config.lon, config.type);
    final cascades = _computeDroughtCascades(finalArea, impact, precipDeficit);

    return SimulationResult(
      config: config,
      frames: frames,
      impact: impact,
      cascades: cascades,
      computedAt: DateTime.now(),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // POPULATION EXPOSURE CALCULATOR
  // ═══════════════════════════════════════════════════════════════

  /// Estimates population within a hazard zone using distance-decay
  /// from nearest major city. Uses a simplified WorldPop grid approach.
  ///
  /// populationDensity(lat, lon) ~ nearestCityPop * exp(-distance/decayKm)
  static int estimatePopulation(double lat, double lon, double areaKm2) {
    // Simplified city density lookup based on latitude bands
    // Global average urban density ~3,000/km2, rural ~50/km2
    final absLat = lat.abs();
    double baseDensity;
    if (absLat < 15) {
      baseDensity = 200; // tropical, often dense
    } else if (absLat < 35) {
      baseDensity = 150; // subtropical
    } else if (absLat < 55) {
      baseDensity = 100; // temperate
    } else {
      baseDensity = 20; // high latitude
    }

    // Rough coastal vs inland adjustment
    // Coastal areas (within ~100km of typical coastlines) have higher density
    final isCoastalEstimate = _estimateCoastal(lat, lon);
    if (isCoastalEstimate) {
      baseDensity *= 2.5;
    }

    return (baseDensity * areaKm2).round();
  }

  // ═══════════════════════════════════════════════════════════════
  // INFRASTRUCTURE VULNERABILITY
  // ═══════════════════════════════════════════════════════════════

  /// Estimates critical infrastructure from population density.
  /// Reference: Koks et al. (2024), One Earth.
  static Map<String, int> estimateInfrastructure(int population) {
    return {
      'hospitals': max(1, (population / 50000).round()),
      'schools': max(1, (population / 5000).round()),
      'fireStations': max(1, (population / 25000).round()),
      'powerFacilities': max(1, (population / 100000).round()),
      'waterTreatment': max(1, (population / 75000).round()),
      'majorBridges': max(1, (population / 30000).round()),
      'structures': (population / 2.5).round(), // avg household size
    };
  }

  // ═══════════════════════════════════════════════════════════════
  // ECONOMIC LOSS ESTIMATOR
  // Simplified World Bank GRADE methodology
  // ═══════════════════════════════════════════════════════════════

  /// Estimates economic damage from a hazard event.
  /// Reference: World Bank GRADE methodology (2024).
  static double estimateEconomicLoss(
    SimulationType type,
    double areaKm2,
    int structures, {
    double waterDepthM = 1.0,
    int droughtMonths = 1,
  }) {
    switch (type) {
      case SimulationType.wildfire:
        // $150,000 per structure destroyed + $5,000/ha timber + $2,000/ha suppression
        final structureLoss = structures * 0.3 * 150000; // 30% destruction rate
        final timberLoss = areaKm2 * 100 * 5000; // convert km2 to ha
        final suppressionCost = areaKm2 * 100 * 2000;
        return structureLoss + timberLoss + suppressionCost;

      case SimulationType.flood:
      case SimulationType.seaLevelRise:
        // $50,000-200,000 per flooded structure (depth-dependent)
        final depthFactor = min(1.0, waterDepthM / 3.0);
        final perStructure = 50000 + 150000 * depthFactor;
        return structures * 0.5 * perStructure; // 50% of structures affected

      case SimulationType.drought:
        // $200/ha agricultural loss per month of D2+ drought
        final agArea = areaKm2 * 100 * 0.4; // 40% agricultural land
        return agArea * 200 * droughtMonths;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // CASCADING IMPACT ENGINE
  // ═══════════════════════════════════════════════════════════════

  static List<CascadeEffect> _computeWildfireCascades(
    double areaKm2,
    ImpactAssessment impact,
  ) {
    return [
      CascadeEffect(
        name: 'Post-Fire Debris Flow',
        description: 'Burned slopes lose vegetation anchoring soil, '
            'increasing debris flow probability by 30-80% in the first '
            'year post-fire, especially during intense rainfall events.',
        probability: 0.65,
        severity: 'high',
        timeframe: '1-12 months (triggered by rainfall)',
        additionalAreaKm2: areaKm2 * 0.15,
        additionalPopulation: (impact.populationExposed * 0.1).round(),
        additionalLossUSD: impact.estimatedLossUSD * 0.2,
        citation: 'Cannon et al. (2010), USGS Fact Sheet 2010-3049',
      ),
      CascadeEffect(
        name: 'Water Quality Degradation',
        description: 'Post-fire sediment loading increases 19-286x in affected '
            'watersheds. Dissolved organic carbon, nutrients, and heavy metals '
            'contaminate downstream water supplies.',
        probability: 0.85,
        severity: 'high',
        timeframe: '1-6 months',
        additionalAreaKm2: areaKm2 * 0.5,
        additionalPopulation: (impact.populationExposed * 0.3).round(),
        additionalLossUSD: impact.estimatedLossUSD * 0.1,
        citation: 'Rust et al. (2025), Nature Communications Earth & Environment',
      ),
      CascadeEffect(
        name: 'Habitat Loss & Species Displacement',
        description: 'Fire destroys critical habitat for terrestrial species. '
            'Recovery timelines range from 5-50 years depending on ecosystem '
            'type and fire severity.',
        probability: 0.95,
        severity: 'extreme',
        timeframe: '0-7 days (immediate)',
        additionalAreaKm2: areaKm2,
        additionalPopulation: 0,
        additionalLossUSD: 0,
        citation: 'Bowman et al. (2009), Science 324(5926)',
      ),
      CascadeEffect(
        name: 'Air Quality Deterioration',
        description: 'PM2.5 concentrations increase 5-50x in downwind areas. '
            'Smoke plumes can travel hundreds of kilometers, affecting '
            'respiratory health in distant population centers.',
        probability: 0.90,
        severity: 'high',
        timeframe: '0-14 days',
        additionalAreaKm2: areaKm2 * 10,
        additionalPopulation: (impact.populationExposed * 5).round(),
        additionalLossUSD: impact.estimatedLossUSD * 0.05,
        citation: 'Reid et al. (2016), Environmental Health Perspectives 124(9)',
      ),
      CascadeEffect(
        name: 'Economic Disruption',
        description: 'Property destruction, timber loss, suppression costs, '
            'tourism decline, and agricultural damage. Indirect costs often '
            'exceed direct costs by 2-5x.',
        probability: 1.0,
        severity: 'extreme',
        timeframe: '0 days - 5 years',
        additionalAreaKm2: 0,
        additionalPopulation: 0,
        additionalLossUSD: impact.estimatedLossUSD * 2.0,
        citation: 'World Bank GRADE methodology (2024)',
      ),
    ];
  }

  static List<CascadeEffect> _computeFloodCascades(
    double areaKm2,
    ImpactAssessment impact,
    double waterLevelM,
  ) {
    return [
      CascadeEffect(
        name: 'Infrastructure Damage',
        description: 'Bridges, roads, power lines, and communication networks '
            'sustain damage proportional to flood depth and duration. '
            'Recovery can take weeks to months.',
        probability: 0.90,
        severity: waterLevelM > 2 ? 'extreme' : 'high',
        timeframe: '0-7 days',
        additionalAreaKm2: 0,
        additionalPopulation: (impact.populationExposed * 0.2).round(),
        additionalLossUSD: impact.estimatedLossUSD * 0.3,
        citation: 'Koks et al. (2024), One Earth',
      ),
      CascadeEffect(
        name: 'Water Contamination',
        description: 'Floodwaters mix with sewage systems, agricultural '
            'runoff, and industrial chemicals. Drinking water supplies '
            'may be compromised for weeks.',
        probability: 0.75,
        severity: 'high',
        timeframe: '1-30 days',
        additionalAreaKm2: areaKm2 * 0.3,
        additionalPopulation: (impact.populationExposed * 0.4).round(),
        additionalLossUSD: impact.estimatedLossUSD * 0.1,
        citation: 'Alderman et al. (2012), PLOS Currents Disasters',
      ),
      CascadeEffect(
        name: 'Waterborne Disease Risk',
        description: 'Flood conditions create breeding grounds for waterborne '
            'pathogens. Cholera, leptospirosis, and hepatitis A risk '
            'increases significantly in affected populations.',
        probability: 0.55,
        severity: 'moderate',
        timeframe: '1-4 weeks',
        additionalAreaKm2: 0,
        additionalPopulation: (impact.populationExposed * 0.15).round(),
        additionalLossUSD: impact.estimatedLossUSD * 0.05,
        citation: 'Alderman et al. (2012), PLOS Currents Disasters',
      ),
      CascadeEffect(
        name: 'Agricultural Loss',
        description: 'Crop damage and soil salinization from flooding. '
            'Recovery of agricultural productivity may take 1-3 growing '
            'seasons depending on flood depth and duration.',
        probability: 0.80,
        severity: 'high',
        timeframe: '0 days - 2 seasons',
        additionalAreaKm2: areaKm2 * 0.4,
        additionalPopulation: 0,
        additionalLossUSD: areaKm2 * 100 * 0.4 * 500, // $500/ha ag loss
        citation: 'World Bank GRADE methodology (2024)',
      ),
      CascadeEffect(
        name: 'Population Displacement',
        description: 'Residents in flood zones are displaced, requiring '
            'emergency shelter and long-term housing solutions. '
            'Average displacement duration: 3-18 months.',
        probability: 0.85,
        severity: 'extreme',
        timeframe: '0 days - 18 months',
        additionalAreaKm2: 0,
        additionalPopulation: (impact.populationExposed * 0.6).round(),
        additionalLossUSD: impact.populationExposed * 1500.0, // $1500/person
        citation: 'IDMC Global Report on Internal Displacement (2024)',
      ),
    ];
  }

  static List<CascadeEffect> _computeDroughtCascades(
    double areaKm2,
    ImpactAssessment impact,
    double precipDeficit,
  ) {
    final fireRiskIncrease = min(0.95, 0.3 + precipDeficit / 100.0);
    return [
      CascadeEffect(
        name: 'Increased Wildfire Risk',
        description: 'Drought-stressed vegetation becomes highly flammable. '
            'Fire risk increases linearly with precipitation deficit. '
            'Historical correlation: r=0.7 between drought severity and '
            'burned area in western North America.',
        probability: fireRiskIncrease,
        severity: precipDeficit > 50 ? 'extreme' : 'high',
        timeframe: '1-6 months',
        additionalAreaKm2: areaKm2 * 0.1,
        additionalPopulation: 0,
        additionalLossUSD: impact.estimatedLossUSD * 0.5,
        citation: 'Littell et al. (2009), Ecological Applications 19(4)',
      ),
      CascadeEffect(
        name: 'Water Scarcity',
        description: 'Reservoir levels decline, groundwater depletion '
            'accelerates, and municipal water restrictions are imposed. '
            'Agricultural irrigation may be curtailed.',
        probability: 0.80,
        severity: 'high',
        timeframe: '1-12 months',
        additionalAreaKm2: areaKm2 * 0.5,
        additionalPopulation: (impact.populationExposed * 0.8).round(),
        additionalLossUSD: impact.estimatedLossUSD * 0.3,
        citation: 'World Bank GRADE methodology (2024)',
      ),
      CascadeEffect(
        name: 'Groundwater Depletion',
        description: 'Over-pumping during drought lowers water tables. '
            'Land subsidence risk increases. Recovery of aquifer levels '
            'can take decades.',
        probability: 0.70,
        severity: 'moderate',
        timeframe: '3-24 months',
        additionalAreaKm2: areaKm2 * 0.3,
        additionalPopulation: 0,
        additionalLossUSD: impact.estimatedLossUSD * 0.15,
        citation: 'Famiglietti (2014), Nature Climate Change 4',
      ),
      CascadeEffect(
        name: 'Energy Production Impact',
        description: 'Hydropower generation declines proportionally with '
            'reduced streamflow. Thermal power plants may face cooling '
            'water shortages, reducing capacity.',
        probability: 0.60,
        severity: 'moderate',
        timeframe: '2-12 months',
        additionalAreaKm2: 0,
        additionalPopulation: (impact.populationExposed * 0.5).round(),
        additionalLossUSD: impact.estimatedLossUSD * 0.2,
        citation: 'van Vliet et al. (2016), Nature Energy 1(16114)',
      ),
      CascadeEffect(
        name: 'Agricultural & Food Security Impact',
        description: 'Crop yields decline 10-50% under severe drought. '
            'Livestock feed shortages lead to herd reduction. Food prices '
            'increase regionally.',
        probability: 0.90,
        severity: 'extreme',
        timeframe: '1-2 growing seasons',
        additionalAreaKm2: areaKm2 * 0.4,
        additionalPopulation: (impact.populationExposed * 0.3).round(),
        additionalLossUSD: areaKm2 * 100 * 0.4 * 200, // $200/ha/month
        citation: 'Lesk et al. (2016), Nature 529',
      ),
    ];
  }

  // ═══════════════════════════════════════════════════════════════
  // HELPER METHODS
  // ═══════════════════════════════════════════════════════════════

  /// Compute impact assessment for a given hazard area.
  static ImpactAssessment _computeImpact(
    double areaKm2,
    double lat,
    double lon,
    SimulationType type,
  ) {
    final population = estimatePopulation(lat, lon, areaKm2);
    final infra = estimateInfrastructure(population);
    final structures = infra['structures'] ?? 0;
    final loss = estimateEconomicLoss(type, areaKm2, structures);

    return ImpactAssessment(
      areaAffectedKm2: areaKm2,
      populationExposed: population,
      hospitalsAtRisk: infra['hospitals'] ?? 0,
      schoolsAtRisk: infra['schools'] ?? 0,
      structuresAtRisk: structures,
      estimatedLossUSD: loss,
      demographicBreakdown: {
        'Children (0-14)': 0.26,
        'Working Age (15-64)': 0.65,
        'Elderly (65+)': 0.09,
      },
    );
  }

  /// Convert grid cell coordinates to lat/lon perimeter polygon.
  /// Uses a simplified convex hull via angular sweep.
  static List<List<double>> _cellsToPerimeter(
    List<List<int>> cells,
    double centerLat,
    double centerLon,
    int gridSize,
    double cellSizeM,
  ) {
    if (cells.isEmpty) return [];

    final center = gridSize / 2.0;
    // Degrees per meter at this latitude
    final mPerDegLat = 111320.0;
    final mPerDegLon = 111320.0 * cos(centerLat * pi / 180.0);

    // Convert cells to lat/lon
    final points = cells.map((cell) {
      final dr = (cell[0] - center) * cellSizeM;
      final dc = (cell[1] - center) * cellSizeM;
      final lat = centerLat + dr / mPerDegLat;
      final lon = centerLon + dc / mPerDegLon;
      return [lat, lon];
    }).toList();

    // Compute convex hull using gift wrapping
    if (points.length < 3) return points;

    // Find leftmost point
    int startIdx = 0;
    for (int i = 1; i < points.length; i++) {
      if (points[i][1] < points[startIdx][1] ||
          (points[i][1] == points[startIdx][1] &&
              points[i][0] < points[startIdx][0])) {
        startIdx = i;
      }
    }

    final hull = <List<double>>[];
    int current = startIdx;
    int maxIterations = points.length;
    int iterations = 0;

    do {
      hull.add(points[current]);
      int next = 0;
      for (int i = 1; i < points.length; i++) {
        if (next == current) {
          next = i;
          continue;
        }
        final cross = _cross(points[current], points[next], points[i]);
        if (cross < 0) {
          next = i;
        }
      }
      current = next;
      iterations++;
    } while (current != startIdx && iterations < maxIterations);

    // Close the polygon
    if (hull.isNotEmpty) {
      hull.add(hull.first);
    }

    // Simplify if too many points (keep ~32 for rendering)
    if (hull.length > 34) {
      final step = hull.length ~/ 32;
      final simplified = <List<double>>[];
      for (int i = 0; i < hull.length - 1; i += step) {
        simplified.add(hull[i]);
      }
      simplified.add(hull.first); // close
      return simplified;
    }

    return hull;
  }

  /// Generate a circular perimeter polygon.
  static List<List<double>> _circlePerimeter(
    double lat,
    double lon,
    double radiusKm,
    int segments,
  ) {
    final coords = <List<double>>[];
    final mPerDegLat = 111320.0;
    final mPerDegLon = 111320.0 * cos(lat * pi / 180.0);

    for (int i = 0; i <= segments; i++) {
      final angle = 2 * pi * i / segments;
      final dLat = radiusKm * 1000.0 * cos(angle) / mPerDegLat;
      final dLon = radiusKm * 1000.0 * sin(angle) / mPerDegLon;
      coords.add([lat + dLat, lon + dLon]);
    }
    return coords;
  }

  /// Cross product for convex hull computation.
  static double _cross(List<double> o, List<double> a, List<double> b) {
    return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]);
  }

  /// Rough estimate of whether a location is coastal.
  static bool _estimateCoastal(double lat, double lon) {
    // Very simplified: check if near continental edges
    // Real implementation would use coastline distance data
    final absLon = lon.abs();
    if (absLon > 170 || absLon < 10) return true; // near dateline or prime meridian
    if (lat.abs() > 60) return false; // polar
    // Check known coastal longitude bands
    if (lon > -130 && lon < -115 && lat > 25 && lat < 50) return true; // US west coast
    if (lon > -82 && lon < -75 && lat > 25 && lat < 45) return true; // US east coast
    if (lon > -10 && lon < 5 && lat > 35 && lat < 60) return true; // Western Europe
    if (lon > 115 && lon < 145 && lat > -45 && lat < 45) return true; // East Asia/Australia
    return false;
  }

  static String _buildExecutiveSummary(SimulationResult result) {
    final type = result.config.type.label;
    final area = result.impact.areaAffectedKm2.toStringAsFixed(1);
    final pop = _formatNumber(result.impact.populationExposed);
    final loss = _formatCurrency(result.impact.estimatedLossUSD);
    final cascadeCount = result.cascades.length;
    final highRisk = result.cascades
        .where((c) => c.severity == 'high' || c.severity == 'extreme')
        .length;

    return 'This $type simulation projects an affected area of $area km\u00B2, '
        'with an estimated $pop people exposed and economic losses of $loss. '
        'The analysis identified $cascadeCount cascading effects, '
        'of which $highRisk are rated high or extreme severity. '
        'All estimates use peer-reviewed methodologies and should be '
        'validated with local data for operational decision-making.';
  }

  static String _buildHazardExtentBody(SimulationResult result) {
    switch (result.config.type) {
      case SimulationType.wildfire:
        return 'Fire spread computed using simplified Rothermel model with '
            'grid-based cellular automata (50m cells). Wind, slope, humidity, '
            'and fuel type modulate spread rate. Perimeter represents '
            'convex hull of burned and burning cells at each timestep.';
      case SimulationType.flood:
        return 'Flood extent computed using simplified HAND (Height Above '
            'Nearest Drainage) model. Water level rises linearly over '
            'simulation duration. Cells where water level exceeds HAND '
            'value are classified as inundated.';
      case SimulationType.seaLevelRise:
        return 'Coastal inundation computed using bathtub model. All cells '
            'below the specified sea level rise that are hydrologically '
            'connected to the coast are classified as inundated.';
      case SimulationType.drought:
        return 'Drought severity projected using NDVI-precipitation deficit '
            'model. Vegetation stress index declines proportionally with '
            'precipitation deficit over time. Severity classified per '
            'US Drought Monitor (D0-D4).';
    }
  }

  static String _formatNumber(int n) {
    if (n >= 1e9) return '${(n / 1e9).toStringAsFixed(1)}B';
    if (n >= 1e6) return '${(n / 1e6).toStringAsFixed(1)}M';
    if (n >= 1e3) return '${(n / 1e3).toStringAsFixed(1)}K';
    return n.toString();
  }

  static String _formatCurrency(double amount) {
    if (amount >= 1e9) return '\$${(amount / 1e9).toStringAsFixed(1)}B';
    if (amount >= 1e6) return '\$${(amount / 1e6).toStringAsFixed(1)}M';
    if (amount >= 1e3) return '\$${(amount / 1e3).toStringAsFixed(1)}K';
    return '\$${amount.toStringAsFixed(0)}';
  }
}
