import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Added for local storage

class GfwHotspot {
  final double lat;
  final double lng;
  final int alerts;
  final double hectares;

  GfwHotspot({required this.lat, required this.lng, required this.alerts, required this.hectares});

  // Convert object to JSON for storage
  Map<String, dynamic> toJson() => {
    'latitude': lat,
    'longitude': lng,
    'alerts': alerts,
  };

  factory GfwHotspot.fromJson(Map<String, dynamic> json) {
    return GfwHotspot(
      lat: json['latitude'] ?? -3.46, 
      lng: json['longitude'] ?? -62.21,
      alerts: json['alerts'] ?? 0,
      hectares: (json['alerts'] ?? 0) * 0.09, 
    );
  }
}

class GfwService {
  static const String _baseUrl = 'https://data-api.globalforestwatch.org/dataset/gfw_integrated_alerts/v20251225/query/';
  // Supplied at build time: flutter build web --dart-define=GFW_API_KEY=...
  static const String _apiKey = String.fromEnvironment('GFW_API_KEY');
  static const String _cacheKey = 'gfw_hotspots_cache';

  // --- NEW: Load from Local Storage ---
  Future<List<GfwHotspot>> getCachedHotspots() async {
    final prefs = await SharedPreferences.getInstance();
    final String? cachedData = prefs.getString(_cacheKey);
    
    if (cachedData != null) {
      final List<dynamic> decoded = jsonDecode(cachedData);
      return decoded.map((item) => GfwHotspot.fromJson(item)).toList();
    }
    return [];
  }
  // Add this inside your GfwService class
Future<void> checkDatabaseIntegrity() async {
  final prefs = await SharedPreferences.getInstance();
  final String? cachedData = prefs.getString(_cacheKey);
  
  if (cachedData == null || cachedData.isEmpty) {
    print("DATABASE CHECK: [EMPTY] No data has reached the local database yet.");
  } else {
    final List<dynamic> decoded = jsonDecode(cachedData);
    print("DATABASE CHECK: [SUCCESS] Found ${decoded.length} entries in local storage.");
    print("PREVIEW: ${decoded.take(1).toList()}"); // Shows the first entry for verification
  }
}

  // --- UPDATED: Fetch with Background Save ---
  Future<List<GfwHotspot>> fetchGlobalHotspots() async {
    final String startDate = DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(const Duration(days: 30)));
    final Map<String, dynamic> sectorPoly = {
      "type": "Polygon",
      "coordinates": [[[-75.0, -20.0], [-40.0, -20.0], [-40.0, 10.0], [-75.0, 10.0], [-75.0, -20.0]]]
    };

    final String sql = "SELECT count(*) as alerts FROM results WHERE gfw_integrated_alerts__date >= '$startDate'";

    try {
      var response = await http.post(
        Uri.parse(_baseUrl),
        headers: {'x-api-key': _apiKey, 'Content-Type': 'application/json', 'Origin': 'https://localhost'},
        body: jsonEncode({"sql": sql, "geometry": sectorPoly}),
      ).timeout(const Duration(seconds: 30));

      // Handle Redirects
      if (response.statusCode == 301 || response.statusCode == 307 || response.statusCode == 308) {
        String? newLoc = response.headers['location'];
        if (newLoc != null) {
          if (newLoc.startsWith('/')) newLoc = 'https://data-api.globalforestwatch.org' + newLoc;
          response = await http.post(Uri.parse(newLoc), headers: {'x-api-key': _apiKey, 'Content-Type': 'application/json'}, body: jsonEncode({"sql": sql, "geometry": sectorPoly}));
        }
      }

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body)['data'];
        final List<GfwHotspot> hotspots = data.map((json) => GfwHotspot.fromJson(json)).toList();
        
        // --- NEW: Persist to Local Storage ---
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_cacheKey, jsonEncode(hotspots.map((h) => h.toJson()).toList()));
        
        return hotspots;
      }
      return await getCachedHotspots(); // Fallback to cache if server fails
    } catch (e) {
      print("Database Fetch Error: $e");
      return await getCachedHotspots(); // Fallback to cache on exception
    }
  }
}