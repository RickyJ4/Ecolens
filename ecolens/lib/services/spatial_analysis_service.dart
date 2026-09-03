import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:ecolens/model/location_model.dart';
import 'package:ecolens/model/spatial_analysis_result.dart';
import 'package:ecolens/services/spatial_statistics.dart';

/// Core service for performing spatial analysis calculations
class SpatialAnalysisService {
  final NumberFormat _numberFormat = NumberFormat.compact();

  /// Convert Color to hex string without using deprecated .value
  String _colorToHex(Color color) {
    final r = (color.r * 255).round().clamp(0, 255);
    final g = (color.g * 255).round().clamp(0, 255);
    final b = (color.b * 255).round().clamp(0, 255);
    return '#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}';
  }

  // ═══════════════════════════════════════════════════════════════
  // CHANGE DETECTION
  // ═══════════════════════════════════════════════════════════════

  SpatialAnalysisResult runChangeDetection(
    List<IntelligenceNode> nodes,
    int startYear,
    int endYear,
  ) {
    final stopwatch = Stopwatch()..start();

    // Filter nodes with historical data
    final nodesWithHistory = nodes.where((n) => n.yearlyHistory.isNotEmpty).toList();

    if (nodesWithHistory.isEmpty) {
      return SpatialAnalysisResult.empty(SpatialAnalysisType.changeDetection);
    }

    double totalLoss = 0;
    int nodesWithLoss = 0;
    double maxLoss = 0;
    String maxLossRegion = '';

    final features = <Map<String, dynamic>>[];

    for (final node in nodesWithHistory) {
      double nodeLoss = 0;

      // Sum losses between start and end years
      for (final entry in node.yearlyHistory.entries) {
        final year = int.tryParse(entry.key) ?? 0;
        if (year >= startYear && year <= endYear) {
          nodeLoss += entry.value;
        }
      }

      if (nodeLoss > 0) {
        nodesWithLoss++;
        totalLoss += nodeLoss;

        if (nodeLoss > maxLoss) {
          maxLoss = nodeLoss;
          maxLossRegion = node.region.isNotEmpty ? node.region : node.headline;
        }

        // Classify by severity
        String severity;
        Color color;
        if (nodeLoss > 1000) {
          severity = 'critical';
          color = const Color(0xFFFF3B3B);
        } else if (nodeLoss > 500) {
          severity = 'high';
          color = const Color(0xFFFF8C00);
        } else if (nodeLoss > 100) {
          severity = 'moderate';
          color = const Color(0xFFFFD700);
        } else {
          severity = 'low';
          color = const Color(0xFF00E676);
        }

        features.add({
          'type': 'Feature',
          'properties': {
            'id': node.id,
            'name': node.headline,
            'loss': nodeLoss,
            'severity': severity,
            'color': _colorToHex(color),
            'startYear': startYear,
            'endYear': endYear,
          },
          'geometry': {
            'type': 'Point',
            'coordinates': [node.lng, node.lat],
          },
        });
      }
    }

    final years = endYear - startYear;
    final avgAnnualLoss = years > 0 ? totalLoss / years : 0;

    stopwatch.stop();

    return SpatialAnalysisResult(
      type: SpatialAnalysisType.changeDetection,
      summary: {
        'totalLoss': totalLoss,
        'avgAnnualLoss': avgAnnualLoss,
        'nodesWithLoss': nodesWithLoss,
        'years': years,
        'maxLoss': maxLoss,
        'maxLossRegion': maxLossRegion,
      },
      geoJson: {
        'type': 'FeatureCollection',
        'features': features,
      },
      statistics: [
        AnalysisStatistic(
          label: 'Total Forest Loss',
          value: '${_numberFormat.format(totalLoss.toInt())}',
          unit: 'hectares',
          color: Colors.red,
          icon: Icons.trending_down,
        ),
        AnalysisStatistic(
          label: 'Annual Average',
          value: '${_numberFormat.format(avgAnnualLoss.toInt())}',
          unit: 'ha/year',
          color: Colors.orange,
          icon: Icons.calendar_today,
        ),
        AnalysisStatistic(
          label: 'Affected Zones',
          value: '$nodesWithLoss',
          unit: 'zones',
          color: Colors.amber,
          icon: Icons.location_on,
        ),
        AnalysisStatistic(
          label: 'Worst Affected',
          value: maxLossRegion.length > 20 ? '${maxLossRegion.substring(0, 20)}...' : maxLossRegion,
          unit: '${_numberFormat.format(maxLoss.toInt())} ha',
          color: Colors.redAccent,
          icon: Icons.warning,
        ),
      ],
      legend: const [
        LegendItem(label: 'Critical (>1000 ha)', color: Color(0xFFFF3B3B)),
        LegendItem(label: 'High (500-1000 ha)', color: Color(0xFFFF8C00)),
        LegendItem(label: 'Moderate (100-500 ha)', color: Color(0xFFFFD700)),
        LegendItem(label: 'Low (<100 ha)', color: Color(0xFF00E676)),
      ],
      timestamp: DateTime.now(),
      nodeCount: nodesWithLoss,
      processingTime: stopwatch.elapsed,
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // VEGETATION INDEX (NDVI/EVI)
  // ═══════════════════════════════════════════════════════════════

  SpatialAnalysisResult runVegetationAnalysis(
    List<IntelligenceNode> nodes,
    String indexType,
  ) {
    final stopwatch = Stopwatch()..start();

    final features = <Map<String, dynamic>>[];
    double totalNdvi = 0;
    int count = 0;
    int degradedCount = 0;
    int healthyCount = 0;

    for (final node in nodes) {
      // Try to get NDVI from sentinel verification
      final sentinel = node.sentinelVerification;
      double? ndvi;

      if (sentinel.isNotEmpty) {
        final vegIndices = sentinel['vegetation_indices'] as Map<String, dynamic>?;
        if (vegIndices != null) {
          ndvi = (vegIndices['${indexType}_after_mean'] ?? vegIndices['after_mean'])?.toDouble();
        }
      }

      // Fallback: estimate from recovery score
      ndvi ??= node.hasRecoveryData ? (node.recoveryScore / 100) * 0.8 : null;

      if (ndvi != null) {
        count++;
        totalNdvi += ndvi;

        // Classify vegetation health
        String health;
        Color color;
        if (ndvi < 0.2) {
          health = 'barren';
          color = const Color(0xFF8B4513);
          degradedCount++;
        } else if (ndvi < 0.4) {
          health = 'sparse';
          color = const Color(0xFFCDAA7D);
          degradedCount++;
        } else if (ndvi < 0.6) {
          health = 'moderate';
          color = const Color(0xFF90EE90);
        } else if (ndvi < 0.8) {
          health = 'healthy';
          color = const Color(0xFF228B22);
          healthyCount++;
        } else {
          health = 'dense';
          color = const Color(0xFF006400);
          healthyCount++;
        }

        features.add({
          'type': 'Feature',
          'properties': {
            'id': node.id,
            'name': node.headline,
            'ndvi': ndvi,
            'health': health,
            'color': _colorToHex(color),
          },
          'geometry': {
            'type': 'Point',
            'coordinates': [node.lng, node.lat],
          },
        });
      }
    }

    final avgNdvi = count > 0 ? totalNdvi / count : 0.0;

    stopwatch.stop();

    if (count == 0) {
      return SpatialAnalysisResult.empty(SpatialAnalysisType.vegetationIndex);
    }

    return SpatialAnalysisResult(
      type: SpatialAnalysisType.vegetationIndex,
      summary: {
        'averageNdvi': avgNdvi,
        'healthyCount': healthyCount,
        'degradedCount': degradedCount,
        'totalCount': count,
      },
      geoJson: {
        'type': 'FeatureCollection',
        'features': features,
      },
      statistics: [
        AnalysisStatistic(
          label: 'Average ${indexType.toUpperCase()}',
          value: avgNdvi.toStringAsFixed(2),
          color: _getNdviColor(avgNdvi),
          icon: Icons.eco,
        ),
        AnalysisStatistic(
          label: 'Healthy Vegetation',
          value: '$healthyCount',
          unit: 'zones',
          color: Colors.green,
          icon: Icons.check_circle,
        ),
        AnalysisStatistic(
          label: 'Degraded Areas',
          value: '$degradedCount',
          unit: 'zones',
          color: Colors.orange,
          icon: Icons.warning,
        ),
        AnalysisStatistic(
          label: 'Analyzed Zones',
          value: '$count',
          color: Colors.blue,
          icon: Icons.analytics,
        ),
      ],
      legend: const [
        LegendItem(label: 'Dense (>0.8)', color: Color(0xFF006400)),
        LegendItem(label: 'Healthy (0.6-0.8)', color: Color(0xFF228B22)),
        LegendItem(label: 'Moderate (0.4-0.6)', color: Color(0xFF90EE90)),
        LegendItem(label: 'Sparse (0.2-0.4)', color: Color(0xFFCDAA7D)),
        LegendItem(label: 'Barren (<0.2)', color: Color(0xFF8B4513)),
      ],
      timestamp: DateTime.now(),
      nodeCount: count,
      processingTime: stopwatch.elapsed,
    );
  }

  Color _getNdviColor(double ndvi) {
    if (ndvi < 0.2) return const Color(0xFF8B4513);
    if (ndvi < 0.4) return const Color(0xFFCDAA7D);
    if (ndvi < 0.6) return const Color(0xFF90EE90);
    if (ndvi < 0.8) return const Color(0xFF228B22);
    return const Color(0xFF006400);
  }

  // ═══════════════════════════════════════════════════════════════
  // BUFFER ANALYSIS
  // Creates circular buffer zones around deforestation areas
  // ═══════════════════════════════════════════════════════════════

  SpatialAnalysisResult runBufferAnalysis(
    List<IntelligenceNode> nodes,
    double distanceKm,
  ) {
    final stopwatch = Stopwatch()..start();

    final features = <Map<String, dynamic>>[];
    double totalBufferArea = 0;
    double totalCoreArea = 0;
    int nodesWithBuffer = 0;
    int criticalNodes = 0;
    int highRiskNodes = 0;
    int lowRiskNodes = 0;
    double avgRiskInBuffer = 0;

    // Get buffer data from GIS analysis or calculate
    for (final node in nodes) {
      double? bufferArea;

      // Try to get pre-calculated buffer from GIS analysis
      final bufferAnalysis = node.gisAnalysis['buffer_analysis'] as Map<String, dynamic>?;
      if (bufferAnalysis != null) {
        if (distanceKm <= 1) {
          bufferArea = (bufferAnalysis['buffer_1km_area_ha'] as num?)?.toDouble();
        } else if (distanceKm <= 5) {
          bufferArea = (bufferAnalysis['buffer_5km_area_ha'] as num?)?.toDouble();
        } else {
          bufferArea = (bufferAnalysis['buffer_10km_area_ha'] as num?)?.toDouble();
        }
      }

      // Fallback: estimate buffer area (πr² in hectares)
      bufferArea ??= math.pi * distanceKm * distanceKm * 100;

      nodesWithBuffer++;
      totalBufferArea += bufferArea;
      totalCoreArea += node.hectares;
      avgRiskInBuffer += node.riskScore;

      // Classify by risk level
      if (node.riskScore >= 80) criticalNodes++;
      else if (node.riskScore >= 60) highRiskNodes++;
      else lowRiskNodes++;

      // Color based on risk score
      Color color;
      String riskLevel;
      if (node.riskScore >= 80) {
        color = const Color(0xFFFF3B3B);
        riskLevel = 'Critical';
      } else if (node.riskScore >= 60) {
        color = const Color(0xFFFF8C00);
        riskLevel = 'High';
      } else if (node.riskScore >= 40) {
        color = const Color(0xFFFFD700);
        riskLevel = 'Moderate';
      } else {
        color = const Color(0xFF00E676);
        riskLevel = 'Low';
      }

      // Create buffer polygon (circle with 32 points)
      final polygon = _createCirclePolygon(node.lat, node.lng, distanceKm);

      // Add buffer zone polygon
      features.add({
        'type': 'Feature',
        'properties': {
          'id': node.id,
          'name': node.headline,
          'bufferKm': distanceKm,
          'areaHa': bufferArea,
          'coreAreaHa': node.hectares,
          'riskScore': node.riskScore,
          'riskLevel': riskLevel,
          'featureType': 'buffer_zone',
          'color': _colorToHex(color),
        },
        'geometry': {
          'type': 'Polygon',
          'coordinates': [polygon],
        },
      });

      // Add center point for the core deforestation zone
      features.add({
        'type': 'Feature',
        'properties': {
          'id': '${node.id}-center',
          'name': node.headline,
          'hectares': node.hectares,
          'riskScore': node.riskScore,
          'featureType': 'core_zone',
          'color': _colorToHex(color),
        },
        'geometry': {
          'type': 'Point',
          'coordinates': [node.lng, node.lat],
        },
      });

      // Add inner buffer ring (half distance) for visualization
      final innerPolygon = _createCirclePolygon(node.lat, node.lng, distanceKm / 2);
      features.add({
        'type': 'Feature',
        'properties': {
          'id': '${node.id}-inner',
          'bufferKm': distanceKm / 2,
          'featureType': 'inner_buffer',
          'color': _colorToHex(color),
        },
        'geometry': {
          'type': 'Polygon',
          'coordinates': [innerPolygon],
        },
      });
    }

    avgRiskInBuffer = nodesWithBuffer > 0 ? avgRiskInBuffer / nodesWithBuffer : 0;
    final avgBufferArea = nodesWithBuffer > 0 ? totalBufferArea / nodesWithBuffer : 0;
    final bufferPerKm2 = math.pi * distanceKm * distanceKm;

    stopwatch.stop();

    return SpatialAnalysisResult(
      type: SpatialAnalysisType.bufferAnalysis,
      summary: {
        'bufferDistance': distanceKm,
        'totalBufferArea': totalBufferArea,
        'totalCoreArea': totalCoreArea,
        'avgBufferArea': avgBufferArea,
        'nodeCount': nodesWithBuffer,
        'criticalNodes': criticalNodes,
        'highRiskNodes': highRiskNodes,
        'avgRiskScore': avgRiskInBuffer,
        'analysisDescription': 'Creates ${distanceKm}km circular buffer zones around each deforestation area to analyze impact zones and potential spread areas.',
      },
      geoJson: {
        'type': 'FeatureCollection',
        'features': features,
      },
      statistics: [
        AnalysisStatistic(
          label: 'Buffer Radius',
          value: '${distanceKm.toStringAsFixed(1)}',
          unit: 'km around each zone',
          color: Colors.blue,
          icon: Icons.radio_button_unchecked,
        ),
        AnalysisStatistic(
          label: 'Total Impact Area',
          value: _numberFormat.format(totalBufferArea.toInt()),
          unit: 'ha (buffers)',
          color: Colors.cyan,
          icon: Icons.blur_circular,
        ),
        AnalysisStatistic(
          label: 'Core Forest Loss',
          value: _numberFormat.format(totalCoreArea.toInt()),
          unit: 'ha (centers)',
          color: Colors.red,
          icon: Icons.forest,
        ),
        AnalysisStatistic(
          label: 'Per Buffer Area',
          value: '${bufferPerKm2.toStringAsFixed(0)}',
          unit: 'km² each',
          color: Colors.teal,
          icon: Icons.square_foot,
        ),
        AnalysisStatistic(
          label: 'Critical Zones',
          value: '$criticalNodes',
          unit: 'risk >80%',
          color: const Color(0xFFFF3B3B),
          icon: Icons.warning_amber,
        ),
        AnalysisStatistic(
          label: 'High Risk Zones',
          value: '$highRiskNodes',
          unit: 'risk 60-80%',
          color: const Color(0xFFFF8C00),
          icon: Icons.priority_high,
        ),
        AnalysisStatistic(
          label: 'Lower Risk Zones',
          value: '$lowRiskNodes',
          unit: 'risk <60%',
          color: const Color(0xFF00E676),
          icon: Icons.shield,
        ),
        AnalysisStatistic(
          label: 'Avg Risk Score',
          value: avgRiskInBuffer.toStringAsFixed(0),
          unit: '%',
          color: Colors.orange,
          icon: Icons.speed,
        ),
        AnalysisStatistic(
          label: 'Zones Analyzed',
          value: '$nodesWithBuffer',
          unit: 'deforestation areas',
          color: Colors.purple,
          icon: Icons.analytics,
        ),
      ],
      legend: [
        LegendItem(
          label: '${distanceKm}km Buffer (Impact Zone)',
          color: Colors.blue.withValues(alpha: 0.3),
        ),
        LegendItem(
          label: '${(distanceKm / 2).toStringAsFixed(1)}km Inner Buffer',
          color: Colors.blue.withValues(alpha: 0.5),
        ),
        const LegendItem(label: 'Critical Risk (>80%)', color: Color(0xFFFF3B3B)),
        const LegendItem(label: 'High Risk (60-80%)', color: Color(0xFFFF8C00)),
        const LegendItem(label: 'Moderate Risk (40-60%)', color: Color(0xFFFFD700)),
        const LegendItem(label: 'Lower Risk (<40%)', color: Color(0xFF00E676)),
      ],
      timestamp: DateTime.now(),
      nodeCount: nodesWithBuffer,
      processingTime: stopwatch.elapsed,
    );
  }

  List<List<double>> _createCirclePolygon(double lat, double lng, double radiusKm) {
    const int points = 32;
    final coords = <List<double>>[];

    for (int i = 0; i <= points; i++) {
      final angle = (i * 360 / points) * math.pi / 180;

      // Convert km to degrees (approximate)
      final dLat = (radiusKm / 111.32) * math.cos(angle);
      final dLng = (radiusKm / (111.32 * math.cos(lat * math.pi / 180))) * math.sin(angle);

      coords.add([lng + dLng, lat + dLat]);
    }

    return coords;
  }

  // ═══════════════════════════════════════════════════════════════
  // PROXIMITY ANALYSIS
  // Measures distance from deforestation zones to infrastructure
  // ═══════════════════════════════════════════════════════════════

  SpatialAnalysisResult runProximityAnalysis(
    List<IntelligenceNode> nodes,
    String infrastructureType,
  ) {
    final stopwatch = Stopwatch()..start();

    final features = <Map<String, dynamic>>[];
    double totalDistance = 0;
    int count = 0;
    int nearbyCount = 0; // Within 5km
    int closeCount = 0; // 5-10km
    int moderateCount = 0; // 10-25km
    int remoteCount = 0; // Beyond 25km
    double minDistance = double.infinity;
    double maxDistance = 0;
    String closestZone = '';
    double totalAtRiskHectares = 0;

    for (final node in nodes) {
      double? distance;

      // Get distance from GIS analysis
      final proximity = node.gisAnalysis['proximity_analysis'] as Map<String, dynamic>?;
      if (proximity != null) {
        switch (infrastructureType) {
          case 'roads':
            distance = (proximity['road_distance_km'] as num?)?.toDouble();
            break;
          case 'rivers':
            distance = (proximity['river_distance_km'] as num?)?.toDouble();
            break;
          case 'settlements':
            distance = (proximity['settlement_distance_km'] as num?)?.toDouble();
            break;
          case 'protected':
            distance = (proximity['protected_area_distance_km'] as num?)?.toDouble();
            break;
        }
      }

      // Use nearest settlement if available as fallback
      distance ??= node.nearestSettlementKm > 0 ? node.nearestSettlementKm : null;

      if (distance != null && distance > 0) {
        count++;
        totalDistance += distance;

        // Track min/max distances
        if (distance < minDistance) {
          minDistance = distance;
          closestZone = node.headline.isNotEmpty ? node.headline : node.region;
        }
        if (distance > maxDistance) {
          maxDistance = distance;
        }

        // Categorize by distance bands
        if (distance <= 5) {
          nearbyCount++;
          totalAtRiskHectares += node.hectares;
        } else if (distance <= 10) {
          closeCount++;
          totalAtRiskHectares += node.hectares * 0.7;
        } else if (distance <= 25) {
          moderateCount++;
        } else {
          remoteCount++;
        }

        // Size inversely proportional to distance (closer = larger)
        final size = (30 / (distance + 1)).clamp(5, 25).toDouble();

        // Color based on proximity band
        Color color;
        String band;
        String riskLevel;
        if (distance <= 5) {
          color = const Color(0xFFFF3B3B);
          band = 'critical';
          riskLevel = 'Critical';
        } else if (distance <= 10) {
          color = const Color(0xFFFF8C00);
          band = 'high';
          riskLevel = 'High';
        } else if (distance <= 25) {
          color = const Color(0xFFFFD700);
          band = 'moderate';
          riskLevel = 'Moderate';
        } else {
          color = const Color(0xFF00E676);
          band = 'low';
          riskLevel = 'Low';
        }

        // Add point feature for the deforestation zone
        features.add({
          'type': 'Feature',
          'properties': {
            'id': node.id,
            'name': node.headline,
            'distance': distance,
            'size': size,
            'band': band,
            'riskLevel': riskLevel,
            'hectares': node.hectares,
            'featureType': 'zone',
            'color': _colorToHex(color),
            'infrastructureType': infrastructureType,
          },
          'geometry': {
            'type': 'Point',
            'coordinates': [node.lng, node.lat],
          },
        });

        // Add a radial line showing the distance to infrastructure
        final angle = (count * 37.0) % 360 * math.pi / 180;
        final endLat = node.lat + (distance / 111.32) * math.cos(angle);
        final endLng = node.lng + (distance / (111.32 * math.cos(node.lat * math.pi / 180))) * math.sin(angle);

        features.add({
          'type': 'Feature',
          'properties': {
            'id': '${node.id}-line',
            'distance': distance,
            'featureType': 'distance_line',
            'color': _colorToHex(color),
          },
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              [node.lng, node.lat],
              [endLng, endLat],
            ],
          },
        });

        // Add infrastructure endpoint marker
        features.add({
          'type': 'Feature',
          'properties': {
            'id': '${node.id}-infra',
            'featureType': 'infrastructure_point',
            'infrastructureType': infrastructureType,
            'color': '#FFFFFF',
          },
          'geometry': {
            'type': 'Point',
            'coordinates': [endLng, endLat],
          },
        });
      }
    }

    final avgDistance = count > 0 ? totalDistance / count : 0;
    if (minDistance == double.infinity) minDistance = 0;

    stopwatch.stop();

    if (count == 0) {
      return SpatialAnalysisResult.empty(SpatialAnalysisType.proximityAnalysis);
    }

    final typeLabel = _getInfrastructureLabel(infrastructureType);
    final typeIcon = _getInfrastructureIcon(infrastructureType);

    return SpatialAnalysisResult(
      type: SpatialAnalysisType.proximityAnalysis,
      summary: {
        'infrastructureType': infrastructureType,
        'typeLabel': typeLabel,
        'averageDistance': avgDistance,
        'minDistance': minDistance,
        'maxDistance': maxDistance,
        'nearbyCount': nearbyCount,
        'closeCount': closeCount,
        'moderateCount': moderateCount,
        'remoteCount': remoteCount,
        'totalCount': count,
        'closestZone': closestZone,
        'totalAtRiskHectares': totalAtRiskHectares,
        'analysisDescription': 'Distance from deforestation zones to nearest $typeLabel',
      },
      geoJson: {
        'type': 'FeatureCollection',
        'features': features,
      },
      statistics: [
        AnalysisStatistic(
          label: 'Distance To',
          value: typeLabel,
          color: Colors.cyan,
          icon: typeIcon,
        ),
        AnalysisStatistic(
          label: 'Average Distance',
          value: avgDistance.toStringAsFixed(1),
          unit: 'km',
          color: Colors.orange,
          icon: Icons.straighten,
        ),
        AnalysisStatistic(
          label: 'Closest',
          value: minDistance.toStringAsFixed(1),
          unit: 'km',
          color: Colors.red,
          icon: Icons.gps_fixed,
        ),
        AnalysisStatistic(
          label: 'Critical (<5km)',
          value: '$nearbyCount',
          unit: 'zones',
          color: const Color(0xFFFF3B3B),
          icon: Icons.warning_amber,
        ),
        AnalysisStatistic(
          label: 'High Risk (5-10km)',
          value: '$closeCount',
          unit: 'zones',
          color: const Color(0xFFFF8C00),
          icon: Icons.priority_high,
        ),
        AnalysisStatistic(
          label: 'At-Risk Area',
          value: _numberFormat.format(totalAtRiskHectares.toInt()),
          unit: 'ha',
          color: Colors.deepOrange,
          icon: Icons.forest,
        ),
        AnalysisStatistic(
          label: 'Remote (>25km)',
          value: '$remoteCount',
          unit: 'zones',
          color: Colors.green,
          icon: Icons.shield,
        ),
        AnalysisStatistic(
          label: 'Total Analyzed',
          value: '$count',
          unit: 'zones',
          color: Colors.blue,
          icon: Icons.analytics,
        ),
      ],
      legend: [
        LegendItem(label: 'Critical (<5km to $typeLabel)', color: const Color(0xFFFF3B3B)),
        LegendItem(label: 'High Risk (5-10km)', color: const Color(0xFFFF8C00)),
        LegendItem(label: 'Moderate (10-25km)', color: const Color(0xFFFFD700)),
        LegendItem(label: 'Remote (>25km)', color: const Color(0xFF00E676)),
        LegendItem(label: 'Distance Lines to $typeLabel', color: Colors.white.withValues(alpha: 0.5)),
      ],
      timestamp: DateTime.now(),
      nodeCount: count,
      processingTime: stopwatch.elapsed,
    );
  }

  String _getInfrastructureLabel(String type) {
    switch (type) {
      case 'roads':
        return 'Roads';
      case 'rivers':
        return 'Rivers';
      case 'settlements':
        return 'Settlements';
      case 'protected':
        return 'Protected Areas';
      default:
        return type;
    }
  }

  IconData _getInfrastructureIcon(String type) {
    switch (type) {
      case 'roads':
        return Icons.route;
      case 'rivers':
        return Icons.water;
      case 'settlements':
        return Icons.location_city;
      case 'protected':
        return Icons.park;
      default:
        return Icons.place;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // HOTSPOT ANALYSIS (Getis-Ord Gi*)
  // ═══════════════════════════════════════════════════════════════

  SpatialAnalysisResult runHotspotAnalysis(
    List<IntelligenceNode> nodes,
    double bandwidthKm,
  ) {
    final stopwatch = Stopwatch()..start();

    if (nodes.length < 3) {
      return SpatialAnalysisResult.error(
        SpatialAnalysisType.hotspotAnalysis,
        'Need at least 3 points for hotspot analysis',
      );
    }

    // Prepare data for statistics
    final points = nodes.map((n) => {
      'id': n.id,
      'lat': n.lat,
      'lng': n.lng,
      'riskScore': n.riskScore,
    }).toList();

    // Run Getis-Ord Gi*
    final results = SpatialStatistics.getisOrdGiStar(points, 'riskScore', bandwidthKm);

    // Build GeoJSON
    final features = results.map((r) {
      return {
        'type': 'Feature',
        'properties': {
          'id': r.nodeId,
          'giStar': r.giStar,
          'zScore': r.zScore,
          'pValue': r.pValue,
          'classification': r.classification.name,
          'color': _colorToHex(r.classification.color),
        },
        'geometry': {
          'type': 'Point',
          'coordinates': [r.lng, r.lat],
        },
      };
    }).toList();

    // Count classifications
    final hotspotCount = results.where((r) =>
      r.classification == HotspotClassification.hotspot99 ||
      r.classification == HotspotClassification.hotspot95 ||
      r.classification == HotspotClassification.hotspot90).length;

    final coldspotCount = results.where((r) =>
      r.classification == HotspotClassification.coldspot99 ||
      r.classification == HotspotClassification.coldspot95 ||
      r.classification == HotspotClassification.coldspot90).length;

    final notSigCount = results.where((r) =>
      r.classification == HotspotClassification.notSignificant).length;

    stopwatch.stop();

    return SpatialAnalysisResult(
      type: SpatialAnalysisType.hotspotAnalysis,
      summary: {
        'bandwidth': bandwidthKm,
        'hotspotCount': hotspotCount,
        'coldspotCount': coldspotCount,
        'notSignificantCount': notSigCount,
      },
      geoJson: {
        'type': 'FeatureCollection',
        'features': features,
      },
      statistics: [
        AnalysisStatistic(
          label: 'Hot Spots',
          value: '$hotspotCount',
          unit: 'clusters',
          color: Colors.red,
          icon: Icons.local_fire_department,
        ),
        AnalysisStatistic(
          label: 'Cold Spots',
          value: '$coldspotCount',
          unit: 'clusters',
          color: Colors.blue,
          icon: Icons.ac_unit,
        ),
        AnalysisStatistic(
          label: 'Not Significant',
          value: '$notSigCount',
          unit: 'zones',
          color: Colors.grey,
          icon: Icons.remove_circle_outline,
        ),
        AnalysisStatistic(
          label: 'Bandwidth',
          value: '${bandwidthKm.toInt()}',
          unit: 'km',
          color: Colors.cyan,
          icon: Icons.radar,
        ),
      ],
      legend: [
        LegendItem(label: HotspotClassification.hotspot99.label, color: HotspotClassification.hotspot99.color),
        LegendItem(label: HotspotClassification.hotspot95.label, color: HotspotClassification.hotspot95.color),
        LegendItem(label: HotspotClassification.hotspot90.label, color: HotspotClassification.hotspot90.color),
        LegendItem(label: HotspotClassification.notSignificant.label, color: HotspotClassification.notSignificant.color),
        LegendItem(label: HotspotClassification.coldspot90.label, color: HotspotClassification.coldspot90.color),
        LegendItem(label: HotspotClassification.coldspot95.label, color: HotspotClassification.coldspot95.color),
        LegendItem(label: HotspotClassification.coldspot99.label, color: HotspotClassification.coldspot99.color),
      ],
      timestamp: DateTime.now(),
      nodeCount: results.length,
      processingTime: stopwatch.elapsed,
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // PATTERN ANALYSIS (Moran's I)
  // ═══════════════════════════════════════════════════════════════

  SpatialAnalysisResult runPatternAnalysis(
    List<IntelligenceNode> nodes,
    String variable,
    double bandwidthKm,
  ) {
    final stopwatch = Stopwatch()..start();

    if (nodes.length < 3) {
      return SpatialAnalysisResult.error(
        SpatialAnalysisType.patternAnalysis,
        'Need at least 3 points for pattern analysis',
      );
    }

    // Prepare data
    final points = nodes.map((n) {
      double value;
      switch (variable) {
        case 'riskScore':
          value = n.riskScore;
          break;
        case 'hectares':
          value = n.hectares;
          break;
        case 'population':
          value = n.population.toDouble();
          break;
        default:
          value = n.riskScore;
      }
      return {
        'id': n.id,
        'lat': n.lat,
        'lng': n.lng,
        variable: value,
      };
    }).toList();

    // Global Moran's I
    final globalI = SpatialStatistics.globalMoransI(points, variable, bandwidthKm);

    // Local Moran's I (LISA)
    final lisaResults = SpatialStatistics.localMoransI(points, variable, bandwidthKm);

    // Build GeoJSON
    final features = lisaResults.map((r) {
      return {
        'type': 'Feature',
        'properties': {
          'id': r.nodeId,
          'localI': r.localI,
          'zScore': r.zScore,
          'pValue': r.pValue,
          'quadrant': r.quadrant.name,
          'color': _colorToHex(r.quadrant.color),
        },
        'geometry': {
          'type': 'Point',
          'coordinates': [r.lng, r.lat],
        },
      };
    }).toList();

    // Count quadrants
    final hhCount = lisaResults.where((r) => r.quadrant == LISAQuadrant.highHigh).length;
    final llCount = lisaResults.where((r) => r.quadrant == LISAQuadrant.lowLow).length;
    final hlCount = lisaResults.where((r) => r.quadrant == LISAQuadrant.highLow).length;
    final lhCount = lisaResults.where((r) => r.quadrant == LISAQuadrant.lowHigh).length;

    stopwatch.stop();

    return SpatialAnalysisResult(
      type: SpatialAnalysisType.patternAnalysis,
      summary: {
        'variable': variable,
        'globalMoransI': globalI.moransI,
        'zScore': globalI.zScore,
        'pValue': globalI.pValue,
        'pattern': globalI.pattern.name,
        'hhCount': hhCount,
        'llCount': llCount,
        'hlCount': hlCount,
        'lhCount': lhCount,
      },
      geoJson: {
        'type': 'FeatureCollection',
        'features': features,
      },
      statistics: [
        AnalysisStatistic(
          label: "Global Moran's I",
          value: globalI.moransI.toStringAsFixed(3),
          color: Colors.purple,
          icon: Icons.bubble_chart,
        ),
        AnalysisStatistic(
          label: 'Pattern',
          value: globalI.pattern.name.toUpperCase(),
          color: globalI.pattern == SpatialPattern.clustered ? Colors.red : Colors.blue,
          icon: Icons.grain,
        ),
        AnalysisStatistic(
          label: 'High-High Clusters',
          value: '$hhCount',
          color: LISAQuadrant.highHigh.color,
          icon: Icons.arrow_upward,
        ),
        AnalysisStatistic(
          label: 'Low-Low Clusters',
          value: '$llCount',
          color: LISAQuadrant.lowLow.color,
          icon: Icons.arrow_downward,
        ),
      ],
      legend: [
        LegendItem(label: LISAQuadrant.highHigh.label, color: LISAQuadrant.highHigh.color),
        LegendItem(label: LISAQuadrant.lowLow.label, color: LISAQuadrant.lowLow.color),
        LegendItem(label: LISAQuadrant.highLow.label, color: LISAQuadrant.highLow.color),
        LegendItem(label: LISAQuadrant.lowHigh.label, color: LISAQuadrant.lowHigh.color),
        LegendItem(label: LISAQuadrant.notSignificant.label, color: LISAQuadrant.notSignificant.color),
      ],
      timestamp: DateTime.now(),
      nodeCount: lisaResults.length,
      processingTime: stopwatch.elapsed,
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // RISK MODELING (Prediction)
  // ═══════════════════════════════════════════════════════════════

  SpatialAnalysisResult runRiskModeling(
    List<IntelligenceNode> nodes,
    int forecastYears,
  ) {
    final stopwatch = Stopwatch()..start();

    final features = <Map<String, dynamic>>[];
    int criticalCount = 0;
    int highRiskCount = 0;
    int acceleratingCount = 0;
    double totalPredictedLoss = 0;

    for (final node in nodes) {
      // Calculate predicted risk based on trends
      double predictedRisk = node.riskScore;
      double predictedLoss = 0;

      // Factor in trend direction
      if (node.trendDirection == 'INCREASING') {
        predictedRisk = (node.riskScore * (1 + (node.trendChangePercent / 100) * forecastYears)).clamp(0, 100);
        acceleratingCount++;
      } else if (node.trendDirection == 'DECREASING') {
        predictedRisk = (node.riskScore * (1 - (node.trendChangePercent / 100) * forecastYears)).clamp(0, 100);
      }

      // Use forecast2026 if available
      if (node.forecast2026 > 0) {
        predictedLoss = node.forecast2026 * forecastYears;
      } else {
        // Estimate based on current rate
        predictedLoss = node.hectares * (node.riskScore / 100) * 0.1 * forecastYears;
      }

      totalPredictedLoss += predictedLoss;

      if (predictedRisk >= 80) criticalCount++;
      if (predictedRisk >= 60) highRiskCount++;

      // Classify risk level
      String riskLevel;
      Color color;
      if (predictedRisk >= 80) {
        riskLevel = 'critical';
        color = const Color(0xFFB30000);
      } else if (predictedRisk >= 60) {
        riskLevel = 'high';
        color = const Color(0xFFFF3B3B);
      } else if (predictedRisk >= 40) {
        riskLevel = 'moderate';
        color = const Color(0xFFFF8C00);
      } else {
        riskLevel = 'low';
        color = const Color(0xFF00E676);
      }

      features.add({
        'type': 'Feature',
        'properties': {
          'id': node.id,
          'name': node.headline,
          'currentRisk': node.riskScore,
          'predictedRisk': predictedRisk,
          'predictedLoss': predictedLoss,
          'trend': node.trendDirection,
          'riskLevel': riskLevel,
          'color': _colorToHex(color),
        },
        'geometry': {
          'type': 'Point',
          'coordinates': [node.lng, node.lat],
        },
      });
    }

    stopwatch.stop();

    return SpatialAnalysisResult(
      type: SpatialAnalysisType.riskModeling,
      summary: {
        'forecastYears': forecastYears,
        'criticalCount': criticalCount,
        'highRiskCount': highRiskCount,
        'acceleratingCount': acceleratingCount,
        'totalPredictedLoss': totalPredictedLoss,
      },
      geoJson: {
        'type': 'FeatureCollection',
        'features': features,
      },
      statistics: [
        AnalysisStatistic(
          label: 'Critical Risk Zones',
          value: '$criticalCount',
          unit: 'by ${DateTime.now().year + forecastYears}',
          color: const Color(0xFFB30000),
          icon: Icons.error,
        ),
        AnalysisStatistic(
          label: 'High Risk Zones',
          value: '$highRiskCount',
          color: Colors.red,
          icon: Icons.warning,
        ),
        AnalysisStatistic(
          label: 'Accelerating Trends',
          value: '$acceleratingCount',
          unit: 'zones',
          color: Colors.orange,
          icon: Icons.trending_up,
        ),
        AnalysisStatistic(
          label: 'Predicted Loss',
          value: _numberFormat.format(totalPredictedLoss.toInt()),
          unit: 'ha',
          color: Colors.redAccent,
          icon: Icons.forest,
        ),
      ],
      legend: const [
        LegendItem(label: 'Critical (>80%)', color: Color(0xFFB30000)),
        LegendItem(label: 'High (60-80%)', color: Color(0xFFFF3B3B)),
        LegendItem(label: 'Moderate (40-60%)', color: Color(0xFFFF8C00)),
        LegendItem(label: 'Low (<40%)', color: Color(0xFF00E676)),
      ],
      timestamp: DateTime.now(),
      nodeCount: nodes.length,
      processingTime: stopwatch.elapsed,
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // PREDICTIVE RISK MAP (Infrastructure-Based Risk Prediction)
  // ═══════════════════════════════════════════════════════════════

  SpatialAnalysisResult runPredictiveRiskMap(
    List<IntelligenceNode> nodes,
    double riskThresholdKm,
    String infrastructureType,
  ) {
    final stopwatch = Stopwatch()..start();

    final features = <Map<String, dynamic>>[];
    int veryHighRiskCount = 0; // Within threshold
    int highRiskCount = 0; // Within 2x threshold
    int moderateRiskCount = 0; // Within 5x threshold
    int lowRiskCount = 0; // Beyond 5x threshold
    double totalAtRiskHectares = 0;
    double minDistance = double.infinity;
    double maxDistance = 0;
    double totalDistance = 0;
    int analyzedCount = 0;
    String closestZone = '';
    double closestZoneHectares = 0;
    double avgRiskProbability = 0;

    // Store high-risk nodes for expansion corridor analysis
    final highRiskNodes = <Map<String, dynamic>>[];

    for (final node in nodes) {
      double? distance;

      // Get proximity from GIS analysis
      final proximity = node.gisAnalysis['proximity_analysis'] as Map<String, dynamic>?;
      if (proximity != null) {
        switch (infrastructureType) {
          case 'roads':
            distance = (proximity['road_distance_km'] as num?)?.toDouble();
            break;
          case 'rivers':
            distance = (proximity['river_distance_km'] as num?)?.toDouble();
            break;
          case 'settlements':
            distance = (proximity['settlement_distance_km'] as num?)?.toDouble();
            break;
          case 'protected':
            distance = (proximity['protected_area_distance_km'] as num?)?.toDouble();
            break;
        }
      }

      // Fallback to nearest settlement
      distance ??= node.nearestSettlementKm > 0 ? node.nearestSettlementKm : null;

      if (distance != null && distance > 0) {
        analyzedCount++;
        totalDistance += distance;

        // Track min/max distances
        if (distance < minDistance) {
          minDistance = distance;
          closestZone = node.headline.isNotEmpty ? node.headline : node.region;
          closestZoneHectares = node.hectares;
        }
        if (distance > maxDistance) {
          maxDistance = distance;
        }

        // Classify based on proximity threshold
        String riskLevel;
        Color color;
        double riskProbability;

        if (distance <= riskThresholdKm) {
          // VERY HIGH RISK: Within the threshold (e.g., <2km from road)
          riskLevel = 'very_high';
          color = const Color(0xFFB30000);
          riskProbability = 0.9;
          veryHighRiskCount++;
          totalAtRiskHectares += node.hectares;
          highRiskNodes.add({'lat': node.lat, 'lng': node.lng, 'hectares': node.hectares, 'level': 'very_high'});
        } else if (distance <= riskThresholdKm * 2) {
          // HIGH RISK: Within 2x threshold
          riskLevel = 'high';
          color = const Color(0xFFFF3B3B);
          riskProbability = 0.7;
          highRiskCount++;
          totalAtRiskHectares += node.hectares * 0.7;
          highRiskNodes.add({'lat': node.lat, 'lng': node.lng, 'hectares': node.hectares, 'level': 'high'});
        } else if (distance <= riskThresholdKm * 5) {
          // MODERATE RISK: Within 5x threshold
          riskLevel = 'moderate';
          color = const Color(0xFFFF8C00);
          riskProbability = 0.4;
          moderateRiskCount++;
        } else {
          // LOW RISK: Beyond 5x threshold
          riskLevel = 'low';
          color = const Color(0xFF00E676);
          riskProbability = 0.1;
          lowRiskCount++;
        }

        avgRiskProbability += riskProbability;

        // Add risk zone polygon for very high and high risk areas
        if (riskLevel == 'very_high' || riskLevel == 'high') {
          // Create expansion risk zone (where deforestation might spread)
          final expansionRadius = math.sqrt(node.hectares / 100 / math.pi) + (riskThresholdKm * 0.5);
          final riskZone = _createCirclePolygon(node.lat, node.lng, expansionRadius);
          features.add({
            'type': 'Feature',
            'properties': {
              'id': '${node.id}-risk-zone',
              'name': '${node.headline} Risk Zone',
              'riskLevel': riskLevel,
              'expansionRadius': expansionRadius,
              'featureType': 'risk_expansion_zone',
              'color': _colorToHex(color.withValues(alpha: 0.3)),
            },
            'geometry': {
              'type': 'Polygon',
              'coordinates': [riskZone],
            },
          });
        }

        // Add point feature for the deforestation zone
        features.add({
          'type': 'Feature',
          'properties': {
            'id': node.id,
            'name': node.headline,
            'distance': distance,
            'riskLevel': riskLevel,
            'riskProbability': riskProbability,
            'hectares': node.hectares,
            'infrastructureType': infrastructureType,
            'featureType': 'risk_point',
            'color': _colorToHex(color),
          },
          'geometry': {
            'type': 'Point',
            'coordinates': [node.lng, node.lat],
          },
        });

        // Add distance line to infrastructure for high-risk zones
        if (riskLevel == 'very_high' || riskLevel == 'high') {
          // Create a line towards the infrastructure (simulated direction)
          final angle = (analyzedCount * 37.0 + node.lat * 10) % 360 * math.pi / 180;
          final endLat = node.lat + (distance / 111.32) * math.cos(angle);
          final endLng = node.lng + (distance / (111.32 * math.cos(node.lat * math.pi / 180))) * math.sin(angle);

          features.add({
            'type': 'Feature',
            'properties': {
              'id': '${node.id}-infra-line',
              'distanceKm': distance,
              'riskLevel': riskLevel,
              'featureType': 'infrastructure_proximity_line',
              'color': _colorToHex(color.withValues(alpha: 0.6)),
            },
            'geometry': {
              'type': 'LineString',
              'coordinates': [
                [node.lng, node.lat],
                [endLng, endLat],
              ],
            },
          });

          // Add infrastructure endpoint marker
          features.add({
            'type': 'Feature',
            'properties': {
              'id': '${node.id}-infra-point',
              'infrastructureType': infrastructureType,
              'featureType': 'infrastructure_point',
              'color': '#FFFFFF',
            },
            'geometry': {
              'type': 'Point',
              'coordinates': [endLng, endLat],
            },
          });
        }
      }
    }

    // Add expansion corridor lines between nearby high-risk zones
    int corridorCount = 0;
    for (int i = 0; i < highRiskNodes.length && i < 20; i++) {
      for (int j = i + 1; j < highRiskNodes.length && j < 20; j++) {
        final n1 = highRiskNodes[i];
        final n2 = highRiskNodes[j];

        final dist = SpatialStatistics.haversineDistance(
          n1['lat'] as double, n1['lng'] as double,
          n2['lat'] as double, n2['lng'] as double,
        );

        // Connect zones within 10km (potential expansion corridors)
        if (dist <= 10.0) {
          features.add({
            'type': 'Feature',
            'properties': {
              'id': 'corridor-$i-$j',
              'distanceKm': dist,
              'featureType': 'expansion_corridor',
              'color': _colorToHex(const Color(0xFFFF6B6B).withValues(alpha: 0.5)),
            },
            'geometry': {
              'type': 'LineString',
              'coordinates': [
                [n1['lng'], n1['lat']],
                [n2['lng'], n2['lat']],
              ],
            },
          });
          corridorCount++;
        }
      }
    }

    avgRiskProbability = analyzedCount > 0 ? avgRiskProbability / analyzedCount : 0;
    final avgDistance = analyzedCount > 0 ? totalDistance / analyzedCount : 0;

    stopwatch.stop();

    final typeLabel = _getInfrastructureLabel(infrastructureType);

    return SpatialAnalysisResult(
      type: SpatialAnalysisType.predictiveRiskMap,
      summary: {
        'thresholdKm': riskThresholdKm,
        'infrastructureType': infrastructureType,
        'veryHighRiskCount': veryHighRiskCount,
        'highRiskCount': highRiskCount,
        'moderateRiskCount': moderateRiskCount,
        'lowRiskCount': lowRiskCount,
        'totalAtRiskHectares': totalAtRiskHectares,
        'avgDistance': avgDistance,
        'minDistance': minDistance,
        'maxDistance': maxDistance,
        'corridorCount': corridorCount,
        'closestZone': closestZone,
        'closestZoneHectares': closestZoneHectares,
        'analysisDescription': 'Predicts future deforestation risk based on proximity to $typeLabel. Zones closer to infrastructure face higher risk of expansion.',
      },
      geoJson: {
        'type': 'FeatureCollection',
        'features': features,
      },
      statistics: [
        AnalysisStatistic(
          label: 'Critical Risk',
          value: '$veryHighRiskCount',
          unit: 'zones <${riskThresholdKm}km from $typeLabel',
          color: const Color(0xFFB30000),
          icon: Icons.warning_amber,
        ),
        AnalysisStatistic(
          label: 'High Risk',
          value: '$highRiskCount',
          unit: 'zones <${(riskThresholdKm * 2).toStringAsFixed(0)}km',
          color: const Color(0xFFFF3B3B),
          icon: Icons.priority_high,
        ),
        AnalysisStatistic(
          label: 'Moderate Risk',
          value: '$moderateRiskCount',
          unit: 'zones <${(riskThresholdKm * 5).toStringAsFixed(0)}km',
          color: const Color(0xFFFF8C00),
          icon: Icons.remove_circle_outline,
        ),
        AnalysisStatistic(
          label: 'At-Risk Forest',
          value: _numberFormat.format(totalAtRiskHectares.toInt()),
          unit: 'hectares threatened',
          color: Colors.deepOrange,
          icon: Icons.forest,
        ),
        AnalysisStatistic(
          label: 'Closest Zone',
          value: minDistance < double.infinity ? '${minDistance.toStringAsFixed(1)}' : 'N/A',
          unit: 'km (${_numberFormat.format(closestZoneHectares.toInt())}ha)',
          color: Colors.red,
          icon: Icons.gps_fixed,
        ),
        AnalysisStatistic(
          label: 'Avg Distance',
          value: '${avgDistance.toStringAsFixed(1)}',
          unit: 'km to $typeLabel',
          color: Colors.blue,
          icon: Icons.straighten,
        ),
        AnalysisStatistic(
          label: 'Avg Risk Score',
          value: '${(avgRiskProbability * 100).toStringAsFixed(0)}',
          unit: '% probability',
          color: Colors.orange,
          icon: Icons.speed,
        ),
        AnalysisStatistic(
          label: 'Expansion Corridors',
          value: '$corridorCount',
          unit: 'connected risk zones',
          color: Colors.purple,
          icon: Icons.timeline,
        ),
        AnalysisStatistic(
          label: 'Protected (Low Risk)',
          value: '$lowRiskCount',
          unit: 'zones >${(riskThresholdKm * 5).toStringAsFixed(0)}km',
          color: const Color(0xFF00E676),
          icon: Icons.shield,
        ),
      ],
      legend: [
        LegendItem(label: 'Critical Risk (<${riskThresholdKm}km to $typeLabel)', color: const Color(0xFFB30000)),
        LegendItem(label: 'High Risk (<${(riskThresholdKm * 2).toStringAsFixed(0)}km)', color: const Color(0xFFFF3B3B)),
        LegendItem(label: 'Moderate Risk (<${(riskThresholdKm * 5).toStringAsFixed(0)}km)', color: const Color(0xFFFF8C00)),
        LegendItem(label: 'Low Risk (>${(riskThresholdKm * 5).toStringAsFixed(0)}km)', color: const Color(0xFF00E676)),
        const LegendItem(label: 'Risk Expansion Zone', color: Color(0x4DB30000)),
        const LegendItem(label: 'Expansion Corridor', color: Color(0x80FF6B6B)),
        LegendItem(label: 'Distance to $typeLabel', color: Colors.white.withValues(alpha: 0.6)),
      ],
      timestamp: DateTime.now(),
      nodeCount: analyzedCount,
      processingTime: stopwatch.elapsed,
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // FRAGMENTATION ANALYSIS (Edge Effect & Forest Connectivity)
  // ═══════════════════════════════════════════════════════════════

  SpatialAnalysisResult runFragmentationAnalysis(
    List<IntelligenceNode> nodes,
    double minPatchSizeHa,
  ) {
    final stopwatch = Stopwatch()..start();

    final features = <Map<String, dynamic>>[];

    // Group nodes into patches based on proximity
    final patches = _identifyPatches(nodes, 5.0); // 5km clustering threshold

    int totalPatches = patches.length;
    int smallPatches = 0; // < minPatchSize
    int mediumPatches = 0; // minPatchSize - 1000ha
    int largePatches = 0; // > 1000ha
    int isolatedPatches = 0; // Single node patches
    double totalEdge = 0;
    double totalCoreArea = 0;
    double totalEdgeArea = 0;
    double avgFragmentationIndex = 0;
    double avgShapeIndex = 0;
    double maxPatchSize = 0;
    String largestPatchName = '';

    // Store patch centroids for connectivity analysis
    final patchCentroids = <Map<String, dynamic>>[];

    for (int i = 0; i < patches.length; i++) {
      final patch = patches[i];
      final patchHectares = patch.fold<double>(0, (sum, n) => sum + n.hectares);

      // Track largest patch
      if (patchHectares > maxPatchSize) {
        maxPatchSize = patchHectares;
        largestPatchName = patch.isNotEmpty
            ? (patch.first.headline.isNotEmpty ? patch.first.headline : patch.first.region)
            : 'Unknown';
      }

      // Track isolated patches
      if (patch.length == 1) {
        isolatedPatches++;
      }

      // Calculate patch centroid
      double centroidLat = 0, centroidLng = 0;
      for (final node in patch) {
        centroidLat += node.lat;
        centroidLng += node.lng;
      }
      centroidLat /= patch.length;
      centroidLng /= patch.length;

      // Calculate patch metrics
      final patchPerimeter = _estimatePatchPerimeter(patch);
      final patchArea = patchHectares;

      // Edge-to-Area Ratio (higher = more fragmented)
      final edgeToAreaRatio = patchArea > 0 ? patchPerimeter / patchArea : 0;

      // Shape Index: 1 = perfect circle, >1 = more complex/elongated
      // SI = Perimeter / (2 * sqrt(pi * Area))
      final shapeIndex = patchArea > 0
          ? patchPerimeter / (2 * math.sqrt(math.pi * patchArea * 10000)) // convert to m²
          : 1.0;
      avgShapeIndex += shapeIndex;

      // Core Area: Area beyond 100m edge buffer
      // Approximate: if edge is significant, reduce core
      final edgeDepth = 0.1; // km (100m edge effect)
      final coreArea = math.max(0, patchArea - (patchPerimeter * edgeDepth * 100));
      final edgeArea = patchArea - coreArea;
      totalCoreArea += coreArea;
      totalEdgeArea += edgeArea;

      // Fragmentation Index (0-100, higher = more fragmented)
      final fragmentationIndex = ((1 - (coreArea / (patchArea + 0.001))) * 100).clamp(0, 100);
      avgFragmentationIndex += fragmentationIndex;

      totalEdge += patchPerimeter;

      // Classify patch
      String patchClass;
      Color color;
      if (patchHectares < minPatchSizeHa) {
        patchClass = 'small';
        color = const Color(0xFFFF3B3B);
        smallPatches++;
      } else if (patchHectares < 1000) {
        patchClass = 'medium';
        color = const Color(0xFFFFB74D);
        mediumPatches++;
      } else {
        patchClass = 'large';
        color = const Color(0xFF00E676);
        largePatches++;
      }

      // Store centroid info for connectivity analysis
      patchCentroids.add({
        'index': i,
        'lat': centroidLat,
        'lng': centroidLng,
        'hectares': patchHectares,
        'color': color,
        'class': patchClass,
      });

      // Create patch boundary polygon if multiple nodes
      if (patch.length > 2) {
        final boundary = _createConvexHull(patch);
        features.add({
          'type': 'Feature',
          'properties': {
            'id': 'patch-$i-boundary',
            'patchId': i,
            'patchClass': patchClass,
            'patchHectares': patchHectares,
            'featureType': 'patch_boundary',
            'color': _colorToHex(color),
          },
          'geometry': {
            'type': 'Polygon',
            'coordinates': [boundary],
          },
        });
      } else if (patch.length == 1) {
        // For single node patches, create a small circle to represent the fragment
        final fragRadius = math.sqrt(patch.first.hectares / 100 / math.pi); // km
        final fragmentCircle = _createCirclePolygon(
          patch.first.lat,
          patch.first.lng,
          math.max(0.5, fragRadius), // At least 0.5km radius for visibility
        );
        features.add({
          'type': 'Feature',
          'properties': {
            'id': 'fragment-$i',
            'patchId': i,
            'patchClass': 'isolated_fragment',
            'patchHectares': patchHectares,
            'featureType': 'isolated_fragment',
            'color': _colorToHex(const Color(0xFFFF3B3B)),
          },
          'geometry': {
            'type': 'Polygon',
            'coordinates': [fragmentCircle],
          },
        });
      }

      // Add each node in patch with patch metrics (as center points)
      for (final node in patch) {
        features.add({
          'type': 'Feature',
          'properties': {
            'id': node.id,
            'name': node.headline,
            'patchId': i,
            'patchClass': patchClass,
            'patchHectares': patchHectares,
            'shapeIndex': shapeIndex,
            'edgeToAreaRatio': edgeToAreaRatio,
            'coreAreaHa': coreArea,
            'edgeAreaHa': edgeArea,
            'fragmentationIndex': fragmentationIndex,
            'featureType': 'patch_node',
            'color': _colorToHex(color),
          },
          'geometry': {
            'type': 'Point',
            'coordinates': [node.lng, node.lat],
          },
        });
      }

      // Add core area indicator for larger patches
      if (patchHectares >= minPatchSizeHa && coreArea > 0) {
        final coreRadius = math.sqrt(coreArea / 100 / math.pi) * 0.7; // Smaller than full patch
        if (coreRadius > 0.2) {
          final coreCircle = _createCirclePolygon(centroidLat, centroidLng, coreRadius);
          features.add({
            'type': 'Feature',
            'properties': {
              'id': 'core-$i',
              'patchId': i,
              'coreAreaHa': coreArea,
              'featureType': 'core_area',
              'color': _colorToHex(const Color(0xFF1B5E20)),
            },
            'geometry': {
              'type': 'Polygon',
              'coordinates': [coreCircle],
            },
          });
        }
      }
    }

    // Add connectivity lines between nearby patches (corridor potential)
    int connectivityLineCount = 0;
    for (int i = 0; i < patchCentroids.length; i++) {
      for (int j = i + 1; j < patchCentroids.length; j++) {
        final p1 = patchCentroids[i];
        final p2 = patchCentroids[j];

        final distance = SpatialStatistics.haversineDistance(
          p1['lat'] as double, p1['lng'] as double,
          p2['lat'] as double, p2['lng'] as double,
        );

        // Show connectivity potential for patches within 20km
        if (distance <= 20.0) {
          Color lineColor;
          String corridorType;
          if (distance <= 5.0) {
            lineColor = const Color(0xFF00E676);
            corridorType = 'strong_connectivity';
          } else if (distance <= 10.0) {
            lineColor = const Color(0xFFFFD700);
            corridorType = 'moderate_connectivity';
          } else {
            lineColor = const Color(0xFFFF8C00);
            corridorType = 'weak_connectivity';
          }

          features.add({
            'type': 'Feature',
            'properties': {
              'id': 'corridor-$i-$j',
              'distanceKm': distance,
              'corridorType': corridorType,
              'featureType': 'connectivity_corridor',
              'color': _colorToHex(lineColor),
            },
            'geometry': {
              'type': 'LineString',
              'coordinates': [
                [p1['lng'], p1['lat']],
                [p2['lng'], p2['lat']],
              ],
            },
          });
          connectivityLineCount++;
        }
      }
    }

    avgFragmentationIndex = patches.isNotEmpty ? avgFragmentationIndex / patches.length : 0;
    avgShapeIndex = patches.isNotEmpty ? avgShapeIndex / patches.length : 0;

    // Landscape Connectivity Index
    // Based on ratio of large patches to total and corridor density
    final corridorDensity = totalPatches > 1
        ? connectivityLineCount / (totalPatches * (totalPatches - 1) / 2) * 100
        : 0.0;
    final connectivityIndex = totalPatches > 0
        ? (((largePatches / totalPatches) * 50) + (corridorDensity * 0.5)).clamp(0, 100)
        : 0.0;

    stopwatch.stop();

    return SpatialAnalysisResult(
      type: SpatialAnalysisType.fragmentationAnalysis,
      summary: {
        'totalPatches': totalPatches,
        'smallPatches': smallPatches,
        'mediumPatches': mediumPatches,
        'largePatches': largePatches,
        'isolatedPatches': isolatedPatches,
        'avgFragmentationIndex': avgFragmentationIndex,
        'avgShapeIndex': avgShapeIndex,
        'totalCoreArea': totalCoreArea,
        'totalEdgeArea': totalEdgeArea,
        'totalEdge': totalEdge,
        'connectivityIndex': connectivityIndex,
        'maxPatchSize': maxPatchSize,
        'largestPatchName': largestPatchName,
        'analysisDescription': 'Analyzes forest fragmentation by grouping deforestation zones into patches, measuring edge effects, core habitat loss, and landscape connectivity.',
      },
      geoJson: {
        'type': 'FeatureCollection',
        'features': features,
      },
      statistics: [
        AnalysisStatistic(
          label: 'Total Patches',
          value: '$totalPatches',
          unit: 'forest fragments',
          color: Colors.blue,
          icon: Icons.dashboard,
        ),
        AnalysisStatistic(
          label: 'Small Fragments',
          value: '$smallPatches',
          unit: '<${minPatchSizeHa.toInt()}ha (vulnerable)',
          color: Colors.red,
          icon: Icons.broken_image,
        ),
        AnalysisStatistic(
          label: 'Isolated Patches',
          value: '$isolatedPatches',
          unit: 'single nodes',
          color: Colors.deepOrange,
          icon: Icons.do_not_disturb,
        ),
        AnalysisStatistic(
          label: 'Fragmentation Index',
          value: '${avgFragmentationIndex.toStringAsFixed(1)}',
          unit: '% (0=intact, 100=fragmented)',
          color: avgFragmentationIndex > 50 ? Colors.red : Colors.green,
          icon: Icons.pie_chart,
        ),
        AnalysisStatistic(
          label: 'Core Forest Area',
          value: _numberFormat.format(totalCoreArea.toInt()),
          unit: 'ha (protected interior)',
          color: const Color(0xFF1B5E20),
          icon: Icons.forest,
        ),
        AnalysisStatistic(
          label: 'Edge-Affected Area',
          value: _numberFormat.format(totalEdgeArea.toInt()),
          unit: 'ha (vulnerable)',
          color: Colors.orange,
          icon: Icons.border_outer,
        ),
        AnalysisStatistic(
          label: 'Connectivity',
          value: '${connectivityIndex.toStringAsFixed(1)}',
          unit: '% landscape connected',
          color: connectivityIndex > 50 ? Colors.green : Colors.orange,
          icon: Icons.hub,
        ),
        AnalysisStatistic(
          label: 'Shape Complexity',
          value: avgShapeIndex.toStringAsFixed(2),
          unit: '(1=circle, >2=complex)',
          color: Colors.purple,
          icon: Icons.shape_line,
        ),
        AnalysisStatistic(
          label: 'Large Intact Areas',
          value: '$largePatches',
          unit: '>1000ha',
          color: Colors.teal,
          icon: Icons.check_circle,
        ),
        AnalysisStatistic(
          label: 'Largest Patch',
          value: _numberFormat.format(maxPatchSize.toInt()),
          unit: 'ha ($largestPatchName)',
          color: Colors.green,
          icon: Icons.star,
        ),
      ],
      legend: [
        const LegendItem(label: 'Large Patch Boundary (>1000ha)', color: Color(0xFF00E676)),
        LegendItem(label: 'Medium Patch (${minPatchSizeHa.toInt()}-1000ha)', color: const Color(0xFFFFB74D)),
        LegendItem(label: 'Small Fragment (<${minPatchSizeHa.toInt()}ha)', color: const Color(0xFFFF3B3B)),
        const LegendItem(label: 'Core Forest Area (protected)', color: Color(0xFF1B5E20)),
        const LegendItem(label: 'Strong Connectivity (<5km)', color: Color(0xFF00E676)),
        const LegendItem(label: 'Moderate Connectivity (5-10km)', color: Color(0xFFFFD700)),
        const LegendItem(label: 'Weak Connectivity (10-20km)', color: Color(0xFFFF8C00)),
      ],
      timestamp: DateTime.now(),
      nodeCount: nodes.length,
      processingTime: stopwatch.elapsed,
    );
  }

  /// Group nodes into patches based on spatial proximity
  List<List<IntelligenceNode>> _identifyPatches(
    List<IntelligenceNode> nodes,
    double clusterThresholdKm,
  ) {
    final patches = <List<IntelligenceNode>>[];
    final assigned = <String>{};

    for (final node in nodes) {
      if (assigned.contains(node.id)) continue;

      // Start a new patch
      final patch = <IntelligenceNode>[node];
      assigned.add(node.id);

      // Find all connected nodes
      var frontier = [node];
      while (frontier.isNotEmpty) {
        final current = frontier.removeLast();

        for (final other in nodes) {
          if (assigned.contains(other.id)) continue;

          final distance = SpatialStatistics.haversineDistance(
            current.lat,
            current.lng,
            other.lat,
            other.lng,
          );

          if (distance <= clusterThresholdKm) {
            patch.add(other);
            assigned.add(other.id);
            frontier.add(other);
          }
        }
      }

      patches.add(patch);
    }

    return patches;
  }

  /// Estimate perimeter of a patch (km)
  double _estimatePatchPerimeter(List<IntelligenceNode> patch) {
    if (patch.isEmpty) return 0;
    if (patch.length == 1) {
      // Single node - estimate from hectares (circular approximation)
      final areaKm2 = patch[0].hectares / 100;
      return 2 * math.pi * math.sqrt(areaKm2 / math.pi);
    }

    // Calculate convex hull perimeter (simplified)
    // Find bounding box and use it as approximation
    double minLat = double.infinity, maxLat = -double.infinity;
    double minLng = double.infinity, maxLng = -double.infinity;

    for (final node in patch) {
      if (node.lat < minLat) minLat = node.lat;
      if (node.lat > maxLat) maxLat = node.lat;
      if (node.lng < minLng) minLng = node.lng;
      if (node.lng > maxLng) maxLng = node.lng;
    }

    // Calculate bounding box perimeter
    final width = SpatialStatistics.haversineDistance(minLat, minLng, minLat, maxLng);
    final height = SpatialStatistics.haversineDistance(minLat, minLng, maxLat, minLng);

    // Approximate convex hull perimeter as ~80% of bounding box
    return (2 * (width + height)) * 0.8;
  }

  /// Create a convex hull polygon from a list of nodes
  /// Uses Gift Wrapping algorithm (Jarvis march)
  List<List<double>> _createConvexHull(List<IntelligenceNode> nodes) {
    if (nodes.isEmpty) return [];
    if (nodes.length == 1) {
      // Return a small square for single point
      final n = nodes.first;
      return [
        [n.lng - 0.01, n.lat - 0.01],
        [n.lng + 0.01, n.lat - 0.01],
        [n.lng + 0.01, n.lat + 0.01],
        [n.lng - 0.01, n.lat + 0.01],
        [n.lng - 0.01, n.lat - 0.01],
      ];
    }
    if (nodes.length == 2) {
      // Return a thin rectangle for two points
      final n1 = nodes[0], n2 = nodes[1];
      final dx = (n2.lng - n1.lng) * 0.1;
      final dy = (n2.lat - n1.lat) * 0.1;
      return [
        [n1.lng - dy, n1.lat + dx],
        [n2.lng - dy, n2.lat + dx],
        [n2.lng + dy, n2.lat - dx],
        [n1.lng + dy, n1.lat - dx],
        [n1.lng - dy, n1.lat + dx],
      ];
    }

    // Find leftmost point
    var leftmost = nodes[0];
    for (final node in nodes) {
      if (node.lng < leftmost.lng ||
          (node.lng == leftmost.lng && node.lat < leftmost.lat)) {
        leftmost = node;
      }
    }

    final hull = <IntelligenceNode>[];
    var current = leftmost;

    do {
      hull.add(current);
      var next = nodes[0];

      for (final candidate in nodes) {
        if (next == current) {
          next = candidate;
          continue;
        }

        // Cross product to determine turn direction
        final cross = (next.lng - current.lng) * (candidate.lat - current.lat) -
            (next.lat - current.lat) * (candidate.lng - current.lng);

        if (cross < 0 ||
            (cross == 0 &&
                _distanceSq(current, candidate) > _distanceSq(current, next))) {
          next = candidate;
        }
      }

      current = next;
    } while (current != leftmost && hull.length < nodes.length);

    // Convert to coordinate list and close the polygon
    final coords = hull.map((n) => [n.lng, n.lat]).toList();
    if (coords.isNotEmpty) {
      coords.add(coords.first); // Close the polygon
    }

    return coords;
  }

  double _distanceSq(IntelligenceNode a, IntelligenceNode b) {
    final dx = a.lng - b.lng;
    final dy = a.lat - b.lat;
    return dx * dx + dy * dy;
  }

  // ═══════════════════════════════════════════════════════════════
  // UNIFIED RUN METHOD
  // ═══════════════════════════════════════════════════════════════

  Future<SpatialAnalysisResult> runAnalysis(
    SpatialAnalysisType type,
    List<IntelligenceNode> nodes,
    AnalysisConfig config,
  ) async {
    // Run on isolate for heavy calculations (would use compute() in production)
    switch (type) {
      case SpatialAnalysisType.changeDetection:
        return runChangeDetection(
          nodes,
          config.startYear ?? 2015,
          config.endYear ?? DateTime.now().year,
        );
      case SpatialAnalysisType.vegetationIndex:
        return runVegetationAnalysis(
          nodes,
          config.vegetationIndex ?? 'ndvi',
        );
      case SpatialAnalysisType.bufferAnalysis:
        return runBufferAnalysis(
          nodes,
          config.bufferDistanceKm ?? 5.0,
        );
      case SpatialAnalysisType.proximityAnalysis:
        return runProximityAnalysis(
          nodes,
          config.infrastructureType ?? 'roads',
        );
      case SpatialAnalysisType.hotspotAnalysis:
        return runHotspotAnalysis(
          nodes,
          config.bandwidthKm ?? 50.0,
        );
      case SpatialAnalysisType.patternAnalysis:
        return runPatternAnalysis(
          nodes,
          config.patternVariable ?? 'riskScore',
          config.bandwidthKm ?? 50.0,
        );
      case SpatialAnalysisType.riskModeling:
        return runRiskModeling(
          nodes,
          config.forecastYears ?? 5,
        );
      case SpatialAnalysisType.predictiveRiskMap:
        return runPredictiveRiskMap(
          nodes,
          config.riskThresholdKm ?? 2.0,
          config.infrastructureType ?? 'roads',
        );
      case SpatialAnalysisType.fragmentationAnalysis:
        return runFragmentationAnalysis(
          nodes,
          config.minPatchSizeHa ?? 100.0,
        );
    }
  }
}
