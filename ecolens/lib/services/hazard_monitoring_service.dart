import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'package:ecolens/model/hazard_models.dart';

// ═══════════════════════════════════════════════════════════════
// HAZARD MONITORING SERVICE
// Communicates with Firebase Cloud Functions for multi-hazard data
// ═══════════════════════════════════════════════════════════════

class HazardMonitoringService {
  // ─────────────────────────────────────────────────────────────
  // Singleton
  // ─────────────────────────────────────────────────────────────
  static final HazardMonitoringService _instance =
      HazardMonitoringService._internal();

  factory HazardMonitoringService() => _instance;

  HazardMonitoringService._internal();

  // ─────────────────────────────────────────────────────────────
  // Firebase references
  // ─────────────────────────────────────────────────────────────
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ─────────────────────────────────────────────────────────────
  // Cache storage
  // ─────────────────────────────────────────────────────────────
  final Map<String, _CacheEntry> _cache = {};

  /// Cache TTL per hazard type (in minutes).
  static const Map<HazardType, int> _cacheTtlMinutes = {
    HazardType.wildfire: 5,
    HazardType.flood: 15,
    HazardType.drought: 60,
    HazardType.glacier: 60,
    HazardType.ndvi: 30,
    HazardType.watershed: 30,
    HazardType.riskSurface: 15,
  };

  // ─────────────────────────────────────────────────────────────
  // Rate limiting
  // ─────────────────────────────────────────────────────────────
  final Map<String, DateTime> _lastCallTimes = {};
  static const Duration _minCallInterval = Duration(seconds: 2);

  // ─────────────────────────────────────────────────────────────
  // Retry configuration
  // ─────────────────────────────────────────────────────────────
  static const int _maxRetries = 3;
  static const Duration _retryBaseDelay = Duration(seconds: 1);

  // ═══════════════════════════════════════════════════════════════
  // PUBLIC API
  // ═══════════════════════════════════════════════════════════════

  // Helper to flatten bbox into the top-level params the backend expects.
  Map<String, dynamic> _bboxParams(LatLngBounds bbox) => {
        'west': bbox.west,
        'south': bbox.south,
        'east': bbox.east,
        'north': bbox.north,
      };

  /// Fetch all hazard types within the given bounding box.
  Future<HazardCollection> fetchAllHazards(
    LatLngBounds bbox, {
    List<String>? include,
  }) async {
    final params = {
      ..._bboxParams(bbox),
      if (include != null) 'include': include,
    };

    final result = await _callFunction('get_active_hazards', params);
    return HazardCollection.fromJson(result);
  }

  /// Fetch active fire hotspots (NASA FIRMS data).
  Future<List<FireHotspot>> fetchActiveFires(LatLngBounds bbox) async {
    final cacheKey = _buildCacheKey('fires', bbox);

    final cached = _getFromCache<List<FireHotspot>>(
      cacheKey,
      HazardType.wildfire,
    );
    if (cached != null) return cached;

    final result = await _callFunction('get_hazard_layer', {
      ..._bboxParams(bbox),
      'hazard_type': 'fire',
    });

    final fires = (result['features'] as List? ?? [])
        .map((e) => FireHotspot.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    _putInCache(cacheKey, fires, HazardType.wildfire);
    return fires;
  }

  /// Fetch flood alerts from gauges within the bounding box.
  Future<List<FloodAlert>> fetchFloodAlerts(LatLngBounds bbox) async {
    final cacheKey = _buildCacheKey('floods', bbox);

    final cached = _getFromCache<List<FloodAlert>>(
      cacheKey,
      HazardType.flood,
    );
    if (cached != null) return cached;

    final result = await _callFunction('get_hazard_layer', {
      ..._bboxParams(bbox),
      'hazard_type': 'flood',
    });

    final floods = (result['features'] as List? ?? [])
        .map((e) => FloodAlert.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    _putInCache(cacheKey, floods, HazardType.flood);
    return floods;
  }

  /// Fetch drought status for the given bounding box.
  Future<DroughtStatus> fetchDroughtStatus(LatLngBounds bbox) async {
    final cacheKey = _buildCacheKey('drought', bbox);

    final cached = _getFromCache<DroughtStatus>(
      cacheKey,
      HazardType.drought,
    );
    if (cached != null) return cached;

    final result = await _callFunction('get_hazard_layer', {
      ..._bboxParams(bbox),
      'hazard_type': 'drought',
    });

    final drought = DroughtStatus.fromJson(result);
    _putInCache(cacheKey, drought, HazardType.drought);
    return drought;
  }

  /// Fetch glacier outlines from the global glacier inventory.
  Future<List<GlacierOutline>> fetchGlacierData(LatLngBounds bbox) async {
    final cacheKey = _buildCacheKey('glaciers', bbox);

    final cached = _getFromCache<List<GlacierOutline>>(
      cacheKey,
      HazardType.glacier,
    );
    if (cached != null) return cached;

    final result = await _callFunction('get_hazard_layer', {
      ..._bboxParams(bbox),
      'hazard_type': 'glacier',
    });

    final glaciers = (result['features'] as List? ?? [])
        .map(
          (e) => GlacierOutline.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();

    _putInCache(cacheKey, glaciers, HazardType.glacier);
    return glaciers;
  }

  /// Fetch NDVI vegetation analysis for the region.
  Future<NDVIResult> fetchNDVIAnalysis(LatLngBounds bbox) async {
    final cacheKey = _buildCacheKey('ndvi', bbox);

    final cached = _getFromCache<NDVIResult>(cacheKey, HazardType.ndvi);
    if (cached != null) return cached;

    final result = await _callFunction('get_hazard_layer', {
      ..._bboxParams(bbox),
      'hazard_type': 'ndvi',
    });

    final ndvi = NDVIResult.fromJson(result);
    _putInCache(cacheKey, ndvi, HazardType.ndvi);
    return ndvi;
  }

  /// Fetch composite risk surface grid.
  Future<RiskSurface> fetchRiskSurface(LatLngBounds bbox) async {
    final cacheKey = _buildCacheKey('risk', bbox);

    final cached = _getFromCache<RiskSurface>(
      cacheKey,
      HazardType.riskSurface,
    );
    if (cached != null) return cached;

    final result = await _callFunction('get_risk_surface', {
      ..._bboxParams(bbox),
    });

    final risk = RiskSurface.fromJson(result);
    _putInCache(cacheKey, risk, HazardType.riskSurface);
    return risk;
  }

  /// Fetch DEM heightmap for 3D terrain / Unity simulation.
  Future<DEMData> fetchDEMHeightmap(LatLngBounds bbox) async {
    final result = await _callFunction('get_dem_heightmap', {
      ..._bboxParams(bbox),
    });

    return DEMData.fromJson(result);
  }

  /// Register a location monitor to receive push notifications.
  Future<LocationMonitor> monitorLocation(
    double lat,
    double lon,
    double radiusKm,
  ) async {
    final result = await _callFunction('monitorLocation', {
      'latitude': lat,
      'longitude': lon,
      'radiusKm': radiusKm,
    });

    return LocationMonitor.fromJson(result);
  }

  /// Listen to real-time hazard alerts from Firestore.
  Stream<List<HazardFeature>> streamHazardAlerts({
    required double lat,
    required double lon,
    double radiusKm = 50,
  }) {
    return _firestore
        .collection('hazard_alerts')
        .where('active', isEqualTo: true)
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return HazardFeature.fromJson(data);
      }).toList();
    });
  }

  /// Clear all cached data.
  void clearCache() {
    _cache.clear();
  }

  // ═══════════════════════════════════════════════════════════════
  // INTERNAL HELPERS
  // ═══════════════════════════════════════════════════════════════

  /// Call a Firebase Cloud Function with rate limiting and retry logic.
  Future<Map<String, dynamic>> _callFunction(
    String functionName,
    Map<String, dynamic> params,
  ) async {
    // Rate limiting
    await _enforceRateLimit(functionName);

    // Retry with exponential back-off
    Exception? lastException;

    for (int attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        final callable = _functions.httpsCallable(
          functionName,
          options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
        );

        final response = await callable.call(params);
        final data = response.data;

        if (data is Map) {
          return Map<String, dynamic>.from(data);
        }
        return jsonDecode(jsonEncode(data)) as Map<String, dynamic>;
      } on FirebaseFunctionsException catch (e) {
        lastException = e;
        debugPrint(
          'Cloud Function "$functionName" attempt ${attempt + 1} failed: '
          '${e.code} - ${e.message}',
        );

        // Don't retry on client errors
        if (e.code == 'invalid-argument' ||
            e.code == 'permission-denied' ||
            e.code == 'unauthenticated') {
          break;
        }

        if (attempt < _maxRetries - 1) {
          await Future.delayed(_retryBaseDelay * (attempt + 1));
        }
      } catch (e) {
        lastException = e is Exception ? e : Exception(e.toString());
        debugPrint(
          'Cloud Function "$functionName" attempt ${attempt + 1} error: $e',
        );

        if (attempt < _maxRetries - 1) {
          await Future.delayed(_retryBaseDelay * (attempt + 1));
        }
      }
    }

    throw lastException ?? Exception('Unknown error calling $functionName');
  }

  /// Enforce minimum interval between calls to the same function.
  Future<void> _enforceRateLimit(String functionName) async {
    final lastCall = _lastCallTimes[functionName];
    if (lastCall != null) {
      final elapsed = DateTime.now().difference(lastCall);
      if (elapsed < _minCallInterval) {
        await Future.delayed(_minCallInterval - elapsed);
      }
    }
    _lastCallTimes[functionName] = DateTime.now();
  }

  /// Build a deterministic cache key from function name and bounding box.
  String _buildCacheKey(String prefix, LatLngBounds bbox) {
    return '$prefix:${bbox.south.toStringAsFixed(3)},'
        '${bbox.west.toStringAsFixed(3)},'
        '${bbox.north.toStringAsFixed(3)},'
        '${bbox.east.toStringAsFixed(3)}';
  }

  /// Retrieve a value from cache if present and not expired.
  T? _getFromCache<T>(String key, HazardType type) {
    final entry = _cache[key];
    if (entry == null) return null;

    final ttl = Duration(minutes: _cacheTtlMinutes[type] ?? 15);
    if (DateTime.now().difference(entry.timestamp) > ttl) {
      _cache.remove(key);
      return null;
    }

    if (entry.data is T) {
      return entry.data as T;
    }
    return null;
  }

  /// Store a value in the cache.
  void _putInCache(String key, dynamic data, HazardType type) {
    _cache[key] = _CacheEntry(data: data, timestamp: DateTime.now());
  }
}

// ─────────────────────────────────────────────────────────────
// Internal cache entry
// ─────────────────────────────────────────────────────────────

class _CacheEntry {
  final dynamic data;
  final DateTime timestamp;

  const _CacheEntry({required this.data, required this.timestamp});
}
