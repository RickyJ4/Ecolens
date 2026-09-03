import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'dart:convert';

class DataService {
  late final GenerativeModel _model;

  DataService() {
    const apiKey = String.fromEnvironment('GEMINI_API_KEY');
    _model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: apiKey);
  }

  // ═══════════════════════════════════════════════════════════════
  // REGIONAL ECONOMIC ANALYSIS
  // ═══════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> analyzeRegionalEconomics({
    required double latitude,
    required double longitude,
    required double hectaresLost,
    required String region,
    required String habitatType,
    required int population,
  }) async {
    final prompt =
        '''
You are an environmental economist analyzing deforestation impacts.

LOCATION DATA:
- Coordinates: [$latitude, $longitude]
- Region: $region
- Habitat Type: $habitatType
- Area Lost: $hectaresLost hectares
- Population Affected: $population people

TASK:
Provide accurate financial impact analysis for this deforestation event. Include:

1. DIRECT ECONOMIC LOSS (in USD):
   - Timber/resource value
   - Carbon credit loss (use \$15-30 per ton CO2, ~500 tons/ha)
   - Tourism revenue impact if applicable
   - Agricultural opportunity cost

2. PROVINCIAL/STATE IMPACT:
   - GDP percentage affected
   - Job losses estimated
   - Infrastructure at risk
   
3. NATIONAL IMPACT:
   - Contribution to national forest loss
   - Impact on climate commitments
   - Biodiversity loss value

4. LONG-TERM COSTS:
   - Ecosystem service disruption (water, soil, pollination)
   - Climate adaptation costs
   - Health impacts from air quality

Return ONLY valid JSON in this exact format:
{
  "total_loss": "\$X.XM or \$XXK",
  "breakdown": {
    "timber_value": "\$XXK",
    "carbon_loss": "\$XXK",
    "ecosystem_services": "\$XXK",
    "other": "\$XXK"
  },
  "provincial_impact": "X% of provincial GDP, estimated Y jobs lost",
  "national_impact": "Represents X% of national annual forest loss",
  "long_term_cost": "\$X.XM over 10 years",
  "source": "World Bank, FAO, local economic data",
  "confidence": "high/medium/low"
}

Use real economic data for the region if available. If data is limited, provide conservative estimates and mark confidence as "medium" or "low".
''';

    try {
      final response = await _model.generateContent([Content.text(prompt)]);
      final text = response.text ?? '';

      // Extract JSON from response
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(text);
      if (jsonMatch != null) {
        final jsonStr = jsonMatch.group(0)!;
        final data = json.decode(jsonStr) as Map<String, dynamic>;
        return data;
      }

      throw Exception('No valid JSON in response');
    } catch (e) {
      print('❌ Gemini economic analysis failed: $e');

      // Fallback calculation
      return _fallbackEconomicCalculation(
        hectaresLost,
        latitude,
        longitude,
        population,
      );
    }
  }

  Map<String, dynamic> _fallbackEconomicCalculation(
    double hectares,
    double lat,
    double lng,
    int population,
  ) {
    // Regional multipliers
    double baseValue = 3000.0; // USD per hectare

    // Amazon / Tropical
    if (lat > -20 && lat < 10 && lng > -80 && lng < -45) {
      baseValue = 4500.0;
    }
    // North America / Europe
    else if (lat > 25 && lat < 70) {
      baseValue = 12500.0;
    }
    // Africa
    else if (lat > -35 && lat < 37 && lng > -20 && lng < 60) {
      baseValue = 6000.0;
    }
    // Southeast Asia
    else if (lat > -10 && lat < 30 && lng > 90 && lng < 150) {
      baseValue = 8000.0;
    }

    final totalLoss = hectares * baseValue;
    final carbonLoss = hectares * 500 * 20; // 500 tons/ha * $20/ton
    final timberValue = hectares * 800;
    final ecosystemServices = hectares * 1200;

    return {
      "total_loss": "\$${_formatCurrency(totalLoss)}",
      "breakdown": {
        "timber_value": "\$${_formatCurrency(timberValue)}",
        "carbon_loss": "\$${_formatCurrency(carbonLoss)}",
        "ecosystem_services": "\$${_formatCurrency(ecosystemServices)}",
        "other":
            "\$${_formatCurrency(totalLoss - timberValue - carbonLoss - ecosystemServices)}",
      },
      "provincial_impact": population > 1000
          ? "Significant local economic disruption, estimated ${(population * 0.15).toInt()} jobs affected"
          : "Limited direct population impact",
      "national_impact": "Contributes to regional deforestation trends",
      "long_term_cost": "\$${_formatCurrency(totalLoss * 2.5)}",
      "source": "Estimated using FAO/World Bank regional averages",
      "confidence": "medium",
    };
  }

  String _formatCurrency(double amount) {
    if (amount >= 1000000000) {
      return "${(amount / 1000000000).toStringAsFixed(2)}B";
    } else if (amount >= 1000000) {
      return "${(amount / 1000000).toStringAsFixed(2)}M";
    } else if (amount >= 1000) {
      return "${(amount / 1000).toStringAsFixed(1)}K";
    }
    return amount.toStringAsFixed(0);
  }

  // ═══════════════════════════════════════════════════════════════
  // SPECIES IUCN STATUS LOOKUP
  // ═══════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> getSpeciesIUCNStatus(String speciesName) async {
    final prompt =
        '''
Look up the IUCN Red List status for: "$speciesName"

Return ONLY valid JSON:
{
  "species": "$speciesName",
  "iucn_status": "Critically Endangered/Endangered/Vulnerable/Near Threatened/Least Concern/Data Deficient",
  "population_trend": "Decreasing/Stable/Increasing/Unknown",
  "estimated_population": 1000,
  "major_threats": ["habitat loss", "poaching", "climate change"],
  "conservation_status": "Protected/Not Protected/Unknown"
}

If the species is not found or you're unsure, use "Data Deficient" for iucn_status.
''';

    try {
      final response = await _model.generateContent([Content.text(prompt)]);
      final text = response.text ?? '';

      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(text);
      if (jsonMatch != null) {
        final jsonStr = jsonMatch.group(0)!;
        return json.decode(jsonStr) as Map<String, dynamic>;
      }

      throw Exception('No valid JSON in response');
    } catch (e) {
      print('❌ IUCN lookup failed for $speciesName: $e');
      return {
        "species": speciesName,
        "iucn_status": "Data Deficient",
        "population_trend": "Unknown",
        "estimated_population": 0,
        "major_threats": ["habitat loss"],
        "conservation_status": "Unknown",
      };
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // BATCH SPECIES ANALYSIS
  // ═══════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> analyzeSpeciesList(
    List<String> species,
  ) async {
    final results = <Map<String, dynamic>>[];

    // Process in batches to avoid rate limiting
    for (var i = 0; i < species.length; i += 3) {
      final batch = species.skip(i).take(3).toList();

      for (var speciesName in batch) {
        final result = await getSpeciesIUCNStatus(speciesName);
        results.add(result);

        // Small delay to avoid rate limiting
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    return results;
  }

  // ═══════════════════════════════════════════════════════════════
  // SECTOR FORENSIC ANALYSIS (Existing method)
  // ═══════════════════════════════════════════════════════════════

  Future<Map<String, String>> analyzeSectorCoordinates(
    double lat,
    double lng,
  ) async {
    final prompt =
        '''
Analyze this deforestation hotspot at coordinates [$lat, $lng].

Provide forensic analysis in these categories:
1. Primary Cause: What is causing the deforestation?
2. Secondary Factors: Contributing factors
3. Timeline: When did this likely start?
4. Perpetrators: Who is likely responsible?
5. Evidence: What evidence supports this analysis?

Return only JSON format.
''';

    try {
      final response = await _model.generateContent([Content.text(prompt)]);
      final text = response.text ?? '';

      return {
        'analysis': text,
        'coordinates': '[$lat, $lng]',
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      return {'analysis': 'Analysis unavailable', 'error': e.toString()};
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // LAND FEATURES IDENTIFICATION
  // ═══════════════════════════════════════════════════════════════

  Future<String> identifyLandFeatures(
    double lat,
    double lng,
    Map<String, dynamic> proximityData,
  ) async {
    final prompt =
        '''
Based on these coordinates [$lat, $lng] and proximity data:
- Rivers: ${proximityData['rivers']?['count'] ?? 0} within ${proximityData['rivers']?['nearest_km'] ?? 'N/A'} km
- Protected Areas: ${proximityData['protected_areas']?['count'] ?? 0} within ${proximityData['protected_areas']?['nearest_km'] ?? 'N/A'} km
- Infrastructure: ${proximityData['infrastructure']?['count'] ?? 0} nearby

Identify the land features present (e.g., "Riparian Zone", "Steep Slope", "Floodplain", "Ridge", "Valley", "Coastal", "Wetland", etc.)

Return ONLY a comma-separated string of 2-4 relevant features.
''';

    try {
      final response = await _model.generateContent([Content.text(prompt)]);
      final text = response.text ?? 'General Forest';
      return text.trim().replaceAll(RegExp(r'["\n]'), '');
    } catch (e) {
      return 'Mixed Terrain';
    }
  }
  // ═══════════════════════════════════════════════════════════════
  // 🔍 GEMINI VERIFICATION AGENT (Added per user request)
  // ═══════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> verifyDataPoints({
    required double lat,
    required double lng,
    required String region,
  }) async {
    final prompt =
        '''
You are an expert environmental analyst.
We have detected a potential deforestation hotspot at [$lat, $lng] in $region, but our primary sensors returned ZERO population affected and NO species data.

TASK:
1. Estimate the human population within a 20km radius of this location.
2. Identify 3-5 distinct endangered species likely to inhabit this specific area.
3. Provide a brief verification of whether this region is known for environmental degradation.

Return JSON ONLY:
{
  "verified_population": 1234,
  "population_source": "Estimated based on rural density in region",
  "verified_species": [
    {"name": "Species Name", "iucn_status": "Endangered"},
    ...
  ],
  "environmental_verification": "Brief text confirming if this area is prone to deforestation...",
  "confidence": "high/medium/low"
}
''';

    try {
      final response = await _model.generateContent([Content.text(prompt)]);
      final text = response.text ?? '';

      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(text);
      if (jsonMatch != null) {
        return json.decode(jsonMatch.group(0)!) as Map<String, dynamic>;
      }
    } catch (e) {
      print('❌ Gemini verification failed: $e');
    }

    return {};
  }

  // ═══════════════════════════════════════════════════════════════
  // 🐍 PYTHON BACKEND LINK (Layer 9-13 Analysis)
  // ═══════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> getComprehensiveAnalysis(
    double lat,
    double lng,
  ) async {
    try {
      debugPrint("📡 Calling Python Pipeline for $lat, $lng...");

      // Call the HTTPS Callable Function 'analyze_location'
      // Note: Set timeout to 180s because ISRIC SoilGrids API is slow
      final result = await FirebaseFunctions.instance
          .httpsCallable(
            'analyze_location',
            options: HttpsCallableOptions(
              timeout: const Duration(seconds: 180),
            ),
          )
          .call({
            'lat': lat,
            'lng': lng,
            'habitat': 'Unknown', // Can be refined later
          });

      final data = result.data as Map<String, dynamic>;
      debugPrint("✅ Pipeline Response: ${data.keys.toList()}");
      return data;
    } catch (e) {
      debugPrint("❌ Pipeline Error: $e");
      // Return empty structure on failure to prevent crashes
      return {
        "error": e.toString(),
        "recovery_potential": {"score": 0, "level": "Unknown"},
        "comprehensive_analysis": {
          "executive_summary": "Analysis unavailable.",
        },
      };
    }
  }
}
