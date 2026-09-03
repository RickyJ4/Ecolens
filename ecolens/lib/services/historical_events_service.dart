import '../model/historical_event.dart';

/// Service that provides verified historical environmental event data
/// for timeline simulation playback on the MapLibre 3D map.
class HistoricalEventsService {
  HistoricalEventsService._();
  static final instance = HistoricalEventsService._();

  /// In-memory cache of the event catalog.
  List<HistoricalEvent>? _catalogCache;

  /// Cache for per-event timeline frames.
  final Map<String, List<TimelineFrame>> _framesCache = {};

  // ------------------------------------------------------------------
  //  VERIFIED EVENT CATALOG
  // ------------------------------------------------------------------

  static final List<Map<String, dynamic>> _rawCatalog = [
    // ---- WILDFIRES ----
    {
      'id': 'camp-fire-2018',
      'name': 'Camp Fire, Paradise CA',
      'category': 'wildfire',
      'description':
          'Deadliest California wildfire, destroyed town of Paradise. '
              '85 fatalities, 18,804 structures destroyed.',
      'latitude': 39.8102,
      'longitude': -121.4370,
      'startDate': '2018-11-08',
      'endDate': '2018-11-25',
      'areaHectares': 62053,
      'country': 'United States',
      'metadata': {
        'fatalities': 85,
        'structuresDestroyed': 18804,
        'cause': 'PG&E electrical transmission line',
        'source': 'NIFC / CAL FIRE',
      },
    },
    {
      'id': 'black-summer-2019',
      'name': 'Australian Black Summer',
      'category': 'wildfire',
      'description':
          'Largest Australian bushfire season on record. Over 3 billion animals affected.',
      'latitude': -36.68,
      'longitude': 149.85,
      'startDate': '2019-09-06',
      'endDate': '2020-03-04',
      'areaHectares': 5800000,
      'country': 'Australia',
      'metadata': {
        'fatalities': 33,
        'animalsAffected': '3 billion',
        'source': 'NSW Rural Fire Service',
      },
    },
    {
      'id': 'maui-lahaina-2023',
      'name': 'Maui Lahaina Fire',
      'category': 'wildfire',
      'description':
          'Deadliest US wildfire in over 100 years, destroyed historic Lahaina town.',
      'latitude': 20.8783,
      'longitude': -156.6825,
      'startDate': '2023-08-08',
      'endDate': '2023-08-11',
      'areaHectares': 890,
      'country': 'United States',
      'metadata': {
        'fatalities': 101,
        'structuresDestroyed': 2207,
        'cause': 'Downed power lines, high winds from Hurricane Dora',
        'source': 'Maui County / FEMA',
      },
    },
    {
      'id': 'canada-wildfires-2023',
      'name': 'Canadian Wildfires 2023',
      'category': 'wildfire',
      'description':
          'Record-breaking Canadian wildfire season. Smoke blanketed much of North America.',
      'latitude': 57.0,
      'longitude': -114.0,
      'startDate': '2023-05-01',
      'endDate': '2023-10-31',
      'areaHectares': 18400000,
      'country': 'Canada',
      'metadata': {
        'evacuees': 200000,
        'firesTotal': 6551,
        'source': 'Canadian Interagency Forest Fire Centre',
      },
    },

    // ---- FLOODS ----
    {
      'id': 'pakistan-floods-2022',
      'name': 'Pakistan Floods 2022',
      'category': 'flood',
      'description':
          'One-third of Pakistan submerged, 33 million people affected. Linked to climate change.',
      'latitude': 27.20,
      'longitude': 67.99,
      'startDate': '2022-06-14',
      'endDate': '2022-10-01',
      'areaHectares': 3049200,
      'country': 'Pakistan',
      'metadata': {
        'fatalities': 1739,
        'displaced': '33 million',
        'economicLoss': '\$30 billion',
        'source': 'NDMA Pakistan / UN OCHA',
      },
    },
    {
      'id': 'ahr-valley-2021',
      'name': 'Germany Ahr Valley Flood',
      'category': 'flood',
      'description':
          'Catastrophic flash flood killed 184 in Rhineland-Palatinate, '
              'worst German flood disaster in decades.',
      'latitude': 50.53,
      'longitude': 7.10,
      'startDate': '2021-07-14',
      'endDate': '2021-07-16',
      'areaHectares': 18000,
      'country': 'Germany',
      'metadata': {
        'fatalities': 184,
        'cause': 'Extreme rainfall — 148mm in 48 hours',
        'economicLoss': '\$40 billion',
        'source': 'DWD / Copernicus EMS',
      },
    },

    // ---- DROUGHT ----
    {
      'id': 'us-megadrought-2020',
      'name': 'US Western Mega-Drought',
      'category': 'drought',
      'description':
          'Worst drought in 1,200 years across western North America. '
              'Lake Mead hit record lows.',
      'latitude': 37.0,
      'longitude': -115.0,
      'startDate': '2020-01-01',
      'endDate': '2022-12-31',
      'areaHectares': 300000000,
      'country': 'United States',
      'metadata': {
        'peakSeverity': 'D4 Exceptional',
        'lakeMeadLevel': '1040 ft (record low)',
        'source': 'US Drought Monitor (USDM)',
      },
    },

    // ---- GLACIAL RETREAT ----
    {
      'id': 'jakobshavn-glacier',
      'name': 'Jakobshavn Glacier Retreat',
      'category': 'glacier',
      'description':
          'One of the fastest retreating glaciers on Earth, '
              'lost 97 billion tons of ice 1985-2022.',
      'latitude': 69.17,
      'longitude': -49.83,
      'startDate': '2000-01-01',
      'endDate': '2020-12-31',
      'areaHectares': 110000,
      'country': 'Greenland',
      'metadata': {
        'retreatDistance': '40+ km since 1850',
        'iceSpeed': '46 m/day',
        'source': 'NSIDC / ESA CryoSat',
      },
    },
    {
      'id': 'gangotri-glacier',
      'name': 'Gangotri Glacier Retreat',
      'category': 'glacier',
      'description':
          'Source of the Ganges River, retreated 1,850 meters in 28 years. '
              'Threatens water supply for millions.',
      'latitude': 30.92,
      'longitude': 79.17,
      'startDate': '1993-01-01',
      'endDate': '2021-12-31',
      'areaHectares': 14300,
      'country': 'India',
      'metadata': {
        'retreatDistance': '1,850 m (1993-2021)',
        'retreatRate': '~66 m/year',
        'source': 'GSI / ISRO',
      },
    },

    // ---- DEFORESTATION ----
    {
      'id': 'amazon-deforestation-2019',
      'name': 'Amazon Deforestation 2019-2023',
      'category': 'deforestation',
      'description':
          'Peak deforestation under weakened enforcement. '
              'Dramatic NDVI loss across Para state.',
      'latitude': -5.0,
      'longitude': -55.0,
      'startDate': '2019-01-01',
      'endDate': '2023-12-31',
      'areaHectares': 5100000,
      'country': 'Brazil',
      'metadata': {
        'annualPeak': '13,235 km2 (2021)',
        'source': 'INPE PRODES / Hansen GFC',
      },
    },
  ];

  // ------------------------------------------------------------------
  //  PUBLIC API
  // ------------------------------------------------------------------

  /// Returns the full event catalog.
  List<HistoricalEvent> getEventCatalog() {
    if (_catalogCache != null) return _catalogCache!;

    _catalogCache =
        _rawCatalog.map((j) => HistoricalEvent.fromJson(j)).toList();
    return _catalogCache!;
  }

  /// Get a single event by ID.
  HistoricalEvent? getEventDetails(String eventId) {
    return getEventCatalog().cast<HistoricalEvent?>().firstWhere(
          (e) => e?.id == eventId,
          orElse: () => null,
        );
  }

  /// Get events filtered by category.
  List<HistoricalEvent> getEventsByCategory(String category) {
    return getEventCatalog().where((e) => e.category == category).toList();
  }

  /// Available categories with display labels.
  static const Map<String, String> categories = {
    'wildfire': 'Wildfires',
    'flood': 'Floods',
    'drought': 'Drought',
    'glacier': 'Glacial Retreat',
    'deforestation': 'Deforestation',
  };

  /// Clear caches (useful for hot-reload).
  void clearCache() {
    _catalogCache = null;
    _framesCache.clear();
  }
}
