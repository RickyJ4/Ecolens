import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// One geography EcoLens has reported on — the shared "Places spine".
///
/// The same places.json drives the map's story pins (JS side) and the
/// Insights place-scoping (Dart side), so the two lenses can never drift
/// apart. Source of truth: assets/maplibre_map/places.json.
class EcoPlace {
  final String id;
  final String name;
  final String? kicker;
  final String? dek;
  final double lat;
  final double lon;
  final String status; // published | coming_soon | in_development
  final String? storyUrl;
  final String? country;
  final List<String> facts;

  const EcoPlace({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    required this.status,
    this.kicker,
    this.dek,
    this.storyUrl,
    this.country,
    this.facts = const [],
  });

  factory EcoPlace.fromJson(Map<String, dynamic> json) {
    return EcoPlace(
      id: json['id'] as String,
      name: json['name'] as String? ?? json['id'] as String,
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      status: json['status'] as String? ?? 'in_development',
      kicker: json['kicker'] as String?,
      dek: json['dek'] as String?,
      storyUrl: json['storyUrl'] as String?,
      country: json['country'] as String?,
      facts: (json['facts'] as List?)?.cast<String>() ?? const [],
    );
  }
}

/// Loads and caches the Places spine from the bundled places.json.
class PlacesService {
  static List<EcoPlace>? _cache;

  static Future<List<EcoPlace>> all() async {
    if (_cache != null) return _cache!;
    try {
      final raw =
          await rootBundle.loadString('assets/maplibre_map/places.json');
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final list = (data['places'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(EcoPlace.fromJson)
          .toList();
      _cache = list;
      return list;
    } catch (e) {
      debugPrint('[PlacesService] failed to load places.json: $e');
      _cache = const [];
      return const [];
    }
  }

  static Future<EcoPlace?> byId(String id) async {
    final places = await all();
    for (final p in places) {
      if (p.id == id) return p;
    }
    return null;
  }
}
