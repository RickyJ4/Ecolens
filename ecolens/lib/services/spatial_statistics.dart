import 'dart:math' as math;
import 'package:ecolens/model/spatial_analysis_result.dart';

/// Statistical functions for spatial analysis
/// Implements Getis-Ord Gi*, Moran's I, and spatial weights calculations
class SpatialStatistics {
  /// Calculate Haversine distance between two points in kilometers
  static double haversineDistance(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const double earthRadiusKm = 6371.0;
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180;

  /// Build a distance-based spatial weights matrix
  /// Returns a 2D matrix where W[i][j] = 1 if distance <= bandwidth, else 0
  static List<List<double>> distanceWeightsMatrix(
    List<Map<String, dynamic>> points,
    double bandwidthKm, {
    bool rowStandardize = true,
  }) {
    final n = points.length;
    final weights = List.generate(n, (_) => List.filled(n, 0.0));

    for (int i = 0; i < n; i++) {
      double rowSum = 0;
      for (int j = 0; j < n; j++) {
        if (i == j) continue;

        final dist = haversineDistance(
          points[i]['lat'] as double,
          points[i]['lng'] as double,
          points[j]['lat'] as double,
          points[j]['lng'] as double,
        );

        if (dist <= bandwidthKm) {
          weights[i][j] = 1.0;
          rowSum += 1.0;
        }
      }

      // Row-standardize if requested
      if (rowStandardize && rowSum > 0) {
        for (int j = 0; j < n; j++) {
          weights[i][j] /= rowSum;
        }
      }
    }

    return weights;
  }

  /// Build inverse distance weights matrix
  /// W[i][j] = 1/distance if within bandwidth
  static List<List<double>> inverseDistanceWeightsMatrix(
    List<Map<String, dynamic>> points,
    double bandwidthKm, {
    bool rowStandardize = true,
    double power = 1.0,
  }) {
    final n = points.length;
    final weights = List.generate(n, (_) => List.filled(n, 0.0));

    for (int i = 0; i < n; i++) {
      double rowSum = 0;
      for (int j = 0; j < n; j++) {
        if (i == j) continue;

        final dist = haversineDistance(
          points[i]['lat'] as double,
          points[i]['lng'] as double,
          points[j]['lat'] as double,
          points[j]['lng'] as double,
        );

        if (dist > 0 && dist <= bandwidthKm) {
          final weight = 1.0 / math.pow(dist, power);
          weights[i][j] = weight;
          rowSum += weight;
        }
      }

      if (rowStandardize && rowSum > 0) {
        for (int j = 0; j < n; j++) {
          weights[i][j] /= rowSum;
        }
      }
    }

    return weights;
  }

  /// Calculate Getis-Ord Gi* statistic for hotspot analysis
  /// Returns a map of point indices to their Gi* z-scores
  static List<HotspotResult> getisOrdGiStar(
    List<Map<String, dynamic>> points,
    String valueField,
    double bandwidthKm,
  ) {
    final n = points.length;
    if (n < 3) return [];

    // Extract values
    final values = points.map((p) => (p[valueField] as num).toDouble()).toList();

    // Calculate global statistics
    final mean = values.reduce((a, b) => a + b) / n;
    final variance = values.map((v) => math.pow(v - mean, 2)).reduce((a, b) => a + b) / n;
    final stdDev = math.sqrt(variance);

    if (stdDev == 0) {
      // All values are the same - no variation
      return points.asMap().entries.map((e) {
        return HotspotResult(
          nodeId: e.value['id']?.toString() ?? e.key.toString(),
          lat: e.value['lat'] as double,
          lng: e.value['lng'] as double,
          giStar: 0,
          zScore: 0,
          pValue: 1.0,
          classification: HotspotClassification.notSignificant,
        );
      }).toList();
    }

    // Build weights matrix (not row-standardized for Gi*)
    final weights = distanceWeightsMatrix(points, bandwidthKm, rowStandardize: false);

    final results = <HotspotResult>[];

    for (int i = 0; i < n; i++) {
      // Calculate sum of weights for this point
      double sumW = 0;
      double sumW2 = 0;
      double numerator = 0;

      for (int j = 0; j < n; j++) {
        final w = weights[i][j];
        sumW += w;
        sumW2 += w * w;
        numerator += w * values[j];
      }

      // Gi* numerator: sum of weighted values minus expected
      final expectedNumerator = mean * sumW;
      final giNumerator = numerator - expectedNumerator;

      // Standard error
      final s = stdDev;
      final nDouble = n.toDouble();
      final denominator = s * math.sqrt(
        (nDouble * sumW2 - sumW * sumW) / (nDouble - 1),
      );

      double zScore = 0;
      if (denominator > 0) {
        zScore = giNumerator / denominator;
      }

      // Calculate p-value (two-tailed)
      final pValue = 2 * (1 - _normalCDF(zScore.abs()));

      // Classify based on z-score
      HotspotClassification classification;
      if (zScore > 2.58) {
        classification = HotspotClassification.hotspot99;
      } else if (zScore > 1.96) {
        classification = HotspotClassification.hotspot95;
      } else if (zScore > 1.65) {
        classification = HotspotClassification.hotspot90;
      } else if (zScore < -2.58) {
        classification = HotspotClassification.coldspot99;
      } else if (zScore < -1.96) {
        classification = HotspotClassification.coldspot95;
      } else if (zScore < -1.65) {
        classification = HotspotClassification.coldspot90;
      } else {
        classification = HotspotClassification.notSignificant;
      }

      results.add(HotspotResult(
        nodeId: points[i]['id']?.toString() ?? i.toString(),
        lat: points[i]['lat'] as double,
        lng: points[i]['lng'] as double,
        giStar: numerator / (sumW > 0 ? sumW : 1),
        zScore: zScore,
        pValue: pValue,
        classification: classification,
      ));
    }

    return results;
  }

  /// Calculate Global Moran's I statistic
  static MoransIResult globalMoransI(
    List<Map<String, dynamic>> points,
    String valueField,
    double bandwidthKm,
  ) {
    final n = points.length;

    if (n < 3) {
      return const MoransIResult(
        moransI: 0,
        expectedI: 0,
        variance: 0,
        zScore: 0,
        pValue: 1,
        pattern: SpatialPattern.random,
      );
    }

    // Extract values
    final values = points.map((p) => (p[valueField] as num).toDouble()).toList();

    // Calculate mean
    final mean = values.reduce((a, b) => a + b) / n;

    // Calculate deviations from mean
    final deviations = values.map((v) => v - mean).toList();

    // Build weights matrix
    final weights = distanceWeightsMatrix(points, bandwidthKm, rowStandardize: false);

    // Calculate sum of weights
    double sumW = 0;
    for (int i = 0; i < n; i++) {
      for (int j = 0; j < n; j++) {
        sumW += weights[i][j];
      }
    }

    if (sumW == 0) {
      return const MoransIResult(
        moransI: 0,
        expectedI: 0,
        variance: 0,
        zScore: 0,
        pValue: 1,
        pattern: SpatialPattern.random,
      );
    }

    // Calculate numerator (spatial covariance)
    double numerator = 0;
    for (int i = 0; i < n; i++) {
      for (int j = 0; j < n; j++) {
        numerator += weights[i][j] * deviations[i] * deviations[j];
      }
    }

    // Calculate denominator (variance)
    final sumSquaredDeviations = deviations.map((d) => d * d).reduce((a, b) => a + b);

    // Moran's I
    final moransI = (n / sumW) * (numerator / sumSquaredDeviations);

    // Expected value under null hypothesis
    final expectedI = -1.0 / (n - 1);

    // Variance calculation (simplified - assumes normality)
    final nDouble = n.toDouble();

    // Calculate S0, S1, S2 for variance
    double s0 = sumW;
    double s1 = 0;
    double s2 = 0;

    for (int i = 0; i < n; i++) {
      double rowSum = 0;
      double colSum = 0;
      for (int j = 0; j < n; j++) {
        s1 += math.pow(weights[i][j] + weights[j][i], 2);
        rowSum += weights[i][j];
        colSum += weights[j][i];
      }
      s2 += math.pow(rowSum + colSum, 2);
    }
    s1 /= 2;

    // Variance under normality assumption
    final variance = (nDouble * ((nDouble * nDouble - 3 * nDouble + 3) * s1 -
            nDouble * s2 +
            3 * s0 * s0) -
        (nDouble * nDouble - nDouble) * s1 -
        2 * nDouble * s2 +
        6 * s0 * s0) /
        ((nDouble - 1) * (nDouble - 2) * (nDouble - 3) * s0 * s0);

    final zScore = (moransI - expectedI) / math.sqrt(variance.abs());
    final pValue = 2 * (1 - _normalCDF(zScore.abs()));

    // Determine pattern
    SpatialPattern pattern;
    if (pValue > 0.05) {
      pattern = SpatialPattern.random;
    } else if (moransI > expectedI) {
      pattern = SpatialPattern.clustered;
    } else {
      pattern = SpatialPattern.dispersed;
    }

    return MoransIResult(
      moransI: moransI,
      expectedI: expectedI,
      variance: variance,
      zScore: zScore,
      pValue: pValue,
      pattern: pattern,
    );
  }

  /// Calculate Local Moran's I (LISA) for each point
  static List<LISAResult> localMoransI(
    List<Map<String, dynamic>> points,
    String valueField,
    double bandwidthKm,
  ) {
    final n = points.length;
    if (n < 3) return [];

    // Extract values
    final values = points.map((p) => (p[valueField] as num).toDouble()).toList();

    // Calculate mean and standard deviation
    final mean = values.reduce((a, b) => a + b) / n;
    final variance = values.map((v) => math.pow(v - mean, 2)).reduce((a, b) => a + b) / n;
    final stdDev = math.sqrt(variance);

    if (stdDev == 0) {
      return points.asMap().entries.map((e) {
        return LISAResult(
          nodeId: e.value['id']?.toString() ?? e.key.toString(),
          lat: e.value['lat'] as double,
          lng: e.value['lng'] as double,
          localI: 0,
          zScore: 0,
          pValue: 1,
          quadrant: LISAQuadrant.notSignificant,
        );
      }).toList();
    }

    // Standardize values (z-scores)
    final zValues = values.map((v) => (v - mean) / stdDev).toList();

    // Build row-standardized weights matrix
    final weights = distanceWeightsMatrix(points, bandwidthKm, rowStandardize: true);

    final results = <LISAResult>[];

    for (int i = 0; i < n; i++) {
      // Calculate spatial lag (weighted average of neighbors)
      double spatialLag = 0;
      for (int j = 0; j < n; j++) {
        spatialLag += weights[i][j] * zValues[j];
      }

      // Local Moran's I = z_i * lag_i
      final localI = zValues[i] * spatialLag;

      // Simplified variance and z-score calculation
      double sumW2 = 0;
      for (int j = 0; j < n; j++) {
        sumW2 += weights[i][j] * weights[i][j];
      }

      // Approximate z-score
      final zScore = localI / math.sqrt(sumW2 > 0 ? sumW2 : 1);
      final pValue = 2 * (1 - _normalCDF(zScore.abs()));

      // Determine quadrant
      LISAQuadrant quadrant;
      if (pValue > 0.05) {
        quadrant = LISAQuadrant.notSignificant;
      } else if (zValues[i] > 0 && spatialLag > 0) {
        quadrant = LISAQuadrant.highHigh;
      } else if (zValues[i] < 0 && spatialLag < 0) {
        quadrant = LISAQuadrant.lowLow;
      } else if (zValues[i] > 0 && spatialLag < 0) {
        quadrant = LISAQuadrant.highLow;
      } else {
        quadrant = LISAQuadrant.lowHigh;
      }

      results.add(LISAResult(
        nodeId: points[i]['id']?.toString() ?? i.toString(),
        lat: points[i]['lat'] as double,
        lng: points[i]['lng'] as double,
        localI: localI,
        zScore: zScore,
        pValue: pValue,
        quadrant: quadrant,
      ));
    }

    return results;
  }

  /// Approximate cumulative distribution function for standard normal
  static double _normalCDF(double z) {
    // Approximation using error function
    final a1 = 0.254829592;
    final a2 = -0.284496736;
    final a3 = 1.421413741;
    final a4 = -1.453152027;
    final a5 = 1.061405429;
    final p = 0.3275911;

    final sign = z < 0 ? -1 : 1;
    z = z.abs() / math.sqrt(2);

    final t = 1.0 / (1.0 + p * z);
    final y = 1.0 -
        (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * math.exp(-z * z);

    return 0.5 * (1.0 + sign * y);
  }

  /// Calculate K-Nearest Neighbors weights matrix
  static List<List<double>> knnWeightsMatrix(
    List<Map<String, dynamic>> points,
    int k, {
    bool rowStandardize = true,
  }) {
    final n = points.length;
    final weights = List.generate(n, (_) => List.filled(n, 0.0));

    for (int i = 0; i < n; i++) {
      // Calculate distances to all other points
      final distances = <int, double>{};
      for (int j = 0; j < n; j++) {
        if (i == j) continue;
        distances[j] = haversineDistance(
          points[i]['lat'] as double,
          points[i]['lng'] as double,
          points[j]['lat'] as double,
          points[j]['lng'] as double,
        );
      }

      // Sort by distance and take k nearest
      final sortedNeighbors = distances.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));

      final kNeighbors = sortedNeighbors.take(k.clamp(1, n - 1));

      for (final neighbor in kNeighbors) {
        weights[i][neighbor.key] = 1.0;
      }

      // Row-standardize
      if (rowStandardize) {
        final rowSum = kNeighbors.length.toDouble();
        if (rowSum > 0) {
          for (final neighbor in kNeighbors) {
            weights[i][neighbor.key] = 1.0 / rowSum;
          }
        }
      }
    }

    return weights;
  }
}
