import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:ecolens/model/hazard_models.dart';
import 'package:ecolens/services/hazard_monitoring_service.dart';

// ═══════════════════════════════════════════════════════════════
// HAZARD VIEWMODEL
// State management for the multi-hazard monitoring system
// ═══════════════════════════════════════════════════════════════

class HazardViewModel extends ChangeNotifier {
  final HazardMonitoringService _service = HazardMonitoringService();

  // ─────────────────────────────────────────────────────────────
  // Layer visibility toggles
  // ─────────────────────────────────────────────────────────────
  final Map<HazardType, bool> _layerVisibility = {
    HazardType.wildfire: true,
    HazardType.flood: true,
    HazardType.drought: false,
    HazardType.glacier: false,
    HazardType.ndvi: false,
    HazardType.watershed: false,
    HazardType.riskSurface: false,
  };

  Map<HazardType, bool> get layerVisibility =>
      Map.unmodifiable(_layerVisibility);

  // ─────────────────────────────────────────────────────────────
  // Cached hazard data per type
  // ─────────────────────────────────────────────────────────────
  final Map<HazardType, List<dynamic>> _hazardData = {};

  Map<HazardType, List<dynamic>> get hazardData =>
      Map.unmodifiable(_hazardData);

  // ─────────────────────────────────────────────────────────────
  // Risk surface
  // ─────────────────────────────────────────────────────────────
  RiskSurface? _currentRiskSurface;
  RiskSurface? get currentRiskSurface => _currentRiskSurface;

  // ─────────────────────────────────────────────────────────────
  // Selection
  // ─────────────────────────────────────────────────────────────
  HazardFeature? _selectedFeature;
  HazardFeature? get selectedFeature => _selectedFeature;

  // ─────────────────────────────────────────────────────────────
  // Loading / error state
  // ─────────────────────────────────────────────────────────────
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  // ─────────────────────────────────────────────────────────────
  // Filters per hazard type
  // ─────────────────────────────────────────────────────────────
  final Map<HazardType, FilterState> _filters = {
    for (final type in HazardType.values) type: FilterState(),
  };

  Map<HazardType, FilterState> get filters => Map.unmodifiable(_filters);

  FilterState getFilter(HazardType type) =>
      _filters[type] ?? FilterState();

  // ─────────────────────────────────────────────────────────────
  // Refresh tracking
  // ─────────────────────────────────────────────────────────────
  DateTime? _lastRefresh;
  DateTime? get lastRefresh => _lastRefresh;

  // ─────────────────────────────────────────────────────────────
  // Auto-refresh timer
  // ─────────────────────────────────────────────────────────────
  Timer? _autoRefreshTimer;
  Duration _autoRefreshInterval = const Duration(minutes: 5);

  Duration get autoRefreshInterval => _autoRefreshInterval;

  bool get isAutoRefreshActive => _autoRefreshTimer?.isActive ?? false;

  // ─────────────────────────────────────────────────────────────
  // Debounce for rapid changes
  // ─────────────────────────────────────────────────────────────
  Timer? _debounceTimer;
  static const Duration _debounceDuration = Duration(milliseconds: 300);

  // ─────────────────────────────────────────────────────────────
  // Current bounding box (cached for auto-refresh)
  // ─────────────────────────────────────────────────────────────
  LatLngBounds? _currentBounds;

  // ═══════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═══════════════════════════════════════════════════════════════

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _debounceTimer?.cancel();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════
  // LAYER TOGGLING
  // ═══════════════════════════════════════════════════════════════

  /// Toggle visibility of a hazard layer. Fetches data if not yet loaded.
  void toggleLayer(HazardType type) {
    _layerVisibility[type] = !(_layerVisibility[type] ?? false);
    notifyListeners();

    // If turned on and we have a bounding box, load data
    if (_layerVisibility[type] == true &&
        !_hazardData.containsKey(type) &&
        _currentBounds != null) {
      _debounce(() => refreshLayer(type, _currentBounds!));
    }
  }

  /// Set all layers visible or hidden.
  void setAllLayersVisible(bool visible) {
    for (final type in HazardType.values) {
      _layerVisibility[type] = visible;
    }
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════
  // DATA FETCHING
  // ═══════════════════════════════════════════════════════════════

  /// Refresh all visible hazard layers within the bounding box.
  /// Each layer fetches independently — one failure doesn't block others.
  Future<void> refreshAllData(LatLngBounds bbox) async {
    _currentBounds = bbox;
    _isLoading = true;
    _error = null;
    // Use microtask to avoid notifying during build phase
    await Future.microtask(() => notifyListeners());

    int successes = 0;
    int failures = 0;

    for (final type in HazardType.values) {
      if (_layerVisibility[type] == true) {
        try {
          await _fetchLayerData(type, bbox);
          successes++;
        } catch (e) {
          failures++;
          debugPrint('Failed to fetch ${type.label}: $e');
        }
      }
    }

    _lastRefresh = DateTime.now();
    if (failures > 0 && successes == 0) {
      _error = 'Could not reach hazard data services. Check your connection.';
    } else if (failures > 0) {
      _error = '$failures hazard layer(s) failed to load.';
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Refresh a single hazard layer.
  Future<void> refreshLayer(HazardType type, LatLngBounds bbox) async {
    _currentBounds = bbox;

    try {
      await _fetchLayerData(type, bbox);
      notifyListeners();
    } catch (e) {
      _error = 'Failed to fetch ${type.label} data: $e';
      debugPrint(_error);
      notifyListeners();
    }
  }

  /// Internal fetch dispatcher per hazard type.
  Future<void> _fetchLayerData(HazardType type, LatLngBounds bbox) async {
    switch (type) {
      case HazardType.wildfire:
        final fires = await _service.fetchActiveFires(bbox);
        _hazardData[type] = fires;
        break;

      case HazardType.flood:
        final floods = await _service.fetchFloodAlerts(bbox);
        _hazardData[type] = floods;
        break;

      case HazardType.drought:
        final drought = await _service.fetchDroughtStatus(bbox);
        _hazardData[type] = [drought];
        break;

      case HazardType.glacier:
        final glaciers = await _service.fetchGlacierData(bbox);
        _hazardData[type] = glaciers;
        break;

      case HazardType.ndvi:
        final ndvi = await _service.fetchNDVIAnalysis(bbox);
        _hazardData[type] = [ndvi];
        break;

      case HazardType.riskSurface:
        final risk = await _service.fetchRiskSurface(bbox);
        _currentRiskSurface = risk;
        _hazardData[type] = [risk];
        break;

      case HazardType.watershed:
        // Placeholder - watershed data handled via risk surface or NDVI
        break;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // SELECTION
  // ═══════════════════════════════════════════════════════════════

  /// Select a hazard feature (e.g., when user taps on map).
  void selectFeature(HazardFeature feature) {
    _selectedFeature = feature;
    notifyListeners();
  }

  /// Clear the current selection.
  void clearSelection() {
    _selectedFeature = null;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════
  // FILTERS
  // ═══════════════════════════════════════════════════════════════

  /// Update filter for a specific hazard type.
  void setFilter(HazardType type, FilterState filter) {
    _filters[type] = filter;
    _debounce(() => notifyListeners());
  }

  /// Get the feature count for a hazard type (after applying filters).
  int getFeatureCount(HazardType type) {
    final data = _hazardData[type];
    if (data == null) return 0;

    final filter = _filters[type];
    if (filter == null || filter.minSeverity == null) return data.length;

    return data.where((item) {
      if (item is HazardFeature) {
        return item.severity.index >= filter.minSeverity!.index;
      }
      return true;
    }).length;
  }

  // ═══════════════════════════════════════════════════════════════
  // GEOJSON EXPORT
  // ═══════════════════════════════════════════════════════════════

  /// Convert cached hazard data for a type into a GeoJSON FeatureCollection.
  Map<String, dynamic> getHazardGeoJSON(HazardType type) {
    final data = _hazardData[type] ?? [];
    final filter = _filters[type];

    final features = <Map<String, dynamic>>[];

    for (final item in data) {
      if (item is HazardFeature) {
        // Apply severity filter
        if (filter?.minSeverity != null &&
            item.severity.index < filter!.minSeverity!.index) {
          continue;
        }

        // Apply date range filter
        if (filter?.dateRange != null) {
          if (item.timestamp.isBefore(filter!.dateRange!.start) ||
              item.timestamp.isAfter(filter.dateRange!.end)) {
            continue;
          }
        }

        features.add(item.toGeoJSON());
      } else if (item is RiskSurface) {
        return item.gridGeoJSON;
      } else if (item is NDVIResult) {
        return item.gridGeoJSON;
      }
    }

    return {
      'type': 'FeatureCollection',
      'features': features,
    };
  }

  // ═══════════════════════════════════════════════════════════════
  // AUTO-REFRESH
  // ═══════════════════════════════════════════════════════════════

  /// Start auto-refresh with a configurable interval.
  void startAutoRefresh({Duration? interval}) {
    _autoRefreshTimer?.cancel();

    if (interval != null) {
      _autoRefreshInterval = interval;
    }

    _autoRefreshTimer = Timer.periodic(_autoRefreshInterval, (_) {
      if (_currentBounds != null) {
        refreshAllData(_currentBounds!);
      }
    });
  }

  /// Stop auto-refresh.
  void stopAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
  }

  // ═══════════════════════════════════════════════════════════════
  // DEBOUNCE
  // ═══════════════════════════════════════════════════════════════

  void _debounce(VoidCallback action) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, action);
  }
}
