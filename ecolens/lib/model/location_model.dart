import 'package:fl_chart/fl_chart.dart';

/// 🌍 Intelligence Node - Enhanced for NGOs/Governments/Organizations
/// Represents a single AI-generated environmental intelligence point
class IntelligenceNode {
  // ═══════════════════════════════════════════════════════════════
  // CORE IDENTIFIERS
  // ═══════════════════════════════════════════════════════════════
  final String id;
  final String type;
  final String headline;
  final String backgroundInfo;

  // ═══════════════════════════════════════════════════════════════
  // GEO
  // ═══════════════════════════════════════════════════════════════
  final double lat;
  final double lng;
  final double hectares;

  // ═══════════════════════════════════════════════════════════════
  // GEOGRAPHIC CLASSIFICATION
  // ═══════════════════════════════════════════════════════════════
  final String continent;
  final String country;
  final String region;
  final String provinceState;

  // ═══════════════════════════════════════════════════════════════
  // RISK & AI
  // ═══════════════════════════════════════════════════════════════
  final double riskScore;

  /// True only when the source actually supplied a risk score. When false,
  /// [riskScore] is 0 as a placeholder and MUST NOT be displayed — a
  /// plausible-looking default rendered as a measurement is a fabrication.
  final bool riskScored;
  final List<int> aiForecast;

  // ═══════════════════════════════════════════════════════════════
  // LEGAL STATUS (Critical for NGOs/Governments)
  // ═══════════════════════════════════════════════════════════════
  final LegalStatus legalStatus;

  // ═══════════════════════════════════════════════════════════════
  // FORENSIC DATA
  // ═══════════════════════════════════════════════════════════════
  final Map<String, dynamic> causeData;

  // ═══════════════════════════════════════════════════════════════
  // FIRE DATA (NASA FIRMS)
  // ═══════════════════════════════════════════════════════════════
  final FireData fireData;

  // ═══════════════════════════════════════════════════════════════
  // CARBON DATA (Climate Policy)
  // ═══════════════════════════════════════════════════════════════
  final CarbonData carbonData;

  // ═══════════════════════════════════════════════════════════════
  // WATER RESOURCES
  // ═══════════════════════════════════════════════════════════════
  final WaterResources waterResources;

  // ═══════════════════════════════════════════════════════════════
  // SPECIES (FAUNA + FLORA)
  // ═══════════════════════════════════════════════════════════════
  final List<SpeciesInfo> faunaAtRisk;
  final List<SpeciesInfo> floraAtRisk;
  final List<SpeciesInfo>
  faunaThrive; // Species that will thrive in restoration
  final List<SpeciesInfo> floraThrive; // Plants ideal for restoration

  // ═══════════════════════════════════════════════════════════════
  // HUMAN IMPACTS
  // ═══════════════════════════════════════════════════════════════
  final int population;
  final int settlementsCount;
  final double nearestSettlementKm;
  final String displacementRisk;
  final List<String> livelihoodsAtRisk;
  final List<String> healthImpacts;

  // ═══════════════════════════════════════════════════════════════
  // ECONOMIC IMPACTS
  // ═══════════════════════════════════════════════════════════════
  final EconomicImpact economicImpacts;

  // ═══════════════════════════════════════════════════════════════
  // LAND FEATURES
  // ═══════════════════════════════════════════════════════════════
  final List<LandFeature> landFeatures;

  // ═══════════════════════════════════════════════════════════════
  // REFORESTATION
  // ═══════════════════════════════════════════════════════════════
  final ReforestZone reforestZone;

  // ═══════════════════════════════════════════════════════════════
  // URGENCY (For Decision Makers)
  // ═══════════════════════════════════════════════════════════════
  final Urgency urgency;

  // ═══════════════════════════════════════════════════════════════
  // RECOMMENDED ACTIONS
  // ═══════════════════════════════════════════════════════════════
  final List<RecommendedAction> recommendedActions;

  // ═══════════════════════════════════════════════════════════════
  // TRENDS
  // ═══════════════════════════════════════════════════════════════
  final String trendDirection;
  final double trendChangePercent;
  final double forecast2026;

  // ═══════════════════════════════════════════════════════════════
  // HISTORY
  // ═══════════════════════════════════════════════════════════════
  final Map<String, double> yearlyHistory;

  // ═══════════════════════════════════════════════════════════════
  // DATA SOURCES
  // ═══════════════════════════════════════════════════════════════
  final List<DataSource> dataSources;

  // ═══════════════════════════════════════════════════════════════
  // AGENT ANALYSIS DATA (NEW)
  // ═══════════════════════════════════════════════════════════════
  final Map<String, dynamic> soilAnalysis; // Layer 9: Soil Analysis
  final Map<String, dynamic> terrainAnalysis; // Layer 10: Terrain Analysis
  final Map<String, dynamic> hydrologyAnalysis; // Layer 11: Hydrology Analysis
  final Map<String, dynamic>
  historicalAnalysis; // Layer 12: Historical Analysis
  final Map<String, dynamic> recoveryPotential; // Recovery potential assessment
  final Map<String, dynamic> comprehensiveAnalysis; // Layer 13: AI Synthesis
  final Map<String, dynamic>
  sentinelVerification; // Layer 14: Sentinel Verification
  final Map<String, dynamic> gisAnalysis; // Layer 15: GIS Analysis
  final Map<String, dynamic> riskPrediction; // Layer 16: Risk Prediction

  // ═══════════════════════════════════════════════════════════════
  // QUICK SUMMARY FIELDS (for carousel cards)
  // ═══════════════════════════════════════════════════════════════
  final String soilType; // e.g., "Clay Loam", "Sandy", "Peat"
  final double soilPH; // Soil pH value
  final String soilFertility; // e.g., "High", "Medium", "Low"
  final double terrainSlope; // Average slope in degrees
  final String terrainDifficulty; // e.g., "Easy", "Moderate", "Difficult"
  final double terrainElevation; // Average elevation in meters
  final String waterAccess; // e.g., "High", "Medium", "Low", "Very High"
  final String waterStress; // e.g., "Low", "Medium", "High"
  final double recoveryScore; // 0-100 score for recovery potential
  final String successProbability; // e.g., "High", "Medium", "Low"

  const IntelligenceNode({
    this.id = '',
    required this.type,
    required this.headline,
    this.backgroundInfo = '',
    required this.lat,
    required this.lng,
    this.hectares = 0.0,
    this.continent = '',
    this.country = '',
    this.region = '',
    this.provinceState = '',
    required this.riskScore,
    this.riskScored = false,
    this.aiForecast = const [],
    this.legalStatus = const LegalStatus(),
    required this.causeData,
    this.fireData = const FireData(),
    this.carbonData = const CarbonData(),
    this.waterResources = const WaterResources(),
    this.faunaAtRisk = const [],
    this.floraAtRisk = const [],
    this.faunaThrive = const [],
    this.floraThrive = const [],
    this.population = 0,
    this.settlementsCount = 0,
    this.nearestSettlementKm = 0.0,
    this.displacementRisk = 'LOW',
    this.livelihoodsAtRisk = const [],
    this.healthImpacts = const [],
    this.economicImpacts = const EconomicImpact(),
    this.landFeatures = const [],
    this.reforestZone = const ReforestZone(),
    this.urgency = const Urgency(),
    this.recommendedActions = const [],
    this.trendDirection = 'STABLE',
    this.trendChangePercent = 0.0,
    this.forecast2026 = 0.0,
    this.yearlyHistory = const {},
    this.dataSources = const [],
    this.soilAnalysis = const {},
    this.terrainAnalysis = const {},
    this.hydrologyAnalysis = const {},
    this.historicalAnalysis = const {},
    this.recoveryPotential = const {},
    this.comprehensiveAnalysis = const {},
    this.sentinelVerification = const {},
    this.gisAnalysis = const {},
    this.riskPrediction = const {},
    this.soilType = 'Unknown',
    this.soilPH = 0.0,
    this.soilFertility = 'Unknown',
    this.terrainSlope = 0.0,
    this.terrainDifficulty = 'Unknown',
    this.terrainElevation = 0.0,
    this.waterAccess = 'Unknown',
    this.waterStress = 'Unknown',
    this.recoveryScore = -1.0, // -1 indicates "no data available"
    this.successProbability = 'Unknown',
  });

  // Combined species list for backward compatibility
  List<String> get speciesAtRisk => [
    ...faunaAtRisk.map((s) => s.commonName),
    ...floraAtRisk.map((s) => s.commonName),
  ];

  // Data availability helpers
  bool get hasRecoveryData => recoveryScore >= 0;
  bool get hasPopulationData => population > 0;
  bool get hasSettlementsData => settlementsCount > 0;
  bool get hasReforestCostData => reforestZone.costEstimateUsd > 0;
  bool get hasSuitabilityData => reforestZone.suitabilityScore > 0;

  // ═══════════════════════════════════════════════════════════════
  // FACTORY
  // ═══════════════════════════════════════════════════════════════
  factory IntelligenceNode.fromMap(Map<String, dynamic> map, String docId) {
    // Extract nested analysis sections for fallback data
    final biodiversityAnalysis = map['biodiversity_analysis'] ?? {};
    final gisAnalysis = map['gis_analysis'] ?? {};
    final historicalAnalysis = map['historical_analysis'] ?? {};
    final terrainAnalysis = map['terrain_analysis'] ?? {};
    final soilAnalysis = map['soil_analysis'] ?? {};
    final hydrologyAnalysis = map['hydrology_analysis'] ?? {};
    final overlayAnalysis = gisAnalysis['overlay_analysis'] ?? {};
    final populationImpact = overlayAnalysis['population_impact'] ?? {};

    // Parse history - check multiple possible locations
    final Map<String, double> parsedHistory = {};
    // Try root-level 'history' map first
    final rawHistory = map['history'];
    if (rawHistory is Map) {
      rawHistory.forEach((key, value) {
        if (value is num) parsedHistory[key.toString()] = value.toDouble();
      });
    }
    // If empty, try historical_analysis.timeline array
    if (parsedHistory.isEmpty) {
      final timeline = historicalAnalysis['timeline'];
      if (timeline is List) {
        for (final entry in timeline) {
          if (entry is Map && entry['year'] != null && entry['loss_ha'] != null) {
            parsedHistory[entry['year'].toString()] = (entry['loss_ha'] as num).toDouble();
          }
        }
      }
    }

    // Parse fauna - check root level first, then biodiversity_analysis
    final List<SpeciesInfo> fauna = [];
    var rawFauna = map['fauna_at_risk'];
    if (rawFauna == null || (rawFauna is List && rawFauna.isEmpty)) {
      rawFauna = biodiversityAnalysis['fauna_at_risk'];
    }
    if (rawFauna is List) {
      for (final s in rawFauna) {
        if (s is Map) fauna.add(SpeciesInfo.fromMap(s));
      }
    }

    // Parse flora - check root level first, then biodiversity_analysis
    final List<SpeciesInfo> flora = [];
    var rawFlora = map['flora_at_risk'];
    if (rawFlora == null || (rawFlora is List && rawFlora.isEmpty)) {
      rawFlora = biodiversityAnalysis['flora_at_risk'];
    }
    if (rawFlora is List) {
      for (final s in rawFlora) {
        if (s is Map) flora.add(SpeciesInfo.fromMap(s));
      }
    }

    // Parse fauna that will thrive
    final List<SpeciesInfo> faunaThrive = [];
    var rawFaunaThrive = map['fauna_thrive'];
    if (rawFaunaThrive == null || (rawFaunaThrive is List && rawFaunaThrive.isEmpty)) {
      rawFaunaThrive = biodiversityAnalysis['fauna_thrive'];
    }
    if (rawFaunaThrive is List) {
      for (final s in rawFaunaThrive) {
        if (s is Map) faunaThrive.add(SpeciesInfo.fromMap(s));
      }
    }

    // Parse flora that will thrive
    final List<SpeciesInfo> floraThrive = [];
    var rawFloraThrive = map['flora_thrive'];
    if (rawFloraThrive == null || (rawFloraThrive is List && rawFloraThrive.isEmpty)) {
      rawFloraThrive = biodiversityAnalysis['flora_thrive'];
    }
    if (rawFloraThrive is List) {
      for (final s in rawFloraThrive) {
        if (s is Map) floraThrive.add(SpeciesInfo.fromMap(s));
      }
    }

    // Parse land features
    final List<LandFeature> features = [];
    final rawFeatures = map['land_features'];
    if (rawFeatures is List) {
      for (final f in rawFeatures) {
        if (f is Map) features.add(LandFeature.fromMap(f));
      }
    }

    // Parse recommended actions
    final List<RecommendedAction> actions = [];
    final rawActions = map['recommended_actions'];
    if (rawActions is List) {
      for (final a in rawActions) {
        if (a is Map) actions.add(RecommendedAction.fromMap(a));
      }
    }

    // Parse data sources
    final List<DataSource> sources = [];
    final rawSources = map['data_sources'];
    if (rawSources is List) {
      for (final s in rawSources) {
        if (s is Map) sources.add(DataSource.fromMap(s));
      }
    }

    // Parse human impacts
    final humanImpacts = map['human_impacts'] ?? {};

    // Parse trends
    final trends = map['trends'] ?? {};

    // Parse Geo & Scale
    final double hectares = (map['hectares'] ?? 0).toDouble();
    // No default score. An unscored hotspot is unscored; it is not a 70.
    final rawRiskScore = map['riskScore'] ?? map['risk_score'];
    final bool riskScored = rawRiskScore is num;
    final double riskScore = riskScored ? rawRiskScore.toDouble() : 0.0;
    final carbonData = CarbonData.fromMap(map['carbon_data'] ?? {});

    // Economic impacts come from the backend or not at all. The previous
    // fallback multiplied hectares by per-hectare constants and rendered the
    // product as a currency breakdown; that is an invented figure, so the
    // section is left empty and the UI omits it instead.
    // Handle both old (economic_analysis) and new (economic_impacts) names.
    final EconomicImpact econData = EconomicImpact.fromMap(
      map['economic_impacts'] ?? map['economic_analysis'] ?? {},
    );

    return IntelligenceNode(
      id: docId,
      type: map['type'] ?? 'Environmental Alert',
      headline: map['headline'] ?? 'Environmental Anomaly Detected',
      backgroundInfo: map['background_info'] ?? '',

      // Geo
      lat: (map['lat'] ?? 0).toDouble(),
      lng: (map['lng'] ?? 0).toDouble(),
      hectares: hectares,

      // Geographic classification
      continent: map['continent'] ?? '',
      country: map['country'] ?? '',
      region: map['region'] ?? '',
      provinceState: map['province_state'] ?? '',

      // Risk
      riskScore: riskScore,
      riskScored: riskScored,

      // Legal status
      legalStatus: LegalStatus.fromMap(map['legal_status'] ?? {}),

      // Forensics
      causeData: Map<String, dynamic>.from(
        map['cause_data'] ?? {'primary_driver': 'Unknown'},
      ),

      // Fire data
      fireData: FireData.fromMap(map['fire_data'] ?? {}),

      // Carbon data
      carbonData: carbonData,

      // Water resources
      waterResources: WaterResources.fromMap(map['water_resources'] ?? {}),

      // Species
      faunaAtRisk: fauna,
      floraAtRisk: flora,
      faunaThrive: faunaThrive,
      floraThrive: floraThrive,

      // Human impacts - check multiple data paths
      // 1. human_impacts.population_affected
      // 2. human_impacts.affected_population.total
      // 3. gis_analysis.overlay_analysis.population_impact.estimated_population_in_buffer
      population: (humanImpacts['population_affected'] ??
          humanImpacts['affected_population']?['total'] ??
          populationImpact['estimated_population_in_buffer'] ??
          map['human_impacts']?['affected_population']?['total'] ?? 0).toInt(),
      settlementsCount: (humanImpacts['settlements_count'] ??
          gisAnalysis['proximity_analysis']?['settlement_count'] ?? 0).toInt(),
      nearestSettlementKm: (humanImpacts['nearest_settlement_km'] ??
          gisAnalysis['proximity_analysis']?['settlement_distance_km'] ?? 0).toDouble(),
      displacementRisk: humanImpacts['displacement_risk'] ?? 'Unknown',
      livelihoodsAtRisk: _parseStringList(humanImpacts['livelihoods_at_risk']),
      healthImpacts: _parseStringList(humanImpacts['health_impacts']),

      // Economic
      economicImpacts: econData,

      // Land features
      landFeatures: features,

      // Reforestation
      reforestZone: ReforestZone.fromMap(map['reforest_plan'] ?? {}),

      // Urgency
      urgency: Urgency.fromMap(map['urgency'] ?? {}),

      // Recommended actions
      recommendedActions: actions,

      // Trends
      trendDirection: trends['direction'] ?? 'STABLE',
      trendChangePercent: (trends['change_percent'] ?? 0).toDouble(),
      forecast2026: (trends['forecast_2026'] ?? 0).toDouble(),

      // History - only use real data, empty if unavailable
      // UI should show "Data unavailable" when history is empty
      yearlyHistory: parsedHistory,
      // Data sources
      dataSources: sources,

      // Agent Analysis Data (NEW - Layer 9-16)
      soilAnalysis: map['soil_analysis'] is Map
          ? Map<String, dynamic>.from(map['soil_analysis'] as Map)
          : {},
      terrainAnalysis: map['terrain_analysis'] is Map
          ? Map<String, dynamic>.from(map['terrain_analysis'] as Map)
          : {},
      hydrologyAnalysis: map['hydrology_analysis'] is Map
          ? Map<String, dynamic>.from(map['hydrology_analysis'] as Map)
          : {},
      historicalAnalysis: map['historical_analysis'] is Map
          ? Map<String, dynamic>.from(map['historical_analysis'] as Map)
          : {},
      recoveryPotential: map['recovery_potential'] is Map
          ? Map<String, dynamic>.from(map['recovery_potential'] as Map)
          : {},
      comprehensiveAnalysis: map['comprehensive_analysis'] is Map
          ? Map<String, dynamic>.from(map['comprehensive_analysis'] as Map)
          : {},
      sentinelVerification: map['sentinel_verification'] is Map
          ? Map<String, dynamic>.from(map['sentinel_verification'] as Map)
          : {},
      gisAnalysis: map['gis_analysis'] is Map
          ? Map<String, dynamic>.from(map['gis_analysis'] as Map)
          : {},
      riskPrediction: map['risk_prediction'] is Map
          ? Map<String, dynamic>.from(map['risk_prediction'] as Map)
          : {},

      // Quick Summary Fields - check root level first, then nested analysis sections
      soilType: map['soil_type']?.toString() ??
          soilAnalysis['soil_texture']?['class']?.toString() ?? 'Unknown',
      soilPH: (map['soil_ph'] ??
          soilAnalysis['ph']?['value'] ?? 0).toDouble(),
      soilFertility: map['soil_fertility']?.toString() ??
          soilAnalysis['fertility']?['level']?.toString() ?? 'Unknown',
      terrainSlope: (map['terrain_slope'] ??
          terrainAnalysis['slope']?['mean_degrees'] ?? 0).toDouble(),
      terrainDifficulty: map['terrain_difficulty']?.toString() ??
          terrainAnalysis['suitability']?['difficulty']?.toString() ?? 'Unknown',
      terrainElevation: (map['terrain_elevation'] ??
          terrainAnalysis['elevation']?['mean_m'] ?? 0).toDouble(),
      waterAccess: map['water_access']?.toString() ??
          hydrologyAnalysis['water_accessibility']?['rating']?.toString() ?? 'Unknown',
      waterStress: map['water_stress']?.toString() ??
          hydrologyAnalysis['water_stress']?['baseline_stress']?.toString() ?? 'Unknown',
      recoveryScore: (map['recovery_score'] ??
          map['recovery_potential']?['score'] ?? -1).toDouble(), // -1 if no data
      successProbability: map['success_probability']?.toString() ??
          map['comprehensive_analysis']?['success_probability']?.toString() ?? 'Unknown',
    );
  }

  static List<String> _parseStringList(dynamic raw) {
    if (raw is List) return raw.map((e) => e.toString()).toList();
    return [];
  }
}

// ═══════════════════════════════════════════════════════════════
// LEGAL STATUS
// ═══════════════════════════════════════════════════════════════
class LegalStatus {
  final bool protectedArea;
  final String protectedAreaName;
  final bool indigenousTerritory;
  final String indigenousCommunityName;
  final String legalDesignation;
  final bool illegalActivitySuspected;
  final String enforcementJurisdiction;

  const LegalStatus({
    this.protectedArea = false,
    this.protectedAreaName = '',
    this.indigenousTerritory = false,
    this.indigenousCommunityName = '',
    this.legalDesignation = '',
    this.illegalActivitySuspected = false,
    this.enforcementJurisdiction = '',
  });

  factory LegalStatus.fromMap(Map<dynamic, dynamic> map) {
    return LegalStatus(
      protectedArea: map['protected_area'] == true,
      protectedAreaName: map['protected_area_name']?.toString() ?? '',
      indigenousTerritory: map['indigenous_territory'] == true,
      indigenousCommunityName:
          map['indigenous_community_name']?.toString() ?? '',
      legalDesignation: map['legal_designation']?.toString() ?? '',
      illegalActivitySuspected: map['illegal_activity_suspected'] == true,
      enforcementJurisdiction:
          map['enforcement_jurisdiction']?.toString() ?? '',
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// FIRE DATA (NASA FIRMS)
// ═══════════════════════════════════════════════════════════════
class FireData {
  final int activeFires;
  final double fireRadiativePower;
  final double burnAreaHa;
  final String fireRiskLevel;
  final String lastFireDate;

  const FireData({
    this.activeFires = 0,
    this.fireRadiativePower = 0,
    this.burnAreaHa = 0,
    this.fireRiskLevel = 'LOW',
    this.lastFireDate = '',
  });

  factory FireData.fromMap(Map<dynamic, dynamic> map) {
    return FireData(
      activeFires: (map['active_fires'] ?? 0).toInt(),
      fireRadiativePower: (map['fire_radiative_power'] ?? 0).toDouble(),
      burnAreaHa: (map['burn_area_ha'] ?? 0).toDouble(),
      fireRiskLevel: map['fire_risk_level']?.toString() ?? 'LOW',
      lastFireDate: map['last_fire_date']?.toString() ?? '',
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// CARBON DATA
// ═══════════════════════════════════════════════════════════════
class CarbonData {
  final double aboveGroundBiomassTonnes;
  final double carbonStockTonnes;
  final double annualEmissionsTonnes;
  final double carbonDensityPerHa;
  final double sequestrationPotentialTonnes;

  const CarbonData({
    this.aboveGroundBiomassTonnes = 0,
    this.carbonStockTonnes = 0,
    this.annualEmissionsTonnes = 0,
    this.carbonDensityPerHa = 0,
    this.sequestrationPotentialTonnes = 0,
  });

  factory CarbonData.fromMap(Map<dynamic, dynamic> map) {
    return CarbonData(
      aboveGroundBiomassTonnes: (map['above_ground_biomass_tonnes'] ?? 0)
          .toDouble(),
      carbonStockTonnes: (map['carbon_stock_tonnes'] ?? 0).toDouble(),
      annualEmissionsTonnes: (map['annual_emissions_tonnes'] ?? 0).toDouble(),
      carbonDensityPerHa: (map['carbon_density_per_ha'] ?? 0).toDouble(),
      sequestrationPotentialTonnes: (map['sequestration_potential_tonnes'] ?? 0)
          .toDouble(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// WATER RESOURCES
// ═══════════════════════════════════════════════════════════════
class WaterResources {
  final String watershedName;
  final List<String> riversAffected;
  final int waterSupplyPopulation;
  final String floodRiskIncrease;
  final String aquiferImpact;

  const WaterResources({
    this.watershedName = '',
    this.riversAffected = const [],
    this.waterSupplyPopulation = 0,
    this.floodRiskIncrease = 'LOW',
    this.aquiferImpact = '',
  });

  factory WaterResources.fromMap(Map<dynamic, dynamic> map) {
    return WaterResources(
      watershedName: map['watershed_name']?.toString() ?? '',
      riversAffected:
          (map['rivers_affected'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      waterSupplyPopulation: (map['water_supply_population'] ?? 0).toInt(),
      floodRiskIncrease: map['flood_risk_increase']?.toString() ?? 'LOW',
      aquiferImpact: map['aquifer_impact']?.toString() ?? '',
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// SPECIES INFO
// ═══════════════════════════════════════════════════════════════
class SpeciesInfo {
  final String commonName;
  final String scientificName;
  final String status;
  final int populationEstimate;
  final bool endemic;
  final double locationLat;
  final double locationLng;

  const SpeciesInfo({
    required this.commonName,
    this.scientificName = '',
    this.status = 'Unknown',
    this.populationEstimate = 0,
    this.endemic = false,
    this.locationLat = 0,
    this.locationLng = 0,
  });

  factory SpeciesInfo.fromMap(Map<dynamic, dynamic> map) {
    return SpeciesInfo(
      commonName:
          map['common_name']?.toString() ??
          map['name']?.toString() ??
          'Unknown',
      scientificName: map['scientific_name']?.toString() ?? '',
      status:
          map['status']?.toString() ?? // BiodiversityAgent uses 'status'
          map['iucn_status']?.toString() ??
          map['conservation_status']?.toString() ??
          map['risk_level']?.toString() ??
          map['threat_level']?.toString() ?? // Also check threat_level
          'Unknown',
      populationEstimate: (map['population_estimate'] ?? 0).toInt(),
      endemic: map['endemic'] == true,
      locationLat: (map['location_lat'] ?? 0).toDouble(),
      locationLng: (map['location_lng'] ?? 0).toDouble(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// ECONOMIC IMPACT
// ═══════════════════════════════════════════════════════════════
class EconomicImpact {
  final int shortTermGainUsd;
  final String shortTermSource;
  final int longTermLossUsd;
  final String lossBreakdown;
  final String localCommunityImpact;
  final List<String> industriesAffected;

  const EconomicImpact({
    this.shortTermGainUsd = 0,
    this.shortTermSource = '',
    this.longTermLossUsd = 0,
    this.lossBreakdown = '',
    this.localCommunityImpact = '',
    this.industriesAffected = const [],
  });

  factory EconomicImpact.fromMap(Map<dynamic, dynamic> map) {
    return EconomicImpact(
      shortTermGainUsd: (map['short_term_gain_usd'] ?? 0).toInt(),
      shortTermSource: map['short_term_source']?.toString() ?? '',
      longTermLossUsd: (map['long_term_loss_usd'] ?? 0).toInt(),
      lossBreakdown: map['loss_breakdown']?.toString() ?? '',
      localCommunityImpact: map['local_community_impact']?.toString() ?? '',
      industriesAffected:
          (map['industries_affected'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }
}

// Old Accessors for backward compatibility if needed
extension EconomicCompat on EconomicImpact {
  int get totalUsd => longTermLossUsd;
}

// ═══════════════════════════════════════════════════════════════
// LAND FEATURE
// ═══════════════════════════════════════════════════════════════
class LandFeature {
  final String name;
  final String type;
  final String impactDescription;
  final double lat;
  final double lng;

  const LandFeature({
    required this.name,
    required this.type,
    this.impactDescription = '',
    this.lat = 0,
    this.lng = 0,
  });

  factory LandFeature.fromMap(Map<dynamic, dynamic> map) {
    return LandFeature(
      name: map['name']?.toString() ?? 'Unknown',
      type: map['type']?.toString() ?? 'unknown',
      impactDescription: map['impact_description']?.toString() ?? '',
      lat: (map['lat'] ?? 0).toDouble(),
      lng: (map['lng'] ?? 0).toDouble(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// REFORESTATION ZONE
// ═══════════════════════════════════════════════════════════════
class ReforestZone {
  final int suitabilityScore;
  final int treesRequired;
  final int costEstimateUsd;
  final int timeToRecoveryYears;
  final int co2SequestrationTonnes;
  final List<String> nativeSpeciesRecommended;

  const ReforestZone({
    this.suitabilityScore = 0,
    this.treesRequired = 0,
    this.costEstimateUsd = 0,
    this.timeToRecoveryYears = 0,
    this.co2SequestrationTonnes = 0,
    this.nativeSpeciesRecommended = const [],
  });

  factory ReforestZone.fromMap(Map<dynamic, dynamic> map) {
    return ReforestZone(
      suitabilityScore: (map['suitability_score'] ?? 0)
          .toInt(), // Kept for compatibility if used
      treesRequired: 0,
      costEstimateUsd: (map['estimated_cost_usd'] ?? 0).toInt(),
      timeToRecoveryYears: (map['years_to_recovery'] ?? 0).toInt(),
      co2SequestrationTonnes: 0,
      nativeSpeciesRecommended:
          (map['native_species_to_plant'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// URGENCY (For Decision Makers)
// ═══════════════════════════════════════════════════════════════
class Urgency {
  final String level;
  final int interventionWindowDays;
  final String irreversibilityRisk;
  final String tippingPointProximity;

  const Urgency({
    this.level = 'MEDIUM',
    this.interventionWindowDays = 30,
    this.irreversibilityRisk = 'LOW',
    this.tippingPointProximity = '',
  });

  factory Urgency.fromMap(Map<dynamic, dynamic> map) {
    return Urgency(
      level: map['level']?.toString() ?? 'MEDIUM',
      interventionWindowDays: (map['intervention_window_days'] ?? 30).toInt(),
      irreversibilityRisk: map['irreversibility_risk']?.toString() ?? 'LOW',
      tippingPointProximity: map['tipping_point_proximity']?.toString() ?? '',
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// RECOMMENDED ACTION
// ═══════════════════════════════════════════════════════════════
class RecommendedAction {
  final String action;
  final String priority;
  final String responsibleEntity;
  final int estimatedCostUsd;

  const RecommendedAction({
    required this.action,
    this.priority = 'SHORT_TERM',
    this.responsibleEntity = '',
    this.estimatedCostUsd = 0,
  });

  factory RecommendedAction.fromMap(Map<dynamic, dynamic> map) {
    return RecommendedAction(
      action: map['action']?.toString() ?? '',
      priority: map['priority']?.toString() ?? 'SHORT_TERM',
      responsibleEntity: map['responsible_entity']?.toString() ?? '',
      estimatedCostUsd: (map['estimated_cost_usd'] ?? 0).toInt(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// DATA SOURCE
// ═══════════════════════════════════════════════════════════════
class DataSource {
  final String name;
  final String url;
  final String lastUpdated;

  const DataSource({required this.name, this.url = '', this.lastUpdated = ''});

  factory DataSource.fromMap(Map<dynamic, dynamic> map) {
    return DataSource(
      name: map['name']?.toString() ?? '',
      url: map['url']?.toString() ?? '',
      lastUpdated: map['last_updated']?.toString() ?? '',
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// GIS & ANALYTICS EXTENSIONS
// ═══════════════════════════════════════════════════════════════
extension GISAnalysis on IntelligenceNode {
  double get estimatedImpactKm2 => hectares / 100;

  List<FlSpot> getTemporalLossSpots() {
    if (yearlyHistory.isEmpty) return [];
    final sortedYears = yearlyHistory.keys.toList()..sort();
    double x = 0;
    return sortedYears
        .map((year) => FlSpot(x++, yearlyHistory[year] ?? 0))
        .toList();
  }

  int get endangeredSpeciesCount => faunaAtRisk.length + floraAtRisk.length;

  String get formattedEconomicLoss {
    final total = economicImpacts.totalUsd;
    if (total >= 1000000) return '\$${(total / 1000000).toStringAsFixed(1)}M';
    if (total >= 1000) return '\$${(total / 1000).toStringAsFixed(0)}K';
    return '\$$total';
  }

  String get formattedCarbonEmissions {
    final tonnes = carbonData.annualEmissionsTonnes;
    if (tonnes >= 1000000) {
      return '${(tonnes / 1000000).toStringAsFixed(1)}M tonnes';
    }
    if (tonnes >= 1000) return '${(tonnes / 1000).toStringAsFixed(0)}K tonnes';
    return '${tonnes.toStringAsFixed(0)} tonnes';
  }

  bool get isHighPriority =>
      urgency.level == 'CRITICAL' || urgency.level == 'HIGH';

  bool get hasLegalComplications =>
      legalStatus.protectedArea || legalStatus.indigenousTerritory;

  // ═══════════════════════════════════════════════════════════════
  // PROXIMITY ANALYSIS GETTERS
  // ═══════════════════════════════════════════════════════════════

  /// Distance to nearest road in kilometers
  double? get roadDistanceKm {
    final proximity = gisAnalysis['proximity_analysis'];
    if (proximity == null) return null;
    final value = proximity['road_distance_km'];
    return value is num ? value.toDouble() : null;
  }

  /// Distance to nearest river in kilometers
  double? get riverDistanceKm {
    final proximity = gisAnalysis['proximity_analysis'];
    if (proximity == null) return null;
    final value = proximity['river_distance_km'];
    return value is num ? value.toDouble() : null;
  }

  /// Distance to nearest settlement in kilometers
  double? get settlementDistanceKm {
    final proximity = gisAnalysis['proximity_analysis'];
    if (proximity == null) return null;
    final value = proximity['settlement_distance_km'];
    return value is num ? value.toDouble() : null;
  }

  /// Distance to nearest protected area in kilometers
  double? get protectedAreaDistanceKm {
    final proximity = gisAnalysis['proximity_analysis'];
    if (proximity == null) return null;
    final value = proximity['protected_area_distance_km'];
    return value is num ? value.toDouble() : null;
  }

  // ═══════════════════════════════════════════════════════════════
  // BUFFER ANALYSIS GETTERS
  // ═══════════════════════════════════════════════════════════════

  /// Buffer area within 1km in hectares
  double? get buffer1kmAreaHa {
    final buffer = gisAnalysis['buffer_analysis'];
    if (buffer == null) return null;
    final value = buffer['buffer_1km_area_ha'];
    return value is num ? value.toDouble() : null;
  }

  /// Buffer area within 5km in hectares
  double? get buffer5kmAreaHa {
    final buffer = gisAnalysis['buffer_analysis'];
    if (buffer == null) return null;
    final value = buffer['buffer_5km_area_ha'];
    return value is num ? value.toDouble() : null;
  }

  /// Buffer area within 10km in hectares
  double? get buffer10kmAreaHa {
    final buffer = gisAnalysis['buffer_analysis'];
    if (buffer == null) return null;
    final value = buffer['buffer_10km_area_ha'];
    return value is num ? value.toDouble() : null;
  }

  // ═══════════════════════════════════════════════════════════════
  // VEGETATION INDICES GETTERS (Sentinel Data)
  // ═══════════════════════════════════════════════════════════════

  /// NDVI value before deforestation
  double? get ndviBefore {
    final vegIndices = sentinelVerification['vegetation_indices'];
    if (vegIndices == null) return null;
    final value = vegIndices['before_mean'] ?? vegIndices['ndvi_before'];
    return value is num ? value.toDouble() : null;
  }

  /// NDVI value after deforestation
  double? get ndviAfter {
    final vegIndices = sentinelVerification['vegetation_indices'];
    if (vegIndices == null) return null;
    final value = vegIndices['after_mean'] ?? vegIndices['ndvi_after'];
    return value is num ? value.toDouble() : null;
  }

  /// NDVI change (negative = vegetation loss)
  double? get ndviChange {
    final vegIndices = sentinelVerification['vegetation_indices'];
    if (vegIndices == null) return null;
    final value = vegIndices['change_mean'] ?? vegIndices['ndvi_change'];
    return value is num ? value.toDouble() : null;
  }

  /// Current NDVI value (uses after value or direct ndvi field)
  double? get currentNdvi {
    // Try direct ndvi field first
    final directNdvi = sentinelVerification['ndvi'];
    if (directNdvi is num) return directNdvi.toDouble();
    // Fall back to vegetation indices
    return ndviAfter;
  }

  /// EVI (Enhanced Vegetation Index) value
  double? get currentEvi {
    final vegIndices = sentinelVerification['vegetation_indices'];
    if (vegIndices == null) return null;
    final value = vegIndices['evi'] ?? vegIndices['evi_mean'];
    return value is num ? value.toDouble() : null;
  }

  // ═══════════════════════════════════════════════════════════════
  // DATA AVAILABILITY HELPERS FOR SPATIAL ANALYSIS
  // ═══════════════════════════════════════════════════════════════

  /// Whether proximity analysis data is available
  bool get hasProximityData => gisAnalysis['proximity_analysis'] != null;

  /// Whether buffer analysis data is available
  bool get hasBufferData => gisAnalysis['buffer_analysis'] != null;

  /// Whether vegetation indices data is available
  bool get hasVegetationData => sentinelVerification['vegetation_indices'] != null;

  /// Whether historical yearly data is available
  bool get hasHistoricalData => yearlyHistory.isNotEmpty;

  /// Whether terrain analysis data is available
  bool get hasTerrainData => terrainAnalysis.isNotEmpty;
}
