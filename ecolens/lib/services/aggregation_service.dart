import 'package:ecolens/model/location_model.dart';

/// Centralized aggregation logic for dashboard and map statistics.
/// Provides a single source of truth for all metric calculations.
class AggregatedMetrics {
  // Population & Settlements
  final int totalPopulation;
  final bool hasPopulationData;
  final int totalSettlements;
  final bool hasSettlementsData;

  // Area & Carbon
  final double totalHectares;
  final double totalCarbonEmissions;
  final double totalCarbonStock;

  // Economic
  final int totalEconomicLoss;
  final int totalReforestCost;
  final bool hasReforestCostData;

  // Recovery
  final double avgRecoveryScore;
  final int nodesWithRecoveryData;
  final double recoveryHectares;

  // Risk
  final int criticalZoneCount; // >= 80%
  final int highRiskZoneCount; // >= 60%
  final int totalSpeciesAtRisk;
  final double avgRiskScore;

  // Counts
  final int totalNodes;

  const AggregatedMetrics({
    required this.totalPopulation,
    required this.hasPopulationData,
    required this.totalSettlements,
    required this.hasSettlementsData,
    required this.totalHectares,
    required this.totalCarbonEmissions,
    required this.totalCarbonStock,
    required this.totalEconomicLoss,
    required this.totalReforestCost,
    required this.hasReforestCostData,
    required this.avgRecoveryScore,
    required this.nodesWithRecoveryData,
    required this.recoveryHectares,
    required this.criticalZoneCount,
    required this.highRiskZoneCount,
    required this.totalSpeciesAtRisk,
    required this.avgRiskScore,
    required this.totalNodes,
  });

  /// Creates empty metrics when no data is available
  factory AggregatedMetrics.empty() => const AggregatedMetrics(
        totalPopulation: 0,
        hasPopulationData: false,
        totalSettlements: 0,
        hasSettlementsData: false,
        totalHectares: 0,
        totalCarbonEmissions: 0,
        totalCarbonStock: 0,
        totalEconomicLoss: 0,
        totalReforestCost: 0,
        hasReforestCostData: false,
        avgRecoveryScore: -1,
        nodesWithRecoveryData: 0,
        recoveryHectares: 0,
        criticalZoneCount: 0,
        highRiskZoneCount: 0,
        totalSpeciesAtRisk: 0,
        avgRiskScore: 0,
        totalNodes: 0,
      );

  /// Computes aggregated metrics from a list of IntelligenceNodes
  factory AggregatedMetrics.fromNodes(List<IntelligenceNode> nodes) {
    if (nodes.isEmpty) return AggregatedMetrics.empty();

    int totalPopulation = 0;
    bool hasPopulationData = false;
    int totalSettlements = 0;
    bool hasSettlementsData = false;

    double totalHectares = 0;
    double totalCarbonEmissions = 0;
    double totalCarbonStock = 0;

    int totalEconomicLoss = 0;
    int totalReforestCost = 0;
    bool hasReforestCostData = false;

    double sumRecoveryScores = 0;
    int nodesWithRecoveryData = 0;
    double recoveryHectares = 0;

    int criticalZoneCount = 0;
    int highRiskZoneCount = 0;
    int totalSpeciesAtRisk = 0;
    double sumRiskScores = 0;

    for (final node in nodes) {
      // Population & Settlements
      if (node.hasPopulationData) {
        totalPopulation += node.population;
        hasPopulationData = true;
      }
      if (node.hasSettlementsData) {
        totalSettlements += node.settlementsCount;
        hasSettlementsData = true;
      }

      // Area & Carbon
      totalHectares += node.hectares;
      totalCarbonEmissions += node.carbonData.annualEmissionsTonnes;
      totalCarbonStock += node.carbonData.carbonStockTonnes;

      // Economic
      totalEconomicLoss += node.economicImpacts.longTermLossUsd;
      if (node.hasReforestCostData) {
        totalReforestCost += node.reforestZone.costEstimateUsd;
        hasReforestCostData = true;
      }

      // Recovery - use suitability score if available, otherwise recovery score
      if (node.hasSuitabilityData || node.hasRecoveryData) {
        final recoveryValue = node.hasSuitabilityData
            ? node.reforestZone.suitabilityScore.toDouble()
            : node.recoveryScore;
        sumRecoveryScores += recoveryValue;
        recoveryHectares += node.hectares * (recoveryValue / 100);
        nodesWithRecoveryData++;
      }

      // Risk
      sumRiskScores += node.riskScore;
      if (node.riskScore >= 80) criticalZoneCount++;
      if (node.riskScore >= 60) highRiskZoneCount++;

      // Species
      totalSpeciesAtRisk += node.faunaAtRisk.length + node.floraAtRisk.length;
    }

    return AggregatedMetrics(
      totalPopulation: totalPopulation,
      hasPopulationData: hasPopulationData,
      totalSettlements: totalSettlements,
      hasSettlementsData: hasSettlementsData,
      totalHectares: totalHectares,
      totalCarbonEmissions: totalCarbonEmissions,
      totalCarbonStock: totalCarbonStock,
      totalEconomicLoss: totalEconomicLoss,
      totalReforestCost: totalReforestCost,
      hasReforestCostData: hasReforestCostData,
      avgRecoveryScore: nodesWithRecoveryData > 0
          ? sumRecoveryScores / nodesWithRecoveryData
          : -1,
      nodesWithRecoveryData: nodesWithRecoveryData,
      recoveryHectares: recoveryHectares,
      criticalZoneCount: criticalZoneCount,
      highRiskZoneCount: highRiskZoneCount,
      totalSpeciesAtRisk: totalSpeciesAtRisk,
      avgRiskScore: nodes.isNotEmpty ? sumRiskScores / nodes.length : 0,
      totalNodes: nodes.length,
    );
  }
}

/// Service class for computing aggregated metrics
class AggregationService {
  /// Computes metrics for a list of nodes
  static AggregatedMetrics compute(List<IntelligenceNode> nodes) {
    return AggregatedMetrics.fromNodes(nodes);
  }

  /// Computes metrics for nodes filtered by region
  static AggregatedMetrics computeForRegion(
    List<IntelligenceNode> nodes,
    String country,
  ) {
    final filtered = nodes.where((n) => n.country == country).toList();
    return AggregatedMetrics.fromNodes(filtered);
  }

  /// Computes metrics for nodes within a radius of a location
  static AggregatedMetrics computeNearLocation(
    List<IntelligenceNode> nodes,
    double lat,
    double lng,
    double radiusKm,
  ) {
    final filtered = nodes.where((n) {
      final distance = _haversineDistance(lat, lng, n.lat, n.lng);
      return distance <= radiusKm;
    }).toList();
    return AggregatedMetrics.fromNodes(filtered);
  }

  /// Haversine distance calculation in kilometers
  static double _haversineDistance(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const double earthRadiusKm = 6371;
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    final a = _sin(dLat / 2) * _sin(dLat / 2) +
        _cos(_toRadians(lat1)) *
            _cos(_toRadians(lat2)) *
            _sin(dLng / 2) *
            _sin(dLng / 2);
    final c = 2 * _atan2(_sqrt(a), _sqrt(1 - a));
    return earthRadiusKm * c;
  }

  static double _toRadians(double degrees) => degrees * 3.141592653589793 / 180;
  static double _sin(double x) => _taylorSin(x);
  static double _cos(double x) => _taylorCos(x);
  static double _sqrt(double x) => x > 0 ? _newtonSqrt(x) : 0;
  static double _atan2(double y, double x) {
    if (x > 0) return _taylorAtan(y / x);
    if (x < 0 && y >= 0) return _taylorAtan(y / x) + 3.141592653589793;
    if (x < 0 && y < 0) return _taylorAtan(y / x) - 3.141592653589793;
    if (x == 0 && y > 0) return 3.141592653589793 / 2;
    if (x == 0 && y < 0) return -3.141592653589793 / 2;
    return 0;
  }

  static double _taylorSin(double x) {
    x = x % (2 * 3.141592653589793);
    double result = x;
    double term = x;
    for (int i = 1; i <= 10; i++) {
      term *= -x * x / ((2 * i) * (2 * i + 1));
      result += term;
    }
    return result;
  }

  static double _taylorCos(double x) {
    x = x % (2 * 3.141592653589793);
    double result = 1;
    double term = 1;
    for (int i = 1; i <= 10; i++) {
      term *= -x * x / ((2 * i - 1) * (2 * i));
      result += term;
    }
    return result;
  }

  static double _taylorAtan(double x) {
    if (x.abs() > 1) {
      return (x > 0 ? 3.141592653589793 / 2 : -3.141592653589793 / 2) -
          _taylorAtan(1 / x);
    }
    double result = x;
    double term = x;
    for (int i = 1; i <= 20; i++) {
      term *= -x * x;
      result += term / (2 * i + 1);
    }
    return result;
  }

  static double _newtonSqrt(double x) {
    if (x <= 0) return 0;
    double guess = x / 2;
    for (int i = 0; i < 20; i++) {
      guess = (guess + x / guess) / 2;
    }
    return guess;
  }
}
