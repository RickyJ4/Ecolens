import 'package:flutter/material.dart';

/// Pending fly-to request for the Map tab.
class MapFlyTarget {
  final double lat;
  final double lng;
  final double zoom;
  final String? label;

  /// Map layer pills to switch on when arriving, by pill key
  /// (for example `impacts`, `affected`). Empty leaves the map as it was.
  final List<String> layers;
  final DateTime requestedAt;

  MapFlyTarget(this.lat, this.lng,
      {this.zoom = 9, this.label, this.layers = const []})
      : requestedAt = DateTime.now();
}

class NavigationViewModel extends ChangeNotifier {
  int _selectedIndex = 0;
  MapFlyTarget? _pendingFlyTarget;

  int get selectedIndex => _selectedIndex;
  MapFlyTarget? get pendingFlyTarget => _pendingFlyTarget;

  void setIndex(int index) {
    _selectedIndex = index;
    notifyListeners();
  }

  /// Switch to the Map tab and signal the map to fly to a specific location.
  /// The map screen should read [pendingFlyTarget] after index changes.
  void goToMapAt(
    double lat,
    double lng, {
    double zoom = 9,
    String? label,
    List<String> layers = const [],
  }) {
    _pendingFlyTarget =
        MapFlyTarget(lat, lng, zoom: zoom, label: label, layers: layers);
    _selectedIndex = 0;
    notifyListeners();
  }

  /// Called by the map screen once it has consumed the fly target.
  void clearFlyTarget() {
    _pendingFlyTarget = null;
  }
}
