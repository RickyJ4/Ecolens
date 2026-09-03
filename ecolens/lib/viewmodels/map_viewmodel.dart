// --- VIEWMODEL: MAP STATE ---
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class MapViewModel extends ChangeNotifier {
  final MapController mapController = MapController();

  // Toggles for layers
  bool showDeforestation = true;
  bool showRiskHeatmap = false;

  // Navigation Target
  double? targetLat;
  double? targetLng;

  // Method to move camera
  void moveToLocation(LatLng location, {double zoom = 6.0}) {
    mapController.move(location, zoom);
    notifyListeners();
  }

  void toggleLayer(String layer) {
    if (layer == 'deforestation') showDeforestation = !showDeforestation;
    if (layer == 'risk') showRiskHeatmap = !showRiskHeatmap;
    notifyListeners();
  }

  void updateTargetLocation(double lat, double lng) {
    targetLat = lat;
    targetLng = lng;
    notifyListeners();
  }

  void clearTargetLocation() {
    targetLat = null;
    targetLng = null;
  }
}
