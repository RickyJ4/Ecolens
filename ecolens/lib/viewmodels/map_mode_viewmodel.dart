// lib/viewmodels/map_mode_viewmodel.dart
import 'package:flutter/material.dart';
import 'package:ecolens/model/location_model.dart';
import 'package:ecolens/data/community_data.dart';

enum MapMode { public, community, advanced }

class PinData {
  final double lat;
  final double lng;
  final Color riskColor;
  final String iconAsset; // For future custom icons
  PinData({
    required this.lat,
    required this.lng,
    required this.riskColor,
    this.iconAsset = '',
  });
}

class MapModeViewModel extends ChangeNotifier {
  MapMode _currentMode = MapMode.public;
  MapMode get currentMode => _currentMode;

  void setMode(MapMode mode) {
    if (_currentMode != mode) {
      _currentMode = mode;
      notifyListeners();
    }
  }

  // Determine pins based on mode and active layers
  Map<String, List<dynamic>> getPins(
    List<IntelligenceNode> aiNodes,
    List<CommunityReport> communityReports,
    Set<String> activeLayers,
  ) {
    List<PinData> aiPins = [];

    // Logic for AI pins (Public & Advanced modes)

    // Community reports
    List<CommunityReport> communityPins = [];
    if (_currentMode == MapMode.community || _currentMode == MapMode.advanced) {
      communityPins = communityReports;
    } else if (_currentMode == MapMode.public) {
      // In public mode, maybe only show planting events (positive action)
      communityPins = communityReports
          .where((r) => r.type == 'planting')
          .toList();
    }
    return {'aiPins': aiPins, 'communityReports': communityPins};
  }
}
