/// Data models for historical environmental event simulations.

class HistoricalEvent {
  final String id;
  final String name;
  final String category; // 'wildfire', 'flood', 'drought', 'glacier', 'deforestation'
  final String description;
  final double latitude;
  final double longitude;
  final DateTime startDate;
  final DateTime endDate;
  final double areaHectares;
  final String country;
  final Map<String, dynamic> metadata;
  final List<TimelineFrame> frames;

  const HistoricalEvent({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.startDate,
    required this.endDate,
    required this.areaHectares,
    required this.country,
    this.metadata = const {},
    this.frames = const [],
  });

  /// Create from JSON (e.g. from JS bridge or API response).
  factory HistoricalEvent.fromJson(Map<String, dynamic> json) {
    return HistoricalEvent(
      id: json['id'] as String,
      name: json['name'] as String,
      category: json['category'] as String,
      description: json['description'] as String? ?? '',
      latitude: (json['latitude'] ?? json['center']?[1] ?? 0).toDouble(),
      longitude: (json['longitude'] ?? json['center']?[0] ?? 0).toDouble(),
      startDate: DateTime.parse(json['startDate'] as String),
      endDate: DateTime.parse(json['endDate'] as String),
      areaHectares: (json['areaHectares'] ?? 0).toDouble(),
      country: json['country'] as String? ?? '',
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
      frames: (json['frames'] as List<dynamic>?)
              ?.map((f) => TimelineFrame.fromJson(f as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'description': description,
        'latitude': latitude,
        'longitude': longitude,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate.toIso8601String(),
        'areaHectares': areaHectares,
        'country': country,
        'metadata': metadata,
      };

  /// Duration of the event.
  Duration get duration => endDate.difference(startDate);

  /// Human-readable date range.
  String get dateRange {
    final fmt = (DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return '${fmt(startDate)} to ${fmt(endDate)}';
  }

  /// Human-readable area string.
  String get areaDisplay {
    if (areaHectares >= 1000000) {
      return '${(areaHectares / 1000000).toStringAsFixed(1)}M ha';
    }
    return '${areaHectares.toStringAsFixed(0)} ha';
  }
}

class TimelineFrame {
  final DateTime date;
  final Map<String, dynamic> geojson;
  final Map<String, dynamic> stats;

  const TimelineFrame({
    required this.date,
    required this.geojson,
    this.stats = const {},
  });

  factory TimelineFrame.fromJson(Map<String, dynamic> json) {
    return TimelineFrame(
      date: DateTime.parse(json['date'] as String),
      geojson: (json['geojson'] as Map<String, dynamic>?) ?? {},
      stats: (json['stats'] as Map<String, dynamic>?) ?? {},
    );
  }

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'geojson': geojson,
        'stats': stats,
      };
}
