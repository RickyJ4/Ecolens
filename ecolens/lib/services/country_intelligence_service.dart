import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:ecolens/model/country_models.dart';
import 'package:ecolens/data/country_data.dart';

// ═══════════════════════════════════════════════════════════════
// COUNTRY INTELLIGENCE SERVICE
// Fetches environmental data from free, no-auth APIs:
//   - World Bank (population, GDP, CO2, forest, electricity)
//   - Open-Meteo (climate history + projections)
//   - USGS (earthquakes)
//   - ReliefWeb (disasters)
// ═══════════════════════════════════════════════════════════════

class CountryIntelligenceService {
  CountryIntelligenceService._();
  static final instance = CountryIntelligenceService._();

  // ── Cache ────────────────────────────────────────────────
  final Map<String, _CacheEntry> _cache = {};
  static const _cacheDuration = Duration(hours: 1);

  T? _getCache<T>(String key) {
    final entry = _cache[key];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.time) > _cacheDuration) {
      _cache.remove(key);
      return null;
    }
    return entry.data as T?;
  }

  void _setCache(String key, dynamic data) {
    _cache[key] = _CacheEntry(data: data, time: DateTime.now());
  }

  // ── World Bank Indicators ───────────────────────────────
  static const _indicators = {
    'SP.POP.TOTL': 'Population',
    'NY.GDP.PCAP.CD': 'GDP per Capita (USD)',
    'EN.ATM.CO2E.PC': 'CO2 Emissions (metric tons per capita)',
    'AG.LND.FRST.ZS': 'Forest Area (%)',
    'EG.ELC.ACCS.ZS': 'Access to Electricity (%)',
  };

  /// Fetches all World Bank indicators for a country.
  Future<Map<String, List<YearValue>>> fetchCountryIndicators(String countryCode) async {
    final cacheKey = 'wb_$countryCode';
    final cached = _getCache<Map<String, List<YearValue>>>(cacheKey);
    if (cached != null) return cached;

    final result = <String, List<YearValue>>{};

    await Future.wait(_indicators.keys.map((indicator) async {
      try {
        final dateRange = indicator == 'EN.ATM.CO2E.PC' ? '2010:2024' :
                          indicator == 'AG.LND.FRST.ZS' ? '2005:2024' :
                          indicator == 'EG.ELC.ACCS.ZS' ? '2010:2024' :
                          '2015:2024';
        final url = 'https://api.worldbank.org/v2/country/$countryCode/indicator/$indicator?format=json&date=$dateRange&per_page=50';
        final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
        if (response.statusCode == 200) {
          final json = jsonDecode(response.body);
          if (json is List && json.length > 1 && json[1] is List) {
            final entries = (json[1] as List)
                .map((e) => YearValue.fromJson(e as Map<String, dynamic>))
                .toList();
            // Sort by year ascending
            entries.sort((a, b) => a.year.compareTo(b.year));
            result[indicator] = entries;
          }
        }
      } catch (e) {
        debugPrint('World Bank fetch error for $indicator: $e');
      }
    }));

    _setCache(cacheKey, result);
    return result;
  }

  /// Builds a complete CountryProfile with all data sources.
  Future<CountryProfile> fetchCountryProfile(String countryCode) async {
    final info = countryByCode(countryCode);
    if (info == null) {
      return CountryProfile(
        code: countryCode,
        iso3: countryCode.toUpperCase(),
        name: countryCode,
        lat: 0,
        lon: 0,
      );
    }

    // Fetch all data in parallel
    final results = await Future.wait([
      fetchCountryIndicators(countryCode),
      fetchClimateHistory(info.lat, info.lon),
      fetchClimateProjection(info.lat, info.lon),
      fetchRecentDisasters(info.iso3),
      fetchNearbyEarthquakes(info.lat, info.lon),
    ]);

    return CountryProfile(
      code: info.code,
      iso3: info.iso3,
      name: info.name,
      lat: info.lat,
      lon: info.lon,
      indicators: results[0] as Map<String, List<YearValue>>,
      climate: results[1] as ClimateData?,
      projection: results[2] as ClimateProjection?,
      recentDisasters: results[3] as List<DisasterEvent>,
      earthquakes: results[4] as List<EarthquakeEvent>,
    );
  }

  // ── Open-Meteo Climate History ──────────────────────────
  Future<ClimateData?> fetchClimateHistory(double lat, double lon) async {
    final cacheKey = 'climate_${lat}_$lon';
    final cached = _getCache<ClimateData?>(cacheKey);
    if (cached != null) return cached;

    try {
      final url = 'https://archive-api.open-meteo.com/v1/archive'
          '?latitude=$lat&longitude=$lon'
          '&start_date=2020-01-01&end_date=2024-12-31'
          '&daily=temperature_2m_max,temperature_2m_min,precipitation_sum'
          '&timezone=auto';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final data = ClimateData.fromOpenMeteo(json);
        _setCache(cacheKey, data);
        return data;
      }
    } catch (e) {
      debugPrint('Climate history fetch error: $e');
    }
    return null;
  }

  // ── Open-Meteo Climate Projections ──────────────────────
  Future<ClimateProjection?> fetchClimateProjection(double lat, double lon) async {
    final cacheKey = 'projection_${lat}_$lon';
    final cached = _getCache<ClimateProjection?>(cacheKey);
    if (cached != null) return cached;

    try {
      final url = 'https://climate-api.open-meteo.com/v1/climate'
          '?latitude=$lat&longitude=$lon'
          '&start_date=2025&end_date=2050'
          '&models=EC_Earth3P_HR'
          '&daily=temperature_2m_max,precipitation_sum';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final data = ClimateProjection.fromOpenMeteo(json);
        _setCache(cacheKey, data);
        return data;
      }
    } catch (e) {
      debugPrint('Climate projection fetch error: $e');
    }
    return null;
  }

  // ── ReliefWeb Disasters ─────────────────────────────────
  Future<List<DisasterEvent>> fetchRecentDisasters(String iso3) async {
    final cacheKey = 'disasters_$iso3';
    final cached = _getCache<List<DisasterEvent>>(cacheKey);
    if (cached != null) return cached;

    try {
      final url = 'https://api.reliefweb.int/v1/disasters'
          '?appname=ecolens'
          '&filter[field]=country.iso3'
          '&filter[value]=$iso3'
          '&limit=200'
          '&sort[]=date:desc'
          '&fields[include][]=name&fields[include][]=date&fields[include][]=type&fields[include][]=status&fields[include][]=country';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final dataList = json['data'] as List? ?? [];
        final disasters = dataList
            .map((e) => DisasterEvent.fromReliefWeb(e as Map<String, dynamic>))
            .toList();
        _setCache(cacheKey, disasters);
        return disasters;
      }
    } catch (e) {
      debugPrint('ReliefWeb fetch error: $e');
    }
    return [];
  }

  // ── USGS Earthquakes ────────────────────────────────────
  Future<List<EarthquakeEvent>> fetchNearbyEarthquakes(double lat, double lon) async {
    final cacheKey = 'earthquakes_${lat}_$lon';
    final cached = _getCache<List<EarthquakeEvent>>(cacheKey);
    if (cached != null) return cached;

    try {
      final now = DateTime.now();
      final start = DateTime(now.year - 1, now.month, now.day);
      final startStr = '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
      final url = 'https://earthquake.usgs.gov/fdsnws/event/1/query'
          '?format=geojson'
          '&latitude=$lat&longitude=$lon'
          '&maxradiuskm=500'
          '&starttime=$startStr'
          '&minmagnitude=2.5'
          '&orderby=time'
          '&limit=200';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final features = json['features'] as List? ?? [];
        final quakes = features
            .map((e) => EarthquakeEvent.fromUsgs(e as Map<String, dynamic>))
            .toList();
        _setCache(cacheKey, quakes);
        return quakes;
      }
    } catch (e) {
      debugPrint('USGS fetch error: $e');
    }
    return [];
  }
}

class _CacheEntry {
  final dynamic data;
  final DateTime time;
  const _CacheEntry({required this.data, required this.time});
}
