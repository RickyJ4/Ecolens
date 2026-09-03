import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

/// Service for calling the new EcoLens mobile feature Cloud Functions:
/// - analyze_restoration_potential
/// - calculate_carbon_credits
/// - Firestore subscription to live_deforestation_alerts
class EcoLensApiService {
  final _functions = FirebaseFunctions.instance;

  // ═══════════════════════════════════════════════════════════════
  // Feature #3: Restoration Success Predictor
  // ═══════════════════════════════════════════════════════════════

  /// Analyzes restoration potential for a degraded land parcel
  ///
  /// Parameters:
  /// - [photoUrl]: Cloud Storage URL of uploaded photo
  /// - [lat]: Latitude
  /// - [lng]: Longitude
  ///
  /// Returns restoration assessment with success probability, costs, carbon value
  Future<Map<String, dynamic>> analyzeRestorationPotential({
    required String photoUrl,
    required double lat,
    required double lng,
  }) async {
    try {
      debugPrint("🌱 Calling analyze_restoration_potential...");

      final result = await _functions
          .httpsCallable(
            'analyze_restoration_potential',
            options: HttpsCallableOptions(
              timeout: const Duration(seconds: 540), // 9 minutes max
            ),
          )
          .call({'photo_url': photoUrl, 'lat': lat, 'lng': lng});

      final data = result.data as Map<String, dynamic>;
      debugPrint("✅ Restoration analysis complete");
      return data;
    } catch (e) {
      debugPrint("❌ Restoration analysis failed: $e");
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Feature #4: Carbon Credit Calculator
  // ═══════════════════════════════════════════════════════════════

  /// Calculates carbon credit value for a land parcel
  ///
  /// Parameters:
  /// - [boundaryPoints]: List of GPS coordinates defining the polygon
  ///
  /// Returns carbon stock/potential, market value, ROI projections
  Future<Map<String, dynamic>> calculateCarbonCredits({
    required List<Map<String, double>> boundaryPoints,
    double? areaHectares,
  }) async {
    try {
      debugPrint(
        "💰 Calling calculate_carbon_credits with ${boundaryPoints.length} points...",
      );

      final result = await _functions
          .httpsCallable(
            'calculate_carbon_credits',
            options: HttpsCallableOptions(
              timeout: const Duration(seconds: 300), // 5 minutes max
            ),
          )
          .call({
            'boundary_points': boundaryPoints,
            if (areaHectares != null) 'area_hectares': areaHectares,
          });

      final data = result.data as Map<String, dynamic>;
      debugPrint("✅ Carbon calculation complete");
      return data;
    } catch (e) {
      debugPrint("❌ Carbon calculation failed: $e");
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Helper: Format error messages for UI display
  // ═══════════════════════════════════════════════════════════════

  String getErrorMessage(dynamic error) {
    if (error is FirebaseFunctionsException) {
      switch (error.code) {
        case 'unavailable':
          return 'Service temporarily unavailable. Please try again later.';
        case 'deadline-exceeded':
          return 'Request timed out. The analysis may be too complex.';
        case 'invalid-argument':
          return 'Invalid input provided. Please check your data.';
        case 'permission-denied':
          return 'Permission denied. Please ensure you are logged in.';
        case 'unauthenticated':
          return 'Please sign in to use this feature.';
        default:
          return 'An error occurred: ${error.message}';
      }
    }
    return error.toString();
  }
}
