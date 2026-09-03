import 'dart:math';
import 'package:flutter/material.dart';
import 'package:ecolens/model/location_model.dart';
import 'package:ecolens/model/spatial_analysis_result.dart';

class GISEngine {
  final List<IntelligenceNode> nodes;

  GISEngine(this.nodes);

  /// Convert Color to hex string for GeoJSON properties
  static String _colorToHex(Color color) {
    final argb = color.toARGB32();
    // Extract RGB components (skip alpha)
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    return '#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}';
  }

  // ======================================================
  // 🔥 RISK HEATMAP SOURCE
  // ======================================================
  Map<String, dynamic> riskHeatmapSource() {
    return {
      "type": "FeatureCollection",
      "features": nodes.map((n) {
        return {
          "type": "Feature",
          "properties": {
            // Heatmaps REQUIRE numeric weights
            "risk": (n.riskScore.clamp(0, 100)) / 100.0,
          },
          "geometry": {
            "type": "Point",
            "coordinates": [n.lng, n.lat],
          },
        };
      }).toList(),
    };
  }

  // ======================================================
  // 🐾 SPECIES DENSITY (KERNEL INPUT)
  // ======================================================
  Map<String, dynamic> speciesDensitySource() {
    return {
      "type": "FeatureCollection",
      "features": nodes.expand((n) {
        // Each species increases density weight
        return n.speciesAtRisk.map((_) {
          return {
            "type": "Feature",
            "properties": {
              "density": 1.0,
            },
            "geometry": {
              "type": "Point",
              "coordinates": [n.lng, n.lat],
            },
          };
        });
      }).toList(),
    };
  }

  // ======================================================
  // 🔮 PREDICTIVE DEFORESTATION SPREAD
  // Radial forward projection (simple model)
  // ======================================================
  Map<String, dynamic> predictiveSpreadSource(double yearsForward) {
    return {
      "type": "FeatureCollection",
      "features": nodes.map((n) {
        // meters per year (risk-weighted)
        final metersPerYear = n.riskScore * 50.0;
        final spreadMeters = metersPerYear * yearsForward;

        // meters → degrees
        final deltaLng =
            spreadMeters / (111320 * cos(n.lat * pi / 180));

        return {
          "type": "Feature",
          "properties": {
            "risk": n.riskScore / 100.0,
          },
          "geometry": {
            "type": "Point",
            "coordinates": [n.lng + deltaLng, n.lat],
          },
        };
      }).toList(),
    };
  }

  // ======================================================
  // 🔥 FIRE / LOGGING PULSE ANIMATION
  // ======================================================
  Map<String, dynamic> pulseSource(double t) {
    return {
      "type": "FeatureCollection",
      "features": nodes.map((n) {
        final pulse = (sin(t) + 1) / 2; // normalize 0–1

        return {
          "type": "Feature",
          "properties": {
            "radius": 6 + pulse * 18, // px
            "opacity": 0.2 + pulse * 0.5,
          },
          "geometry": {
            "type": "Point",
            "coordinates": [n.lng, n.lat],
          },
        };
      }).toList(),
    };
  }

  // ======================================================
  // 📊 SPATIAL STATISTICS (HUD)
  // ======================================================
  Map<String, double> spatialStats() {
    if (nodes.isEmpty) {
      return {
        "total_hectares": 0,
        "avg_risk": 0,
      };
    }

    final totalHectares =
        nodes.fold<double>(0, (sum, n) => sum + n.hectares);

    final avgRisk =
        nodes.fold<double>(0, (sum, n) => sum + n.riskScore) /
            nodes.length;

    return {
      "total_hectares": totalHectares,
      "avg_risk": avgRisk,
    };
  }

  // ======================================================
  // 📈 CHANGE DETECTION SOURCE
  // Visualizes forest cover change between years
  // ======================================================
  Map<String, dynamic> changeDetectionSource(int startYear, int endYear) {
    return {
      "type": "FeatureCollection",
      "features": nodes.where((n) => n.yearlyHistory.isNotEmpty).map((n) {
        final startKey = startYear.toString();
        final endKey = endYear.toString();
        final startLoss = n.yearlyHistory[startKey] ?? 0.0;
        final endLoss = n.yearlyHistory[endKey] ?? 0.0;
        final totalChange = endLoss - startLoss;

        // Classify change magnitude
        String changeClass;
        Color color;
        if (totalChange > 1000) {
          changeClass = 'severe';
          color = const Color(0xFFB30000);
        } else if (totalChange > 500) {
          changeClass = 'high';
          color = const Color(0xFFFF0000);
        } else if (totalChange > 100) {
          changeClass = 'moderate';
          color = const Color(0xFFFF8C00);
        } else if (totalChange > 0) {
          changeClass = 'low';
          color = const Color(0xFFFFD700);
        } else {
          changeClass = 'stable';
          color = const Color(0xFF00E676);
        }

        return {
          "type": "Feature",
          "properties": {
            "id": n.id,
            "name": n.headline,
            "startYear": startYear,
            "endYear": endYear,
            "startLoss": startLoss,
            "endLoss": endLoss,
            "totalChange": totalChange,
            "changeClass": changeClass,
            "color": _colorToHex(color),
          },
          "geometry": {
            "type": "Point",
            "coordinates": [n.lng, n.lat],
          },
        };
      }).toList(),
    };
  }

  // ======================================================
  // 🌿 VEGETATION INDEX SOURCE (NDVI/EVI)
  // ======================================================
  Map<String, dynamic> vegetationIndexSource(String indexType) {
    return {
      "type": "FeatureCollection",
      "features": nodes.map((n) {
        double? value;
        if (indexType == 'ndvi') {
          value = n.currentNdvi;
        } else if (indexType == 'evi') {
          value = n.currentEvi;
        }

        // NDVI ranges from -1 to 1, typical healthy vegetation: 0.3-0.8
        final ndviValue = value ?? 0.0;

        // Classify vegetation health
        String healthClass;
        Color color;
        if (ndviValue >= 0.6) {
          healthClass = 'healthy';
          color = const Color(0xFF00E676);
        } else if (ndviValue >= 0.4) {
          healthClass = 'moderate';
          color = const Color(0xFF8BC34A);
        } else if (ndviValue >= 0.2) {
          healthClass = 'stressed';
          color = const Color(0xFFFFEB3B);
        } else if (ndviValue >= 0) {
          healthClass = 'sparse';
          color = const Color(0xFFFF9800);
        } else {
          healthClass = 'barren';
          color = const Color(0xFF795548);
        }

        return {
          "type": "Feature",
          "properties": {
            "id": n.id,
            "name": n.headline,
            "indexType": indexType.toUpperCase(),
            "value": ndviValue,
            "healthClass": healthClass,
            "change": n.ndviChange ?? 0.0,
            "color": _colorToHex(color),
          },
          "geometry": {
            "type": "Point",
            "coordinates": [n.lng, n.lat],
          },
        };
      }).toList(),
    };
  }

  // ======================================================
  // ⭕ BUFFER ANALYSIS SOURCE
  // Creates buffer zone polygons around nodes
  // ======================================================
  Map<String, dynamic> bufferAnalysisSource(double distanceKm) {
    return {
      "type": "FeatureCollection",
      "features": nodes.map((n) {
        // Create approximate circular buffer as polygon
        final bufferPoints = _createCirclePolygon(n.lat, n.lng, distanceKm, 32);

        // Get buffer area from GIS data if available
        double? bufferArea;
        if (distanceKm <= 1.5) {
          bufferArea = n.buffer1kmAreaHa;
        } else if (distanceKm <= 7.5) {
          bufferArea = n.buffer5kmAreaHa;
        } else {
          bufferArea = n.buffer10kmAreaHa;
        }

        return {
          "type": "Feature",
          "properties": {
            "id": n.id,
            "name": n.headline,
            "bufferKm": distanceKm,
            "bufferAreaHa": bufferArea ?? (pi * distanceKm * distanceKm * 100),
            "riskScore": n.riskScore,
            "hectares": n.hectares,
          },
          "geometry": {
            "type": "Polygon",
            "coordinates": [bufferPoints],
          },
        };
      }).toList(),
    };
  }

  /// Creates a circular polygon approximation
  List<List<double>> _createCirclePolygon(double lat, double lng, double radiusKm, int points) {
    final coords = <List<double>>[];
    final earthRadiusKm = 6371.0;

    for (int i = 0; i <= points; i++) {
      final angle = (2 * pi * i) / points;
      final dLat = (radiusKm / earthRadiusKm) * (180 / pi) * cos(angle);
      final dLng = (radiusKm / earthRadiusKm) * (180 / pi) * sin(angle) / cos(lat * pi / 180);
      coords.add([lng + dLng, lat + dLat]);
    }

    return coords;
  }

  // ======================================================
  // 📍 PROXIMITY ANALYSIS SOURCE
  // Shows distance to infrastructure
  // ======================================================
  Map<String, dynamic> proximityAnalysisSource(String infrastructureType) {
    return {
      "type": "FeatureCollection",
      "features": nodes.map((n) {
        double? distance;
        switch (infrastructureType) {
          case 'roads':
            distance = n.roadDistanceKm;
            break;
          case 'rivers':
            distance = n.riverDistanceKm;
            break;
          case 'settlements':
            distance = n.settlementDistanceKm;
            break;
          case 'protected':
            distance = n.protectedAreaDistanceKm;
            break;
          default:
            distance = n.roadDistanceKm;
        }

        final dist = distance ?? 999.0;

        // Classify vulnerability based on proximity
        String vulnerabilityClass;
        Color color;
        if (dist < 1) {
          vulnerabilityClass = 'critical';
          color = const Color(0xFFB30000);
        } else if (dist < 5) {
          vulnerabilityClass = 'high';
          color = const Color(0xFFFF5722);
        } else if (dist < 10) {
          vulnerabilityClass = 'moderate';
          color = const Color(0xFFFFB74D);
        } else if (dist < 20) {
          vulnerabilityClass = 'low';
          color = const Color(0xFF4CAF50);
        } else {
          vulnerabilityClass = 'minimal';
          color = const Color(0xFF2E7D32);
        }

        return {
          "type": "Feature",
          "properties": {
            "id": n.id,
            "name": n.headline,
            "infrastructureType": infrastructureType,
            "distanceKm": dist,
            "vulnerabilityClass": vulnerabilityClass,
            "riskScore": n.riskScore,
            "color": _colorToHex(color),
          },
          "geometry": {
            "type": "Point",
            "coordinates": [n.lng, n.lat],
          },
        };
      }).toList(),
    };
  }

  // ======================================================
  // 🔥 HOTSPOT ANALYSIS SOURCE (Getis-Ord Gi*)
  // ======================================================
  Map<String, dynamic> hotspotAnalysisSource(List<HotspotResult> results) {
    return {
      "type": "FeatureCollection",
      "features": results.map((r) {
        return {
          "type": "Feature",
          "properties": {
            "id": r.nodeId,
            "giStar": r.giStar,
            "zScore": r.zScore,
            "pValue": r.pValue,
            "classification": r.classification.label,
            "color": _colorToHex(r.classification.color),
          },
          "geometry": {
            "type": "Point",
            "coordinates": [r.lng, r.lat],
          },
        };
      }).toList(),
    };
  }

  // ======================================================
  // 🗺️ PATTERN ANALYSIS SOURCE (LISA/Moran's I)
  // ======================================================
  Map<String, dynamic> patternAnalysisSource(List<LISAResult> results) {
    return {
      "type": "FeatureCollection",
      "features": results.map((r) {
        return {
          "type": "Feature",
          "properties": {
            "id": r.nodeId,
            "localI": r.localI,
            "zScore": r.zScore,
            "pValue": r.pValue,
            "quadrant": r.quadrant.label,
            "color": _colorToHex(r.quadrant.color),
          },
          "geometry": {
            "type": "Point",
            "coordinates": [r.lng, r.lat],
          },
        };
      }).toList(),
    };
  }

  // ======================================================
  // ⚠️ PREDICTIVE RISK MAP SOURCE
  // Identifies high-risk zones based on proximity patterns
  // ======================================================
  Map<String, dynamic> predictiveRiskMapSource(double riskThresholdKm, String infrastructureType) {
    return {
      "type": "FeatureCollection",
      "features": nodes.map((n) {
        double? distance;
        switch (infrastructureType) {
          case 'roads':
            distance = n.roadDistanceKm;
            break;
          case 'rivers':
            distance = n.riverDistanceKm;
            break;
          case 'settlements':
            distance = n.settlementDistanceKm;
            break;
          default:
            distance = n.roadDistanceKm;
        }

        final dist = distance ?? 999.0;
        final isHighRisk = dist <= riskThresholdKm;

        // Calculate risk probability based on distance
        double riskProbability;
        String riskClass;
        Color color;

        if (dist <= riskThresholdKm * 0.5) {
          riskProbability = 0.9;
          riskClass = 'very_high';
          color = const Color(0xFFB30000);
        } else if (dist <= riskThresholdKm) {
          riskProbability = 0.75;
          riskClass = 'high';
          color = const Color(0xFFFF5722);
        } else if (dist <= riskThresholdKm * 2) {
          riskProbability = 0.5;
          riskClass = 'moderate';
          color = const Color(0xFFFFB74D);
        } else if (dist <= riskThresholdKm * 4) {
          riskProbability = 0.25;
          riskClass = 'low';
          color = const Color(0xFF4CAF50);
        } else {
          riskProbability = 0.1;
          riskClass = 'minimal';
          color = const Color(0xFF2E7D32);
        }

        return {
          "type": "Feature",
          "properties": {
            "id": n.id,
            "name": n.headline,
            "distanceKm": dist,
            "thresholdKm": riskThresholdKm,
            "isHighRisk": isHighRisk,
            "riskProbability": riskProbability,
            "riskClass": riskClass,
            "infrastructureType": infrastructureType,
            "currentRiskScore": n.riskScore,
            "color": _colorToHex(color),
          },
          "geometry": {
            "type": "Point",
            "coordinates": [n.lng, n.lat],
          },
        };
      }).toList(),
    };
  }

  // ======================================================
  // 🧩 FRAGMENTATION ANALYSIS SOURCE
  // Visualizes forest patches and edge effects
  // ======================================================
  Map<String, dynamic> fragmentationAnalysisSource({
    required List<Map<String, dynamic>> patches,
    double minPatchSizeHa = 100.0,
  }) {
    final features = <Map<String, dynamic>>[];

    for (final patch in patches) {
      final patchNodes = patch['nodes'] as List<IntelligenceNode>? ?? [];
      final patchArea = patch['area'] as double? ?? 0.0;
      final edgeRatio = patch['edgeRatio'] as double? ?? 0.0;
      final shapeIndex = patch['shapeIndex'] as double? ?? 1.0;
      final coreArea = patch['coreArea'] as double? ?? 0.0;

      // Classify fragmentation severity
      String fragmentClass;
      Color color;

      if (patchArea < minPatchSizeHa * 0.5) {
        fragmentClass = 'critical';
        color = const Color(0xFFB30000);
      } else if (edgeRatio > 0.8) {
        fragmentClass = 'severe';
        color = const Color(0xFFFF5722);
      } else if (edgeRatio > 0.5) {
        fragmentClass = 'moderate';
        color = const Color(0xFFFFB74D);
      } else if (shapeIndex > 2.0) {
        fragmentClass = 'irregular';
        color = const Color(0xFF9C27B0);
      } else {
        fragmentClass = 'intact';
        color = const Color(0xFF00BCD4);
      }

      // Create polygon from patch nodes (convex hull approximation)
      if (patchNodes.length >= 3) {
        final hullPoints = _convexHull(patchNodes);
        features.add({
          "type": "Feature",
          "properties": {
            "patchId": patch['id'] ?? features.length,
            "nodeCount": patchNodes.length,
            "areaHa": patchArea,
            "edgeRatio": edgeRatio,
            "shapeIndex": shapeIndex,
            "coreAreaHa": coreArea,
            "fragmentClass": fragmentClass,
            "color": _colorToHex(color),
          },
          "geometry": {
            "type": "Polygon",
            "coordinates": [hullPoints],
          },
        });
      } else {
        // Single or pair of nodes - show as points
        for (final node in patchNodes) {
          features.add({
            "type": "Feature",
            "properties": {
              "patchId": patch['id'] ?? features.length,
              "nodeCount": patchNodes.length,
              "areaHa": patchArea,
              "edgeRatio": edgeRatio,
              "shapeIndex": shapeIndex,
              "coreAreaHa": coreArea,
              "fragmentClass": fragmentClass,
              "color": _colorToHex(color),
            },
            "geometry": {
              "type": "Point",
              "coordinates": [node.lng, node.lat],
            },
          });
        }
      }
    }

    return {
      "type": "FeatureCollection",
      "features": features,
    };
  }

  /// Compute convex hull of nodes using Graham scan
  List<List<double>> _convexHull(List<IntelligenceNode> nodes) {
    if (nodes.length < 3) {
      return nodes.map((n) => [n.lng, n.lat]).toList();
    }

    // Find lowest point
    var lowest = nodes[0];
    for (final n in nodes) {
      if (n.lat < lowest.lat || (n.lat == lowest.lat && n.lng < lowest.lng)) {
        lowest = n;
      }
    }

    // Sort by polar angle
    final sorted = List<IntelligenceNode>.from(nodes)
      ..sort((a, b) {
        final angleA = atan2(a.lat - lowest.lat, a.lng - lowest.lng);
        final angleB = atan2(b.lat - lowest.lat, b.lng - lowest.lng);
        return angleA.compareTo(angleB);
      });

    // Graham scan
    final hull = <IntelligenceNode>[];
    for (final p in sorted) {
      while (hull.length >= 2 && _cross(hull[hull.length - 2], hull.last, p) <= 0) {
        hull.removeLast();
      }
      hull.add(p);
    }

    // Close the polygon
    final coords = hull.map((n) => [n.lng, n.lat]).toList();
    if (coords.isNotEmpty) {
      coords.add(coords.first);
    }

    return coords;
  }

  /// Cross product for convex hull
  double _cross(IntelligenceNode o, IntelligenceNode a, IntelligenceNode b) {
    return (a.lng - o.lng) * (b.lat - o.lat) - (a.lat - o.lat) * (b.lng - o.lng);
  }

  // ======================================================
  // 📊 RISK MODELING SOURCE (Trend-based prediction)
  // ======================================================
  Map<String, dynamic> riskModelingSource(int forecastYears) {
    return {
      "type": "FeatureCollection",
      "features": nodes.map((n) {
        // Calculate projected risk based on trends
        final currentRisk = n.riskScore;
        final trendPercent = n.trendChangePercent;
        final projectedRisk = (currentRisk + (trendPercent * forecastYears / 100) * currentRisk).clamp(0, 100);

        // Classify trend
        String trendClass;
        Color color;

        if (n.trendDirection == 'INCREASING' && trendPercent > 10) {
          trendClass = 'accelerating';
          color = const Color(0xFFB30000);
        } else if (n.trendDirection == 'INCREASING') {
          trendClass = 'worsening';
          color = const Color(0xFFFF5722);
        } else if (n.trendDirection == 'STABLE') {
          trendClass = 'stable';
          color = const Color(0xFFFFB74D);
        } else if (n.trendDirection == 'DECREASING') {
          trendClass = 'improving';
          color = const Color(0xFF4CAF50);
        } else {
          trendClass = 'unknown';
          color = const Color(0xFF9E9E9E);
        }

        return {
          "type": "Feature",
          "properties": {
            "id": n.id,
            "name": n.headline,
            "currentRisk": currentRisk,
            "projectedRisk": projectedRisk,
            "forecastYears": forecastYears,
            "trendDirection": n.trendDirection,
            "trendPercent": trendPercent,
            "trendClass": trendClass,
            "forecast2026": n.forecast2026,
            "color": _colorToHex(color),
          },
          "geometry": {
            "type": "Point",
            "coordinates": [n.lng, n.lat],
          },
        };
      }).toList(),
    };
  }
}
