import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

/// A live wildfire threat derived from clustered NASA FIRMS hotspots.
///
/// The dashboard uses these instead of LLM-curated nodes when reporting
/// active threats. Every numeric field is sourced from real measurements
/// (FIRMS detection counts, VIIRS pixel area, geocoded city population) —
/// never synthesised from ratios.
class LiveThreat {
  final double lat;
  final double lng;
  final int detectionCount;
  final double estBurnAreaHa;
  final double maxFrp;
  final double avgFrp;
  final DateTime? latestDate;

  /// Human-readable place name (e.g. "near Revelstoke, BC"). Empty until
  /// geocoding resolves.
  final String placeLabel;
  final String country;

  /// Population of the nearest populated place (from Open-Meteo
  /// geocoding). 0 if no place was matched within the search radius —
  /// callers MUST treat 0 as "unknown", never "zero people".
  final int nearestPlacePop;

  /// Distance from cluster centroid to the nearest populated place, km.
  final double nearestPlaceKm;

  const LiveThreat({
    required this.lat,
    required this.lng,
    required this.detectionCount,
    required this.estBurnAreaHa,
    required this.maxFrp,
    required this.avgFrp,
    this.latestDate,
    this.placeLabel = '',
    this.country = '',
    this.nearestPlacePop = 0,
    this.nearestPlaceKm = 0,
  });

  /// 0–3 severity tier from FRP + detection count. Used for ordering and
  /// the colour swatch in the priority list.
  int get severityTier {
    if (maxFrp >= 200 || detectionCount >= 50) return 3; // critical
    if (maxFrp >= 80 || detectionCount >= 15) return 2; // high
    if (maxFrp >= 30 || detectionCount >= 5) return 1; // moderate
    return 0; // low
  }

  String get severityLabel =>
      const ['Low', 'Moderate', 'High', 'Critical'][severityTier];

  LiveThreat copyWith({
    String? placeLabel,
    String? country,
    int? nearestPlacePop,
    double? nearestPlaceKm,
  }) =>
      LiveThreat(
        lat: lat,
        lng: lng,
        detectionCount: detectionCount,
        estBurnAreaHa: estBurnAreaHa,
        maxFrp: maxFrp,
        avgFrp: avgFrp,
        latestDate: latestDate,
        placeLabel: placeLabel ?? this.placeLabel,
        country: country ?? this.country,
        nearestPlacePop: nearestPlacePop ?? this.nearestPlacePop,
        nearestPlaceKm: nearestPlaceKm ?? this.nearestPlaceKm,
      );
}

class LiveThreatsService {
  /// One VIIRS I-band pixel ≈ 375 m × 375 m at nadir = 14.0625 ha.
  static const double _viirsPixelAreaHa = 14.0625;

  /// Greedy spatial clustering of FIRMS GeoJSON features.
  ///
  /// Pure function — no I/O. Pass [bbox] as `[west, south, east, north]`
  /// to scope to a region; pass `null` for global. Features without
  /// coordinates are silently skipped.
  static List<LiveThreat> clusterFires({
    required List<dynamic> fireFeatures,
    List<double>? bbox,
    double clusterRadiusKm = 25,
    int maxClusters = 12,
  }) {
    if (fireFeatures.isEmpty) return const [];

    final points = <_FirePoint>[];
    for (final f in fireFeatures) {
      if (f is! Map) continue;
      final coords = (f['geometry'] as Map?)?['coordinates'] as List?;
      if (coords == null || coords.length < 2) continue;
      final lng = (coords[0] as num).toDouble();
      final lat = (coords[1] as num).toDouble();
      if (bbox != null &&
          (lng < bbox[0] || lng > bbox[2] || lat < bbox[1] || lat > bbox[3])) {
        continue;
      }
      final p = (f['properties'] as Map?) ?? const {};
      final frp = (p['frp'] as num?)?.toDouble() ?? 0;
      final acqDate = p['acq_date']?.toString() ?? '';
      points.add(_FirePoint(lat: lat, lng: lng, frp: frp, dateRaw: acqDate));
    }
    if (points.isEmpty) return const [];

    // Sort by FRP descending so the brightest fire seeds each cluster.
    points.sort((a, b) => b.frp.compareTo(a.frp));

    final clusters = <_Cluster>[];
    final radiusKmSq = clusterRadiusKm * clusterRadiusKm;
    for (final p in points) {
      _Cluster? hit;
      for (final c in clusters) {
        final dKmSq = _approxDistKmSq(p.lat, p.lng, c.lat, c.lng);
        if (dKmSq <= radiusKmSq) {
          hit = c;
          break;
        }
      }
      if (hit == null) {
        clusters.add(_Cluster.seed(p));
      } else {
        hit.add(p);
      }
    }

    clusters.sort((a, b) {
      final t = b.severityScore.compareTo(a.severityScore);
      return t != 0 ? t : b.count.compareTo(a.count);
    });

    return clusters
        .take(maxClusters)
        .map((c) => LiveThreat(
              lat: c.lat,
              lng: c.lng,
              detectionCount: c.count,
              estBurnAreaHa: c.count * _viirsPixelAreaHa,
              maxFrp: c.maxFrp,
              avgFrp: c.totalFrp / c.count,
              latestDate: c.latestDate,
            ))
        .toList(growable: false);
  }

  /// Resolve `placeLabel`, `country`, `nearestPlacePop`, `nearestPlaceKm`
  /// for the given threats. Uses Open-Meteo's `findNearestPlace` via the
  /// search endpoint with a wide bbox — returns the most populous place
  /// near the cluster.
  ///
  /// Concurrent across all threats; never throws — failed lookups leave
  /// the threat unchanged.
  static Future<List<LiveThreat>> enrichWithGeocoding(
      List<LiveThreat> threats) async {
    if (threats.isEmpty) return threats;
    final futures = threats.map(_resolveOne).toList();
    return await Future.wait(futures);
  }

  static Future<LiveThreat> _resolveOne(LiveThreat t) async {
    final cached = _geocodeCache[_cacheKey(t.lat, t.lng)];
    if (cached != null) return t.copyWith(
          placeLabel: cached.placeLabel,
          country: cached.country,
          nearestPlacePop: cached.population,
          nearestPlaceKm: cached.distanceKm,
        );

    try {
      final hit = await _bigDataCloudReverse(t.lat, t.lng);
      if (hit == null) return t;

      // Try to enrich population by forward-geocoding the city name.
      int pop = hit.population;
      double dist = hit.distanceKm;
      if (pop == 0 && hit.city.isNotEmpty) {
        final fwd = await _openMeteoForward(hit.city, hit.countryCode);
        if (fwd != null) {
          pop = fwd.population;
          dist = _approxDistKm(t.lat, t.lng, fwd.lat, fwd.lng);
        }
      }

      final entry = _GeoCacheEntry(
        placeLabel: hit.label,
        country: hit.country,
        population: pop,
        distanceKm: dist,
      );
      _geocodeCache[_cacheKey(t.lat, t.lng)] = entry;
      return t.copyWith(
        placeLabel: entry.placeLabel,
        country: entry.country,
        nearestPlacePop: entry.population,
        nearestPlaceKm: entry.distanceKm,
      );
    } catch (_) {
      return t;
    }
  }

  static String _cacheKey(double lat, double lng) =>
      '${(lat * 4).round() / 4}|${(lng * 4).round() / 4}'; // 0.25° bin

  static final Map<String, _GeoCacheEntry> _geocodeCache = {};

  static Future<_ReverseHit?> _bigDataCloudReverse(
      double lat, double lng) async {
    final url = Uri.parse(
        'https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=$lat&longitude=$lng&localityLanguage=en');
    final r = await http.get(url).timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) return null;
    final j = json.decode(r.body) as Map<String, dynamic>;
    final city = (j['city'] ??
            j['locality'] ??
            j['principalSubdivision'] ??
            '')
        .toString();
    final region = (j['principalSubdivision'] ?? '').toString();
    final country = (j['countryName'] ?? '').toString();
    final countryCode = (j['countryCode'] ?? '').toString();
    if (city.isEmpty && region.isEmpty) return null;
    final label = city.isNotEmpty
        ? (region.isNotEmpty && region != city ? '$city, $region' : city)
        : region;
    // BigDataCloud free tier doesn't expose population here.
    return _ReverseHit(
      label: label,
      city: city,
      country: country,
      countryCode: countryCode,
      population: 0,
      distanceKm: 0,
    );
  }

  static Future<_ForwardHit?> _openMeteoForward(
      String name, String countryCode) async {
    final url = Uri.parse(
        'https://geocoding-api.open-meteo.com/v1/search?name=${Uri.encodeQueryComponent(name)}&count=5&language=en&format=json');
    final r = await http.get(url).timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) return null;
    final j = json.decode(r.body) as Map<String, dynamic>;
    final results = (j['results'] as List?) ?? const [];
    if (results.isEmpty) return null;
    Map<String, dynamic>? best;
    for (final r in results) {
      if (r is Map) {
        if (countryCode.isNotEmpty && r['country_code'] == countryCode) {
          best = Map<String, dynamic>.from(r);
          break;
        }
      }
    }
    best ??= Map<String, dynamic>.from(results.first as Map);
    final pop = (best['population'] as num?)?.toInt() ?? 0;
    final lat = (best['latitude'] as num?)?.toDouble() ?? 0;
    final lng = (best['longitude'] as num?)?.toDouble() ?? 0;
    return _ForwardHit(population: pop, lat: lat, lng: lng);
  }

  // ---- Distance helpers (equirectangular, fast — accurate enough at
  // city scales for clustering + ordering). ----

  static double _approxDistKmSq(
      double lat1, double lng1, double lat2, double lng2) {
    const earthRadiusKm = 6371.0;
    final latRad = (lat1 + lat2) * 0.5 * math.pi / 180;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180 * math.cos(latRad);
    final dx = dLng * earthRadiusKm;
    final dy = dLat * earthRadiusKm;
    return dx * dx + dy * dy;
  }

  static double _approxDistKm(
          double lat1, double lng1, double lat2, double lng2) =>
      math.sqrt(_approxDistKmSq(lat1, lng1, lat2, lng2));
}

// ─── Internal types ─────────────────────────────────────────────────

class _FirePoint {
  final double lat;
  final double lng;
  final double frp;
  final String dateRaw;
  _FirePoint(
      {required this.lat,
      required this.lng,
      required this.frp,
      required this.dateRaw});
}

class _Cluster {
  double lat;
  double lng;
  int count;
  double totalFrp;
  double maxFrp;
  DateTime? latestDate;

  _Cluster.seed(_FirePoint p)
      : lat = p.lat,
        lng = p.lng,
        count = 1,
        totalFrp = p.frp,
        maxFrp = p.frp,
        latestDate = _parseDate(p.dateRaw);

  void add(_FirePoint p) {
    // Running mean of centroid, FRP-weighted toward brighter pixels.
    final w = math.max(p.frp, 1.0);
    final wTotal = (totalFrp == 0 ? count.toDouble() : totalFrp) + w;
    lat = (lat * (wTotal - w) + p.lat * w) / wTotal;
    lng = (lng * (wTotal - w) + p.lng * w) / wTotal;
    totalFrp += p.frp;
    maxFrp = math.max(maxFrp, p.frp);
    count += 1;
    final d = _parseDate(p.dateRaw);
    if (d != null && (latestDate == null || d.isAfter(latestDate!))) {
      latestDate = d;
    }
  }

  /// Higher = more severe. Combines fire intensity (max FRP) with
  /// extent (detection count). Both signals matter — a single 500-MW
  /// pixel is dangerous, and so is a 200-pixel slow burn.
  double get severityScore => maxFrp + count * 5.0;

  static DateTime? _parseDate(String raw) {
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }
}

class _ReverseHit {
  final String label;
  final String city;
  final String country;
  final String countryCode;
  final int population;
  final double distanceKm;
  _ReverseHit({
    required this.label,
    required this.city,
    required this.country,
    required this.countryCode,
    required this.population,
    required this.distanceKm,
  });
}

class _ForwardHit {
  final int population;
  final double lat;
  final double lng;
  _ForwardHit({required this.population, required this.lat, required this.lng});
}

class _GeoCacheEntry {
  final String placeLabel;
  final String country;
  final int population;
  final double distanceKm;
  _GeoCacheEntry({
    required this.placeLabel,
    required this.country,
    required this.population,
    required this.distanceKm,
  });
}
