import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:ecolens/model/cartographic_intelligence_models.dart';

/// Service for calling the Cartographic Intelligence Engine.
///
/// Supports two modes:
/// - **Direct HTTP**: Calls the Docker server directly (for local dev/demo)
/// - **Cloud Functions**: Calls Firebase httpsCallable (for production)
///
/// Set [useDirectHttp] to true for local demo with Docker server.
class CartographicIntelligenceService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// Set to true to call the local Docker server directly
  /// instead of going through Firebase Cloud Functions.
  /// For demo: Docker server runs on localhost:8080
  static const bool useDirectHttp = true;
  static const String directUrl = 'http://127.0.0.1:8080';

  /// Generate a publication-quality cartographic map.
  Future<CartographicMapResult> generateMap(
    CartographicMapRequest request,
  ) async {
    if (useDirectHttp) {
      return _generateViaHttp(request);
    }
    return _generateViaCloudFunction(request);
  }

  /// Direct HTTP call to the Docker QGIS server.
  Future<CartographicMapResult> _generateViaHttp(
    CartographicMapRequest request,
  ) async {
    try {
      final url = '$directUrl/generate';
      debugPrint("🗺️ POST $url");
      debugPrint("🗺️ Request: ${request.mapType} | ${request.theme} | bbox=${request.bbox}");

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(request.toJson()),
      ).timeout(const Duration(seconds: 300));

      debugPrint("🗺️ Response: ${response.statusCode} (${response.body.length} bytes)");

      if (response.statusCode != 200) {
        throw Exception('Server error ${response.statusCode}: ${response.body.substring(0, 200)}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      debugPrint("✅ Map generated: quality=${data['quality_report']?['overall']}/100, "
          "renderer=${data['metadata']?['renderer']}");

      return CartographicMapResult.fromJson(data);
    } catch (e, stack) {
      debugPrint("❌ Map generation failed: $e");
      debugPrint("❌ Stack: $stack");
      rethrow;
    }
  }

  /// Firebase Cloud Functions call (production mode).
  Future<CartographicMapResult> _generateViaCloudFunction(
    CartographicMapRequest request,
  ) async {
    try {
      debugPrint("🗺️ Generating map via Cloud Function: ${request.mapType} | ${request.theme}");

      final result = await _functions
          .httpsCallable(
            'generate_cartographic_map',
            options: HttpsCallableOptions(
              timeout: const Duration(seconds: 540),
            ),
          )
          .call(request.toJson());

      final data = result.data as Map<String, dynamic>;
      debugPrint("✅ Map generated: quality=${data['quality_report']?['overall']}/100");

      return CartographicMapResult.fromJson(data);
    } catch (e) {
      debugPrint("❌ Map generation failed: $e");
      rethrow;
    }
  }

  /// Generate a showcase example map by ID.
  Future<CartographicMapResult> generateShowcase(String showcaseId) async {
    return generateMap(CartographicMapRequest(
      bbox: const [0, 0, 0, 0],
      showcaseId: showcaseId,
    ));
  }

  /// Get the full catalog of templates, palettes, data sources, and showcases.
  Future<CartographicCatalog> getCatalog({
    List<double>? bbox,
    String? theme,
  }) async {
    if (useDirectHttp) {
      try {
        debugPrint("📋 Loading catalog via HTTP...");
        final response = await http.get(
          Uri.parse('$directUrl/templates'),
        ).timeout(const Duration(seconds: 30));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          return CartographicCatalog.fromJson(data);
        }
      } catch (e) {
        debugPrint("❌ Catalog HTTP failed: $e");
      }
    }

    // Fallback to Cloud Functions
    try {
      final result = await _functions
          .httpsCallable(
            'get_map_templates',
            options: HttpsCallableOptions(
              timeout: const Duration(seconds: 60),
            ),
          )
          .call({
            if (bbox != null) 'bbox': bbox,
            if (theme != null) 'theme': theme,
          });

      return CartographicCatalog.fromJson(result.data as Map<String, dynamic>);
    } catch (e) {
      debugPrint("❌ Catalog load failed: $e");
      rethrow;
    }
  }

  /// Get a user-friendly error message.
  String getErrorMessage(dynamic error) {
    if (error is FirebaseFunctionsException) {
      switch (error.code) {
        case 'unavailable':
          return 'Service temporarily unavailable. Please try again.';
        case 'deadline-exceeded':
          return 'Map generation timed out. Try a smaller area or simpler map type.';
        case 'invalid-argument':
          return 'Invalid map parameters: ${error.message}';
        case 'resource-exhausted':
          return 'Server is busy. Please wait a moment and try again.';
        case 'internal':
          return 'Map generation failed: ${error.message}';
        default:
          return 'An error occurred: ${error.message}';
      }
    }
    return error.toString();
  }
}
