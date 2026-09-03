// ═══════════════════════════════════════════════════════════════
// COUNTRY INTELLIGENCE DATA MODELS
// Structured data for country/city environmental intelligence
// ═══════════════════════════════════════════════════════════════

class CountryProfile {
  final String code; // ISO 3166-1 alpha-2
  final String iso3; // ISO 3166-1 alpha-3
  final String name;
  final double lat;
  final double lon;
  final Map<String, List<YearValue>> indicators;
  final List<DisasterEvent> recentDisasters;
  final ClimateData? climate;
  final ClimateProjection? projection;
  final List<EarthquakeEvent> earthquakes;

  const CountryProfile({
    required this.code,
    required this.iso3,
    required this.name,
    required this.lat,
    required this.lon,
    this.indicators = const {},
    this.recentDisasters = const [],
    this.climate,
    this.projection,
    this.earthquakes = const [],
  });

  /// Most recent value for an indicator, or null.
  double? latestIndicator(String key) {
    final series = indicators[key];
    if (series == null || series.isEmpty) return null;
    for (final yv in series) {
      if (yv.value != null) return yv.value;
    }
    return null;
  }

  CountryProfile copyWith({
    Map<String, List<YearValue>>? indicators,
    List<DisasterEvent>? recentDisasters,
    ClimateData? climate,
    ClimateProjection? projection,
    List<EarthquakeEvent>? earthquakes,
  }) {
    return CountryProfile(
      code: code,
      iso3: iso3,
      name: name,
      lat: lat,
      lon: lon,
      indicators: indicators ?? this.indicators,
      recentDisasters: recentDisasters ?? this.recentDisasters,
      climate: climate ?? this.climate,
      projection: projection ?? this.projection,
      earthquakes: earthquakes ?? this.earthquakes,
    );
  }
}

class YearValue {
  final int year;
  final double? value;

  const YearValue({required this.year, this.value});

  factory YearValue.fromJson(Map<String, dynamic> json) {
    return YearValue(
      year: int.tryParse(json['date']?.toString() ?? '') ?? 0,
      value: (json['value'] as num?)?.toDouble(),
    );
  }
}

class DisasterEvent {
  final String name;
  final String type;
  final DateTime date;
  final String? description;
  final String? url;

  const DisasterEvent({
    required this.name,
    required this.type,
    required this.date,
    this.description,
    this.url,
  });

  factory DisasterEvent.fromReliefWeb(Map<String, dynamic> json) {
    final fields = json['fields'] ?? json;
    final name = fields['name'] as String? ?? 'Unknown';
    // ReliefWeb type list
    final typeList = fields['type'] as List?;
    final type = (typeList != null && typeList.isNotEmpty)
        ? (typeList.first['name'] as String? ?? 'Unknown')
        : 'Unknown';
    final dateStr = fields['date']?['created'] as String? ?? '';
    final url = fields['url'] as String?;
    final desc = fields['description'] as String?;

    return DisasterEvent(
      name: name,
      type: type,
      date: DateTime.tryParse(dateStr) ?? DateTime.now(),
      description: desc,
      url: url,
    );
  }
}

class ClimateData {
  final List<MonthlyClimate> monthly;
  final double avgTempC;
  final double totalPrecipMm;
  final List<DailyClimate> daily;

  const ClimateData({
    required this.monthly,
    required this.avgTempC,
    required this.totalPrecipMm,
    this.daily = const [],
  });

  factory ClimateData.fromOpenMeteo(Map<String, dynamic> json) {
    final daily = json['daily'] as Map<String, dynamic>? ?? {};
    final times = (daily['time'] as List?)?.cast<String>() ?? [];
    final maxTemps = (daily['temperature_2m_max'] as List?)
            ?.map((e) => (e as num?)?.toDouble() ?? 0.0)
            .toList() ??
        [];
    final minTemps = (daily['temperature_2m_min'] as List?)
            ?.map((e) => (e as num?)?.toDouble() ?? 0.0)
            .toList() ??
        [];
    final precips = (daily['precipitation_sum'] as List?)
            ?.map((e) => (e as num?)?.toDouble() ?? 0.0)
            .toList() ??
        [];

    // Build daily entries
    final dailyEntries = <DailyClimate>[];
    for (int i = 0; i < times.length; i++) {
      dailyEntries.add(DailyClimate(
        date: DateTime.tryParse(times[i]) ?? DateTime.now(),
        tempMax: i < maxTemps.length ? maxTemps[i] : 0,
        tempMin: i < minTemps.length ? minTemps[i] : 0,
        precipMm: i < precips.length ? precips[i] : 0,
      ));
    }

    // Aggregate to monthly
    final monthBuckets = <int, List<DailyClimate>>{};
    for (final d in dailyEntries) {
      monthBuckets.putIfAbsent(d.date.month, () => []).add(d);
    }

    final monthlyList = <MonthlyClimate>[];
    double totalTemp = 0;
    double totalPrecip = 0;
    int tempCount = 0;

    for (int m = 1; m <= 12; m++) {
      final bucket = monthBuckets[m] ?? [];
      if (bucket.isEmpty) {
        monthlyList.add(MonthlyClimate(month: m, avgTempMax: 0, avgTempMin: 0, precipMm: 0));
        continue;
      }
      final avgMax = bucket.map((e) => e.tempMax).reduce((a, b) => a + b) / bucket.length;
      final avgMin = bucket.map((e) => e.tempMin).reduce((a, b) => a + b) / bucket.length;
      final sumPrecip = bucket.map((e) => e.precipMm).reduce((a, b) => a + b);

      monthlyList.add(MonthlyClimate(
        month: m,
        avgTempMax: avgMax,
        avgTempMin: avgMin,
        precipMm: sumPrecip / (dailyEntries.length > 365 ? (dailyEntries.length / 365).ceil() : 1),
      ));

      totalTemp += (avgMax + avgMin) / 2;
      totalPrecip += sumPrecip;
      tempCount++;
    }

    return ClimateData(
      monthly: monthlyList,
      avgTempC: tempCount > 0 ? totalTemp / tempCount : 0,
      totalPrecipMm: totalPrecip / (dailyEntries.length > 365 ? (dailyEntries.length / 365).ceil() : 1),
      daily: dailyEntries,
    );
  }
}

class MonthlyClimate {
  final int month;
  final double avgTempMax;
  final double avgTempMin;
  final double precipMm;

  const MonthlyClimate({
    required this.month,
    required this.avgTempMax,
    required this.avgTempMin,
    required this.precipMm,
  });

  String get monthName {
    const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return names[(month - 1).clamp(0, 11)];
  }
}

class DailyClimate {
  final DateTime date;
  final double tempMax;
  final double tempMin;
  final double precipMm;

  const DailyClimate({
    required this.date,
    required this.tempMax,
    required this.tempMin,
    required this.precipMm,
  });
}

class ClimateProjection {
  final String model;
  final String scenario;
  final List<YearlyProjection> yearly;

  const ClimateProjection({
    required this.model,
    required this.scenario,
    required this.yearly,
  });

  factory ClimateProjection.fromOpenMeteo(Map<String, dynamic> json, {
    String model = 'EC_Earth3P_HR',
    String scenario = 'SSP2-4.5',
  }) {
    final daily = json['daily'] as Map<String, dynamic>? ?? {};
    final times = (daily['time'] as List?)?.cast<String>() ?? [];
    final maxTemps = (daily['temperature_2m_max'] as List?)
            ?.map((e) => (e as num?)?.toDouble() ?? 0.0)
            .toList() ??
        [];
    final precips = (daily['precipitation_sum'] as List?)
            ?.map((e) => (e as num?)?.toDouble() ?? 0.0)
            .toList() ??
        [];

    // Aggregate by year
    final yearBuckets = <int, List<int>>{};
    for (int i = 0; i < times.length; i++) {
      final year = int.tryParse(times[i].split('-').first) ?? 2025;
      yearBuckets.putIfAbsent(year, () => []).add(i);
    }

    final yearlyList = <YearlyProjection>[];
    for (final entry in yearBuckets.entries) {
      final indices = entry.value;
      final avgTemp = indices
              .where((i) => i < maxTemps.length)
              .map((i) => maxTemps[i])
              .fold<double>(0, (a, b) => a + b) /
          indices.length;
      final totalPrecip = indices
          .where((i) => i < precips.length)
          .map((i) => precips[i])
          .fold<double>(0, (a, b) => a + b);

      yearlyList.add(YearlyProjection(
        year: entry.key,
        tempMax: avgTemp,
        precipMm: totalPrecip,
      ));
    }

    yearlyList.sort((a, b) => a.year.compareTo(b.year));

    return ClimateProjection(
      model: model,
      scenario: scenario,
      yearly: yearlyList,
    );
  }
}

class YearlyProjection {
  final int year;
  final double tempMax;
  final double precipMm;

  const YearlyProjection({
    required this.year,
    required this.tempMax,
    required this.precipMm,
  });
}

class EarthquakeEvent {
  final double magnitude;
  final double depth;
  final String place;
  final DateTime time;
  final double lat;
  final double lon;

  const EarthquakeEvent({
    required this.magnitude,
    required this.depth,
    required this.place,
    required this.time,
    required this.lat,
    required this.lon,
  });

  factory EarthquakeEvent.fromUsgs(Map<String, dynamic> feature) {
    final props = feature['properties'] as Map<String, dynamic>? ?? {};
    final geometry = feature['geometry'] as Map<String, dynamic>? ?? {};
    final coords = (geometry['coordinates'] as List?) ?? [0, 0, 0];

    return EarthquakeEvent(
      magnitude: (props['mag'] as num?)?.toDouble() ?? 0,
      depth: coords.length > 2 ? (coords[2] as num?)?.toDouble() ?? 0 : 0,
      place: props['place'] as String? ?? 'Unknown',
      time: DateTime.fromMillisecondsSinceEpoch(
        (props['time'] as num?)?.toInt() ?? 0,
        isUtc: true,
      ),
      lat: coords.length > 1 ? (coords[1] as num?)?.toDouble() ?? 0 : 0,
      lon: (coords[0] as num?)?.toDouble() ?? 0,
    );
  }
}
