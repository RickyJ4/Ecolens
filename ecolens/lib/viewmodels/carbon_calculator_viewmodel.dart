import 'package:ecolens/services/ecolens_api_service.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

/// ViewModel for Carbon Credit Calculator screen
class CarbonCalculatorViewModel extends ChangeNotifier {
  final EcoLensApiService _apiService = EcoLensApiService();

  // State
  bool _isCalculating = false;
  String? _error;
  Map<String, dynamic>? _carbonData;
  final List<Position> _boundaryPoints = [];
  Position? _currentLocation;
  bool _isTracking = false;

  // Getters
  bool get isCalculating => _isCalculating;
  String? get error => _error;
  Map<String, dynamic>? get carbonData => _carbonData;
  List<Position> get boundaryPoints => List.unmodifiable(_boundaryPoints);
  Position? get currentLocation => _currentLocation;
  bool get isTracking => _isTracking;

  // Has result
  bool get hasResult => _carbonData != null;

  // Has enough points for calculation (minimum 3)
  bool get canCalculate => _boundaryPoints.length >= 3;

  // Get land type
  String get landType {
    if (_carbonData == null) return 'Unknown';
    return _carbonData!['land_type'] ?? 'Unknown';
  }

  // Is existing forest?
  bool get isExistingForest => landType == 'existing_forest';

  // Area in hectares
  double get areaHectares {
    if (_carbonData == null) return 0.0;
    return (_carbonData!['area_hectares'] as num?)?.toDouble() ?? 0.0;
  }

  /// Initialize
  void init() {
    _getCurrentLocation();
  }

  /// Get current GPS location
  Future<void> _getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _currentLocation = position;
      notifyListeners();
    } catch (e) {
      debugPrint("❌ Location error: $e");
    }
  }

  /// Start tracking boundary
  void startTracking() {
    _isTracking = true;
    _boundaryPoints.clear();
    _carbonData = null;
    _error = null;
    notifyListeners();
    debugPrint("🟢 Started boundary tracking");
  }

  /// Stop tracking boundary
  void stopTracking() {
    _isTracking = false;
    notifyListeners();
    debugPrint("🔴 Stopped boundary tracking");
  }

  /// Add a boundary point from current GPS location (mobile flow:
  /// user physically walks the perimeter and taps "Add point" at each corner).
  Future<void> addBoundaryPoint() async {
    if (!_isTracking) return;

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _boundaryPoints.add(position);
      _currentLocation = position;
      notifyListeners();
      debugPrint(
        "📍 Added point ${_boundaryPoints.length}: ${position.latitude}, ${position.longitude}",
      );
    } catch (e) {
      _error = "Failed to add point: $e";
      notifyListeners();
    }
  }

  /// Add a boundary point at explicit coordinates (web flow:
  /// user taps the map to drop each corner).
  void addPointAtCoords(double lat, double lng) {
    if (!_isTracking) return;
    _boundaryPoints.add(
      Position(
        latitude: lat,
        longitude: lng,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      ),
    );
    notifyListeners();
    debugPrint(
      "📍 Added tap-point ${_boundaryPoints.length}: $lat, $lng",
    );
  }

  /// Remove last boundary point
  void removeLastPoint() {
    if (_boundaryPoints.isNotEmpty) {
      _boundaryPoints.removeLast();
      notifyListeners();
      debugPrint(
        "🗑️ Removed last point. Remaining: ${_boundaryPoints.length}",
      );
    }
  }

  /// Clear all boundary points
  void clearBoundary() {
    _boundaryPoints.clear();
    _carbonData = null;
    _error = null;
    _isTracking = false;
    notifyListeners();
    debugPrint("🗑️ Cleared all boundary points");
  }

  /// Calculate carbon credits
  Future<void> calculateCarbon() async {
    if (!canCalculate) {
      _error = "Need at least 3 boundary points";
      notifyListeners();
      return;
    }

    _isCalculating = true;
    _error = null;
    notifyListeners();

    try {
      // Convert Position objects to lat/lng maps
      final boundaryData = _boundaryPoints
          .map((pos) => {'lat': pos.latitude, 'lng': pos.longitude})
          .toList();

      // Send calculated area to backend for consistency
      final calculatedArea = calculateApproximateArea();

      final result = await _apiService.calculateCarbonCredits(
        boundaryPoints: boundaryData,
        areaHectares: calculatedArea,
      );

      _carbonData = result;
      _isCalculating = false;
      notifyListeners();

      debugPrint("✅ Carbon calculation complete for ${areaHectares} ha");
    } catch (e) {
      _isCalculating = false;
      _error = _apiService.getErrorMessage(e);
      notifyListeners();
      debugPrint("❌ Calculation failed: $e");
    }
  }

  /// Get carbon stock (for existing forest)
  Map<String, dynamic> get carbonStock {
    if (_carbonData == null || !isExistingForest) return {};
    return _carbonData!['carbon_stock'] ?? {};
  }

  /// Get market value (for existing forest)
  Map<String, dynamic> get marketValue {
    if (_carbonData == null || !isExistingForest) return {};
    return _carbonData!['market_value'] ?? {};
  }

  /// Get restoration potential (for degraded land)
  Map<String, dynamic> get restorationPotential {
    if (_carbonData == null || isExistingForest) return {};
    return _carbonData!['restoration_potential'] ?? {};
  }

  /// Get investment required (for degraded land)
  Map<String, dynamic> get investmentRequired {
    if (_carbonData == null || isExistingForest) return {};
    return _carbonData!['investment_required'] ?? {};
  }

  /// Get ROI analysis (for degraded land)
  Map<String, dynamic> get roiAnalysis {
    if (_carbonData == null || isExistingForest) return {};
    return _carbonData!['roi_analysis'] ?? {};
  }

  /// Get ecosystem services (for existing forest)
  Map<String, dynamic> get ecosystemServices {
    if (_carbonData == null || !isExistingForest) return {};
    return _carbonData!['ecosystem_services'] ?? {};
  }

  /// Get recommendations
  List<String> get recommendations {
    if (_carbonData == null) return [];
    return List<String>.from(_carbonData!['recommendations'] ?? []);
  }

  /// Calculate approximate area from boundary points (rough Shoelace formula)
  double calculateApproximateArea() {
    if (_boundaryPoints.length < 3) return 0.0;

    // Simple polygon area calculation (approximate for small areas)
    double area = 0.0;
    for (int i = 0; i < _boundaryPoints.length; i++) {
      final j = (i + 1) % _boundaryPoints.length;
      area += _boundaryPoints[i].latitude * _boundaryPoints[j].longitude;
      area -= _boundaryPoints[j].latitude * _boundaryPoints[i].longitude;
    }
    area = (area.abs() / 2.0);

    // Convert from degrees^2 to hectares (very rough approximation)
    // At equator, 1 degree ≈ 111 km, so 1 degree^2 ≈ 12,321 km^2 = 1,232,100 ha
    return area * 1232100;
  }
}
