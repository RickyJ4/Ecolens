import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ecolens/model/location_model.dart';
import 'package:ecolens/data/data_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class DashboardViewModel extends ChangeNotifier {
  // --- 🔐 PRIVATE STATE ---
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DataService _dataService = DataService();
  StreamSubscription? _hotspotSubscription;

  bool isLoading = true;
  List<IntelligenceNode> activeNodes = [];
  List<IntelligenceNode> localNodes = []; // Nodes near user

  // 📍 USER LOCATION
  String userCountry = "Global";
  String userRegion = "";
  String userLocality = "";
  String locationStatusText = "Detecting location...";
  LatLng userLocation = const LatLng(0, 0);
  bool locationLoaded = false;

  // 📈 GRAPH DATA
  List<FlSpot> globalTrendSpots = [];
  List<String> globalTrendYears = [];

  List<FlSpot> localTrendSpots = [];
  List<String> localTrendYears = [];

  // --- 📊 GLOBAL METRICS ---
  String totalDeforestation = "0";
  String reforestHectares = "0";
  int activeAlerts = 0;

  // --- 📊 LOCAL METRICS ---
  String localDeforestation = "0";
  String localRecovery = "0";
  int localAlerts = 0;

  // --- ADDITIONAL ---
  String dominantDriver = "STABLE";
  String syncStatusText = "CONNECTING TO SATELLITE...";
  LatLng focusLocation = const LatLng(0, 0);
  List<String> speciesAtRiskSummary = [];

  // --- 📌 PLACE SCOPE (story pin → Insights deep link) ---
  // When set, the "local" lens anchors on the story's geography instead of
  // the visitor's geolocation. Driven by /#/insights?place=<id> deep links
  // from the map's story pins (see PlacesService + MainLayout).
  String? scopedPlaceId;
  String? scopedPlaceName;
  String? scopedPlaceDek;
  String? scopedPlaceStoryUrl;
  LatLng? _placeAnchorLocation;
  String? _placeAnchorCountry;

  /// Re-anchor the local lens on a documented place.
  void focusOnPlace({
    required String id,
    required String name,
    required double lat,
    required double lng,
    String? dek,
    String? storyUrl,
    String? country,
  }) {
    scopedPlaceId = id;
    scopedPlaceName = name;
    scopedPlaceDek = dek;
    scopedPlaceStoryUrl = storyUrl;
    _placeAnchorLocation = LatLng(lat, lng);
    _placeAnchorCountry = country;
    focusLocation = LatLng(lat, lng);
    // The local lens must work even when browser geolocation was declined.
    locationLoaded = true;
    _performLocalAnalytics();
    notifyListeners();
  }

  /// Drop the place scope and return the local lens to the visitor's location.
  void clearPlaceScope() {
    scopedPlaceId = null;
    scopedPlaceName = null;
    scopedPlaceDek = null;
    scopedPlaceStoryUrl = null;
    _placeAnchorLocation = null;
    _placeAnchorCountry = null;
    _performLocalAnalytics();
    notifyListeners();
  }

  // --- 🌟 NEW: RICH ANALYTICS (Layer 13) ---
  int recoveryScore = 0; // 0-100
  String successProbability = "Unknown";
  Map<String, dynamic> actionPlan = {};
  Map<String, dynamic> soilData = {};
  Map<String, dynamic> terrainData = {};
  Map<String, dynamic> hydrologyData = {};
  Map<String, dynamic> historicalData = {};
  Map<String, dynamic> riskData = {};
  Map<String, dynamic> sentinelData = {};
  Map<String, dynamic> gisData = {};
  bool isAnalyzing = false;

  // --- 🎠 CAROUSEL STATE ---
  int currentCarouselIndex = 0;
  List<Map<String, dynamic>> hotspotSummaries = []; // Brief stats per hotspot
  bool autoAnalysisComplete = false;

  // --- 🗄️ INTELLIGENCE CACHE ---
  Map<String, Map<String, String>> preloadedForensics = {};
  bool _forensicsPreloadStarted = false;

  DashboardViewModel() {
    // The hotspot stream is no longer started at construction. It pulled
    // every document in `hotspots` (about 1,040 documents at roughly 100 KB
    // each) on every page load, then ran ten model calls and a geolocation
    // prompt, for a dashboard no screen renders any more. Insights streams
    // the live news feed instead. Place scoping from story deep links still
    // works: focusOnPlace/clearPlaceScope do not need hotspots.
    isLoading = false;
  }

  // --- 1. INITIALIZE WITH GEOLOCATION ---
  //
  // Fire Firestore + geolocation in parallel. Previous version awaited
  // geolocation (up to 10s) before subscribing to hotspots, so users saw
  // a blank dashboard for the full timeout if the browser was slow to
  // prompt for permission. Now hotspots stream in immediately; once
  // geolocation resolves we re-run local analytics.
  Future<void> _initWithLocation() async {
    isLoading = true;
    notifyListeners();

    _initRealTimeUplink();

    // Let location resolve in the background — re-derive local analytics
    // when it lands. Don't block the dashboard render on it.
    // ignore: unawaited_futures
    _getUserLocation().then((_) {
      if (activeNodes.isNotEmpty) {
        _performLocalAnalytics();
        _buildHotspotSummaries();
        if (!autoAnalysisComplete && locationLoaded) {
          _autoAnalyzeLocation();
        }
        notifyListeners();
      }
    });
  }

  // --- 2. GET USER LOCATION ---
  Future<void> _getUserLocation() async {
    try {
      // Check permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        locationStatusText = "Location permission denied";
        debugPrint("📍 Location permission denied, using global view");
        return;
      }

      // Get current position. Kept short so we don't sit on the
      // permission prompt indefinitely on slow browsers — the dashboard
      // already renders without it.
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 4),
      );

      userLocation = LatLng(position.latitude, position.longitude);
      focusLocation = userLocation;
      locationLoaded = true;
      if (userCountry == "Global" || userCountry == "Unknown") {
        _inferPlaceFromCoordinates(position.latitude, position.longitude);
      }
      locationStatusText = "Location detected";

      // Reverse geocode to get country/region
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );

        if (placemarks.isNotEmpty) {
          userCountry = placemarks.first.country ?? "Unknown";
          userRegion = placemarks.first.administrativeArea ?? "";
          userLocality = placemarks.first.locality ?? "";
          debugPrint("📍 User location: $userCountry, $userRegion");
        }
      } catch (e) {
        _inferPlaceFromCoordinates(position.latitude, position.longitude);
        debugPrint("📍 Geocoding error: $e");
      }

      locationLoaded = true;
    } catch (e) {
      debugPrint("📍 Location error: $e");
    }
  }

  void _inferPlaceFromCoordinates(double lat, double lng) {
    if (lat >= 41.5 && lat <= 83.5 && lng >= -141.0 && lng <= -52.0) {
      userCountry = "Canada";
      if (lat >= 48.0 && lat <= 60.5 && lng >= -139.5 && lng <= -114.0) {
        userRegion = "British Columbia";
      }
      return;
    }

    if (lat >= 24.0 && lat <= 49.5 && lng >= -125.0 && lng <= -66.0) {
      userCountry = "United States";
      userRegion = "";
      userLocality = "";
    }
  }

  Future<void> refreshUserLocation() async {
    locationStatusText = "Detecting location...";
    notifyListeners();
    await _getUserLocation();
    _performLocalAnalytics();
    _buildHotspotSummaries();
    notifyListeners();
  }

  // --- 3. THE REAL-TIME UPLINK ---
  void _initRealTimeUplink() {
    _hotspotSubscription = _firestore
        .collection('hotspots')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen(
          (snapshot) {
            try {
              activeNodes = snapshot.docs
                  .map((doc) => IntelligenceNode.fromMap(doc.data(), doc.id))
                  .toList();

              debugPrint(
                "🛰️ ECO-LENS: Received ${activeNodes.length} active nodes.",
              );
            } catch (e) {
              debugPrint("❌ DATA PARSING ERROR: $e");
            }

            // Process analytics
            _performGlobalAnalytics();
            _performLocalAnalytics();
            _preloadForensics();
            _buildHotspotSummaries(); // Build carousel data

            // Auto-trigger analysis for user's location (once)
            if (!autoAnalysisComplete && locationLoaded) {
              _autoAnalyzeLocation();
            }

            isLoading = false;
            syncStatusText = "SATELLITE SYNC: ACTIVE";
            notifyListeners();
          },
          onError: (error) {
            debugPrint("❌ HOTSPOT STREAM ERROR: $error");
            activeNodes = [];
            localNodes = [];
            hotspotSummaries = [];
            activeAlerts = 0;
            localAlerts = 0;
            totalDeforestation = "0";
            localDeforestation = "0";
            reforestHectares = "0";
            localRecovery = "0";
            dominantDriver = "UNAVAILABLE";
            syncStatusText = "SATELLITE SYNC: DEGRADED";
            isLoading = false;
            notifyListeners();
          },
        );
  }

  // --- 4. GLOBAL ANALYTICS ---
  void _performGlobalAnalytics() {
    if (activeNodes.isEmpty) {
      totalDeforestation = "0";
      activeAlerts = 0;
      reforestHectares = "0";
      globalTrendSpots = [];
      return;
    }

    double totalHa = 0;
    Map<String, int> driverCounts = {};
    Set<String> speciesSet = {};
    Map<String, double> temporalAggregate = {};

    for (var node in activeNodes) {
      totalHa += node.hectares;
      driverCounts[node.type] = (driverCounts[node.type] ?? 0) + 1;
      speciesSet.addAll(node.speciesAtRisk.cast<String>());

      node.yearlyHistory.forEach((year, loss) {
        temporalAggregate[year] = (temporalAggregate[year] ?? 0) + loss;
      });
    }

    final sortedYears = temporalAggregate.keys.toList()..sort();
    globalTrendYears = sortedYears;
    double xIndex = 0;
    globalTrendSpots = sortedYears.map((year) {
      return FlSpot(xIndex++, temporalAggregate[year]!);
    }).toList();

    totalDeforestation = NumberFormat.compact().format(totalHa);
    activeAlerts = activeNodes.length;
    reforestHectares = NumberFormat.compact().format(totalHa * 0.85);

    dominantDriver = driverCounts.entries.isEmpty
        ? "STABLE"
        : driverCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key;

    speciesAtRiskSummary = speciesSet.take(5).toList();

    if (!locationLoaded) return;
  }

  // --- 5. LOCAL ANALYTICS (user's region, or a scoped place) ---
  // Anchors on the visitor's geolocation by default; when a place scope is
  // active (story pin → Insights deep link) it anchors on that place instead.
  void _performLocalAnalytics() {
    if (activeNodes.isEmpty || !locationLoaded) {
      localNodes = [];
      _calculateLocalStats();
      return;
    }

    final anchorLocation = _placeAnchorLocation ?? userLocation;
    final anchorCountry = _placeAnchorCountry ?? userCountry;

    // Filter nodes by the anchor's country
    localNodes = activeNodes.where((node) {
      // Match by country name
      if (node.country.toLowerCase() == anchorCountry.toLowerCase()) {
        return true;
      }
      // Or by proximity (within ~500km)
      final distance = const Distance().as(
        LengthUnit.Kilometer,
        LatLng(node.lat, node.lng),
        anchorLocation,
      );
      return distance < 500;
    }).toList();

    // If no local nodes match the country string, keep only genuinely nearby
    // nodes. Do not fall back to arbitrary global alerts in local mode.
    if (localNodes.isEmpty) {
      final sortedByDistance = List<IntelligenceNode>.from(activeNodes)
        ..sort((a, b) {
          final distA = const Distance().as(
            LengthUnit.Kilometer,
            LatLng(a.lat, a.lng),
            anchorLocation,
          );
          final distB = const Distance().as(
            LengthUnit.Kilometer,
            LatLng(b.lat, b.lng),
            anchorLocation,
          );
          return distA.compareTo(distB);
        });
      localNodes = sortedByDistance
          .where((node) {
            final distance = const Distance().as(
              LengthUnit.Kilometer,
              LatLng(node.lat, node.lng),
              anchorLocation,
            );
            return distance < 500;
          })
          .take(10)
          .toList();
    }

    _calculateLocalStats();
  }

  void _calculateLocalStats() {
    double localHa = 0;
    Map<String, double> localTemporal = {};

    for (var node in localNodes) {
      localHa += node.hectares;
      node.yearlyHistory.forEach((year, loss) {
        localTemporal[year] = (localTemporal[year] ?? 0) + loss;
      });
    }

    localDeforestation = NumberFormat.compact().format(localHa);
    localAlerts = localNodes.length;
    localRecovery = NumberFormat.compact().format(localHa * 0.85);

    final sortedYears = localTemporal.keys.toList()..sort();
    localTrendYears = sortedYears;
    double xIndex = 0;
    localTrendSpots = sortedYears.map((year) {
      return FlSpot(xIndex++, localTemporal[year]!);
    }).toList();
  }

  // --- 6. BACKGROUND INTELLIGENCE PRE-LOADER ---
  //
  // Fires ONCE per session, in parallel. Previous version ran sequentially
  // (10 round-trips serial) AND was triggered on every Firestore snapshot,
  // so each hotspot delta replayed the whole batch — that's what was
  // hammering the Cloud Function and slowing the dashboard.
  Future<void> _preloadForensics() async {
    if (_forensicsPreloadStarted) return;
    _forensicsPreloadStarted = true;

    final batch = activeNodes
        .take(10)
        .where((n) => !preloadedForensics.containsKey(n.id))
        .toList();
    if (batch.isEmpty) return;

    await Future.wait(batch.map((node) async {
      try {
        final forensics =
            await _dataService.analyzeSectorCoordinates(node.lat, node.lng);
        preloadedForensics[node.id] = forensics;
      } catch (e) {
        debugPrint('Forensics preload failed for ${node.id}: $e');
      }
    }));
    notifyListeners();
  }

  // --- 7. BUILD CAROUSEL SUMMARIES ---
  void _buildHotspotSummaries() {
    hotspotSummaries = localNodes.take(5).map((node) {
      // Use the summary fields directly from the node
      return {
        'id': node.id,
        'name': node.region.isNotEmpty ? node.region : node.country,
        'lat': node.lat,
        'lng': node.lng,
        'hectares': node.hectares,
        'riskScore': node.riskScore,
        'recoveryPotential': _getRecoveryPotentialLabel(node.recoveryScore),
        'soilSummary': node.soilType,
        'waterAccess': node.waterAccess,
        'terrainDifficulty': node.terrainDifficulty,
        'dominantDriver': node.type,
      };
    }).toList();

    // If no local nodes exist, keep the local view empty instead of showing
    // unrelated global alerts as "nearby".
    if (hotspotSummaries.isEmpty && !locationLoaded && activeNodes.isNotEmpty) {
      hotspotSummaries = activeNodes
          .take(5)
          .map(
            (node) => {
              'id': node.id,
              'name': node.region.isNotEmpty ? node.region : node.country,
              'lat': node.lat,
              'lng': node.lng,
              'hectares': node.hectares,
              'riskScore': node.riskScore,
              'recoveryPotential': _getRecoveryPotentialLabel(
                node.recoveryScore,
              ),
              'soilSummary': node.soilType,
              'waterAccess': node.waterAccess,
              'terrainDifficulty': node.terrainDifficulty,
              'dominantDriver': node.type,
            },
          )
          .toList();
    }

    // No fallback / demo data. If hotspotSummaries is empty after pipeline
    // ingestion + LLM enrichment, the dashboard renders an honest empty
    // state — no synthetic numbers, no fake place names.
  }

  // --- 8. AUTO-ANALYZE USER LOCATION ---
  Future<void> _autoAnalyzeLocation() async {
    if (autoAnalysisComplete) return;
    autoAnalysisComplete = true; // Prevent duplicate calls

    // Delay slightly to let UI settle
    await Future.delayed(const Duration(milliseconds: 500));

    // Analyze user's location in background
    await analyzeCurrentLocation();
  }

  // --- 9. DATA REFRESH ---
  Future<void> loadInsights() async {
    _hotspotSubscription?.cancel();
    await _initWithLocation();
  }

  // --- 8. TRIGGER DEEP DIVE ANALYSIS ---
  Future<void> analyzeCurrentLocation() async {
    if (focusLocation.latitude == 0 && focusLocation.longitude == 0) return;

    isAnalyzing = true;
    notifyListeners();

    try {
      final data = await _dataService.getComprehensiveAnalysis(
        focusLocation.latitude,
        focusLocation.longitude,
      );

      // Safe Parsing Helper
      Map<String, dynamic> safeMap(String key) {
        if (data[key] == null) return {};
        try {
          return Map<String, dynamic>.from(data[key] as Map);
        } catch (e) {
          debugPrint("⚠️ Error casting key $key: $e");
          return {};
        }
      }

      // Parse detailed metrics
      if (data.containsKey('recovery_potential')) {
        var rp = data['recovery_potential'];
        if (rp is Map) {
          recoveryScore = rp['score'] ?? 0;
        } else {
          recoveryScore = 0;
        }
      }

      // Safe Parsing for all layers
      soilData = safeMap('soil_analysis');
      terrainData = safeMap('terrain_analysis');
      hydrologyData = safeMap('hydrology_analysis');
      historicalData = safeMap('historical_analysis');
      riskData = safeMap('risk_prediction');
      sentinelData = safeMap('sentinel_verification');
      gisData = safeMap('gis_analysis');

      if (data.containsKey('comprehensive_analysis')) {
        final analysis = data['comprehensive_analysis'];
        successProbability = analysis['success_probability'] ?? "Unknown";
        actionPlan = Map<String, dynamic>.from(analysis['action_plan'] ?? {});
      }
    } catch (e) {
      debugPrint("❌ Dashboard Analysis Error: $e");
    } finally {
      isAnalyzing = false;
      notifyListeners();
    }
  }

  // --- HELPER: Convert recovery score to label ---
  String _getRecoveryPotentialLabel(double score) {
    if (score >= 80) return 'Very High';
    if (score >= 65) return 'High';
    if (score >= 50) return 'Medium';
    if (score >= 35) return 'Low';
    return 'Very Low';
  }

  @override
  void dispose() {
    _hotspotSubscription?.cancel();
    super.dispose();
  }
}
