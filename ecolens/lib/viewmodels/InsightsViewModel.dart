import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ecolens/data/data_service.dart' show DataService;
import 'package:ecolens/model/location_model.dart';
import 'package:ecolens/views/widgets/atlas_finding_card.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class InsightsViewModel extends ChangeNotifier {
  final DataService _dataService = DataService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _newsSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _newsMetaSubscription;

  /// Set by dispose so a one-off Firestore read that lands afterwards
  /// (openNewsById) never notifies a disposed notifier.
  bool _disposed = false;

  // --- 🌍 ENVIRONMENTAL NEWS (GDACS mirror, refreshed server-side) ---
  /// When the server last refreshed the feed (UTC), from news_meta/latest.
  DateTime? newsUpdatedAt;

  /// Feed-wide counts published with each refresh: total, per type, per level.
  int newsCount = 0;
  Map<String, int> newsByType = const {};
  Map<String, int> newsByLevel = const {};

  /// Set when the stream errors (rules, offline). Shown instead of silence.
  String? newsError;

  // --- 🛰️ NEWS HUB STATE ---
  bool isLoading = true;
  bool isSectorAnalyzing = false;
  bool isDeepAnalyzing = false; // Layer 9-13 analysis
  bool isAnalysisSlow = false; // True if on-demand analysis is taking >8s
  String? analysisError; // Set when analysis times out or fails
  Timer? _slowAnalysisTimer;
  List<IntelligenceNode> allAlerts =
      []; // Global list for the independent News Center

  // The active target selected for Deep Dive analysis
  IntelligenceNode? _activeAlert;
  IntelligenceNode? get activeAlert => _activeAlert;

  Map<String, String> sectorForensics = {};
  List<FlSpot> historicDeforestation = [];

  // --- 🌟 LAYER 9-13: COMPREHENSIVE ANALYSIS DATA ---
  Map<String, dynamic> soilData = {}; // Layer 9: Soil Analysis
  Map<String, dynamic> terrainData = {}; // Layer 10: Terrain Analysis
  Map<String, dynamic> hydrologyData = {}; // Layer 11: Hydrology Analysis
  Map<String, dynamic> historicalData = {}; // Layer 12: Historical Trends
  Map<String, dynamic> comprehensiveData = {}; // Layer 13: AI Synthesis
  Map<String, dynamic> riskData = {}; // New: Risk Prediction
  Map<String, dynamic> sentinelData = {}; // New: Sentinel Verification
  Map<String, dynamic> gisData = {}; // New: Spatial/GIS Analysis

  int recoveryScore = 0;
  String successProbability = 'Unknown';
  Map<String, dynamic> actionPlan = {};

  InsightsViewModel() {
    _initGlobalNewsUplink();
  }

  /// 🌍 ENVIRONMENTAL NEWS: streams the `news_feed` collection, which the
  /// refresh_environmental_news Cloud Function keeps in step with the GDACS
  /// RSS every 15 minutes. Firestore pushes each change, so the page is as
  /// current as the last server refresh with no polling from the client.
  /// Ordered by sort_key: Red, then Orange, then Green alerts, and the most
  /// recent activity first within each level.
  void _initGlobalNewsUplink() {
    _newsSubscription = _firestore
        .collection('news_feed')
        .orderBy('sort_key')
        .limit(120)
        .snapshots()
        .listen(
      (snapshot) {
        final nodes = <IntelligenceNode>[];
        for (final doc in snapshot.docs) {
          final node = _newsDocToNode(doc.id, doc.data());
          if (node != null) nodes.add(node);
        }
        allAlerts = nodes;
        newsError = null;
        isLoading = false;
        notifyListeners();
      },
      onError: (error) {
        debugPrint('[Insights] news_feed stream error: $error');
        newsError = 'The news feed could not be read: $error';
        isLoading = false;
        notifyListeners();
      },
    );

    _newsMetaSubscription = _firestore
        .collection('news_meta')
        .doc('latest')
        .snapshots()
        .listen(
      (snap) {
        final m = snap.data();
        if (m == null) return;
        final ms = m['updated_at_ms'];
        newsUpdatedAt = ms is num
            ? DateTime.fromMillisecondsSinceEpoch(ms.toInt(), isUtc: true)
            : DateTime.tryParse((m['updated_at'] ?? '').toString());
        newsCount = (m['count'] is num) ? (m['count'] as num).toInt() : 0;
        newsByType = _intMap(m['by_type']);
        newsByLevel = _intMap(m['by_level']);
        notifyListeners();
      },
      onError: (e) => debugPrint('[Insights] news_meta stream error: $e'),
    );
  }

  Map<String, int> _intMap(dynamic raw) {
    if (raw is! Map) return const {};
    return {
      for (final e in raw.entries)
        if (e.value is num) e.key.toString(): (e.value as num).toInt(),
    };
  }

  List<Map<String, dynamic>> _mapList(dynamic raw) {
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if (e is Map) Map<String, dynamic>.from(e),
    ];
  }

  /// Opens a news item in the report view WITHOUT the deep-analysis chain
  /// that selectAlert runs (temporal trends, forensic and comprehensive
  /// analysis). Those would spend model calls generating soil, terrain and
  /// risk prose about a wire item: exactly the unsourced content EcoLens
  /// refuses to show.
  void openNewsItem(IntelligenceNode node) {
    _activeAlert = node;
    notifyListeners();
  }

  /// Opens a story by its GDACS guid, which is the news_feed document id
  /// (for example "FL1104124"); the map screen calls this when a reader
  /// taps a story. An item already on the streamed wire opens at once. One
  /// outside the 120-document window is read once from Firestore and
  /// opened when it arrives; nothing opens if the document does not exist.
  void openNewsById(String id) {
    final guid = id.trim();
    if (guid.isEmpty) return;
    for (final node in allAlerts) {
      if (node.id == guid) {
        openNewsItem(node);
        return;
      }
    }
    _fetchAndOpenNews(guid);
  }

  Future<void> _fetchAndOpenNews(String guid) async {
    try {
      final snap = await _firestore.collection('news_feed').doc(guid).get();
      if (_disposed) return;
      final data = snap.data();
      if (data == null) {
        debugPrint('[Insights] news_feed/$guid does not exist');
        return;
      }
      final node = _newsDocToNode(snap.id, data);
      if (node != null) openNewsItem(node);
    } catch (e) {
      debugPrint('[Insights] news_feed/$guid could not be read: $e');
    }
  }

  /// One `news_feed` document (mirrored from the GDACS RSS by
  /// refresh_environmental_news) as an IntelligenceNode, so the existing
  /// report view and share card work unchanged. Every field is copied from
  /// the feed. causeData carries the published alert level, severity,
  /// population statement, dates and report link for the report view.
  IntelligenceNode? _newsDocToNode(String docId, Map<String, dynamic> d) {
    try {
      String s(String k) => (d[k] ?? '').toString();
      double n(String k) => (d[k] is num) ? (d[k] as num).toDouble() : 0.0;
      final typeLabel =
          s('type_label').isNotEmpty ? s('type_label') : s('event_type');
      final headline = s('headline').isNotEmpty ? s('headline') : s('title');
      final link = s('link');
      final country = s('country');
      // The EcoLens reading: what EcoLens's own layers show around the
      // event (FIRMS fires, USGS quakes, the Open-Meteo air model, the
      // gazetteer, the wire itself), the sentences built only from those
      // figures, and an editorial that exists only when every check passed.
      // Written server-side; null until then, and the story shows nothing
      // for it until then.
      final reading = (d['ecolens_reading'] is Map)
          ? Map<String, dynamic>.from(d['ecolens_reading'] as Map)
          : null;
      String readingSource(String block, String fallback) {
        final b = reading?[block];
        final src = b is Map ? (b['source'] ?? '').toString().trim() : '';
        return src.isEmpty ? fallback : src;
      }

      return IntelligenceNode(
        id: docId,
        type: typeLabel.toLowerCase(),
        headline: headline,
        backgroundInfo: s('description'),
        lat: n('lat'),
        lng: n('lon'),
        hectares: 0,
        continent: '',
        country: country,
        region: '',
        provinceState: '',
        riskScore: 0,
        riskScored: false,
        aiForecast: [],
        legalStatus: const LegalStatus(),
        causeData: {
          'source': 'GDACS',
          // Read by the card and report as the published alert level.
          'severity': s('alert_level'),
          'alert_level': s('alert_level'),
          'event_type': s('event_type'),
          'type_label': typeLabel,
          'event_name': s('event_name'),
          'severity_text': s('severity_text'),
          'population_text': s('population_text'),
          'from_date': s('from_date'),
          'to_date': s('to_date'),
          'last_activity': s('last_activity'),
          'is_current': d['is_current'] == true,
          'url': link,
          'title': s('title'),
          // Report-page detail, copied by refresh_environmental_news from the
          // GDACS detail API and report page. Absent until that event has
          // been enriched; the UI shows nothing for absent fields.
          'affected_countries': _stringList(d['affected_countries']),
          'duration_days': (d['duration_days'] is num)
              ? (d['duration_days'] as num).toInt()
              : null,
          'impact_statement': s('impact_statement'),
          'affected_area_km2': (d['affected_area_km2'] is num)
              ? (d['affected_area_km2'] as num).toDouble()
              : null,
          'affected_area_basis': s('affected_area_basis'),
          'affected_zones': _mapList(d['affected_zones']),
          'impact_reports': _mapList(d['impact_reports']),
          'impact_headline': (d['impact_headline'] is Map)
              ? Map<String, dynamic>.from(d['impact_headline'] as Map)
              : null,
          'exposure': (d['exposure'] is Map)
              ? Map<String, dynamic>.from(d['exposure'] as Map)
              : null,
          'map_images': _mapList(d['map_images']),
          'products': _mapList(d['products']),
          'documents': _mapList(d['documents']),
          'glide': s('glide'),
          'report_url': s('report_url').isNotEmpty ? s('report_url') : link,
          'enriched_at': s('enriched_at'),
          'activations': _mapList(d['activations']),
          // The story: dateline, headline, standfirst, paragraphs with their
          // sources, timeline and press list, composed server-side from
          // published fields only.
          'article': (d['article'] is Map)
              ? Map<String, dynamic>.from(d['article'] as Map)
              : null,
          // Rendered by the story view as "EcoLens's reading"; null renders
          // nothing there, not a placeholder.
          'ecolens_reading': reading,
        },
        fireData: const FireData(),
        carbonData: const CarbonData(),
        waterResources: const WaterResources(),
        faunaAtRisk: [],
        floraAtRisk: [],
        faunaThrive: [],
        floraThrive: [],
        population: 0,
        settlementsCount: 0,
        nearestSettlementKm: 0,
        displacementRisk: '',
        livelihoodsAtRisk: [],
        healthImpacts: [],
        economicImpacts: const EconomicImpact(),
        landFeatures: [],
        reforestZone: const ReforestZone(),
        urgency: const Urgency(),
        recommendedActions: [],
        trendDirection: '',
        trendChangePercent: 0,
        forecast2026: 0,
        yearlyHistory: {},
        dataSources: [
          DataSource(
            name: 'GDACS (Global Disaster Alert and Coordination System)',
            url: link.isNotEmpty ? link : 'https://www.gdacs.org',
          ),
          // The layers behind the EcoLens reading, named by the source
          // string the reading itself carries, so the Sources card lists
          // every origin on the page.
          if (reading?['fires'] is Map)
            DataSource(
              name: '${readingSource('fires', 'NASA FIRMS')}, '
                  'for the EcoLens reading',
              url: 'https://firms.modaps.eosdis.nasa.gov/',
            ),
          if (reading?['quakes'] is Map)
            DataSource(
              name: '${readingSource('quakes', 'USGS earthquake catalog')}, '
                  'for the EcoLens reading',
              url: 'https://earthquake.usgs.gov/',
            ),
          if (reading?['air'] is Map)
            DataSource(
              name:
                  '${readingSource('air', 'Open-Meteo air-quality model')}, '
                  'for the EcoLens reading',
              url: 'https://open-meteo.com/',
            ),
        ],
        soilAnalysis: {},
        terrainAnalysis: {},
        hydrologyAnalysis: {},
        historicalAnalysis: {},
        recoveryPotential: {},
        comprehensiveAnalysis: {},
        sentinelVerification: {},
        gisAnalysis: {},
        riskPrediction: {},
        soilType: '',
        soilPH: 0,
        soilFertility: '',
        terrainSlope: 0,
        terrainDifficulty: '',
        terrainElevation: 0,
        waterAccess: '',
      );
    } catch (e) {
      debugPrint('[Insights] Failed to read news_feed/$docId: $e');
      return null;
    }
  }

  /// Dismiss the analysis error banner (called from the UI tap handler).
  void dismissAnalysisError() {
    if (analysisError == null) return;
    analysisError = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _newsSubscription?.cancel();
    _newsMetaSubscription?.cancel();
    _slowAnalysisTimer?.cancel();
    super.dispose();
  }

  // --- 📈 TREND ANALYTICS ENGINE ---

  /// Calculates the percentage change in forest loss for the Trend Indicator
  /// Returns a formatted string like "↑ 12.5% vs Last Period" or "STABLE"
  String getTrendAnalysis(IntelligenceNode node) {
    if (node.yearlyHistory.length < 2) return "STABLE";

    // Sort years to get the two most recent data points chronologically
    final sortedYears = node.yearlyHistory.keys.toList()..sort();
    final currentYearLoss = node.yearlyHistory[sortedYears.last] ?? 0.0;
    final previousYearLoss =
        node.yearlyHistory[sortedYears[sortedYears.length - 2]] ?? 0.0;

    if (previousYearLoss == 0) return "NEW ALERT";

    double percentChange =
        ((currentYearLoss - previousYearLoss) / previousYearLoss) * 100;

    String prefix = percentChange >= 0 ? "↑" : "↓";
    return "$prefix ${percentChange.abs().toStringAsFixed(1)}% vs Last Period";
  }

  // --- 🎯 TARGET ACQUISITION ---

  /// Transitions from News Feed to Detailed Forensic Report
  void selectAlert(IntelligenceNode node) {
    _activeAlert = node;
    _processTemporalTrends(node);
    _runDeepForensicAnalysis(node);
    // 🌟 Trigger Layer 9-13 comprehensive analysis
    fetchComprehensiveAnalysis();
    notifyListeners();
  }

  // --- ATLAS FINDINGS (escalated from the map screen) ---

  /// Findings the Atlas agent produced for questions the map could not answer
  /// on its own — a ranked comparison, its sources and its stated limits.
  /// Newest first; the map screen pushes these across the JS bridge.
  final List<AtlasFinding> atlasFindings = <AtlasFinding>[];

  /// Accepts a finding escalated from the map. Re-asking the same question
  /// replaces the previous answer rather than stacking a duplicate.
  void addAtlasFinding(AtlasFinding finding) {
    atlasFindings.removeWhere(
      (f) =>
          f.id == finding.id ||
          (f.question.isNotEmpty && f.question == finding.question),
    );
    atlasFindings.insert(0, finding);
    // A reader can only hold so many; keep the recent ones.
    if (atlasFindings.length > 8) {
      atlasFindings.removeRange(8, atlasFindings.length);
    }
    notifyListeners();
  }

  void dismissAtlasFinding(String id) {
    final before = atlasFindings.length;
    atlasFindings.removeWhere((f) => f.id == id);
    if (atlasFindings.length != before) notifyListeners();
  }

  /// Opens a live or historical map event as a complete Insights report.
  ///
  /// MapLibre events are already intelligence products, so this avoids routing
  /// them through the deforestation-specific on-demand analysis fallback.
  void selectMapEvent(Map<String, dynamic> event) {
    final node = _buildNodeFromMapEvent(event);
    _activeAlert = node;
    _processTemporalTrends(node);

    sectorForensics = {
      'classification': node.type,
      'primary_signal': node.causeData['type']?.toString() ?? node.type,
      'drivers': node.causeData['drivers']?.toString() ?? 'Not specified',
      'pattern': node.causeData['pattern']?.toString() ?? 'Pattern pending',
      'confidence':
          node.causeData['confidence']?.toString() ?? 'Confidence pending',
      'source': node.causeData['source']?.toString() ?? 'Source pending',
    };

    soilData = node.soilAnalysis;
    terrainData = node.terrainAnalysis;
    hydrologyData = node.hydrologyAnalysis;
    historicalData = node.historicalAnalysis;
    riskData = node.riskPrediction;
    sentinelData = node.sentinelVerification;
    gisData = node.gisAnalysis;
    comprehensiveData = node.comprehensiveAnalysis;
    recoveryScore = node.recoveryScore.toInt();
    successProbability = node.successProbability;
    actionPlan = Map<String, dynamic>.from(
      node.comprehensiveAnalysis['action_plan'] as Map? ?? {},
    );
    isSectorAnalyzing = false;
    isDeepAnalyzing = false;
    notifyListeners();
  }

  /// Exits the Deep Dive view and returns to the News Center list
  void clearActiveAlert() {
    _activeAlert = null;
    sectorForensics = {};
    historicDeforestation = [];
    _clearLayeredData();
    notifyListeners();
  }

  // --- 📐 ANALYTICS ENGINE ---

  void _processTemporalTrends(IntelligenceNode node) {
    if (node.yearlyHistory.isEmpty) {
      historicDeforestation = [];
      return;
    }
    final sortedYears = node.yearlyHistory.keys.toList()..sort();
    double xIndex = 0;
    historicDeforestation = sortedYears.map((yearStr) {
      double hectareLoss = node.yearlyHistory[yearStr] ?? 0.0;
      return FlSpot(xIndex++, hectareLoss);
    }).toList();
  }

  Future<void> _runDeepForensicAnalysis(IntelligenceNode node) async {
    isSectorAnalyzing = true;
    notifyListeners();
    try {
      sectorForensics = await _dataService.analyzeSectorCoordinates(
        node.lat,
        node.lng,
      );
    } catch (e) {
      sectorForensics = {"error": "Satellite Uplink Failed"};
    } finally {
      isSectorAnalyzing = false;
      notifyListeners();
    }
  }

  /// 🌟 LAYER 9-16: FETCH COMPREHENSIVE ANALYSIS
  /// Now reads directly from the node instead of making a separate API call
  Future<void> fetchComprehensiveAnalysis() async {
    if (_activeAlert == null) return;

    debugPrint(
      '🚀 fetchComprehensiveAnalysis called for coords: ${_activeAlert!.lat}, ${_activeAlert!.lng}',
    );
    isDeepAnalyzing = true;
    notifyListeners();

    try {
      // Read agent analysis data directly from the node (stored in database)
      soilData = _activeAlert!.soilAnalysis;
      terrainData = _activeAlert!.terrainAnalysis;
      hydrologyData = _activeAlert!.hydrologyAnalysis;
      historicalData = _activeAlert!.historicalAnalysis;
      riskData = _activeAlert!.riskPrediction;
      sentinelData = _activeAlert!.sentinelVerification;
      gisData = _activeAlert!.gisAnalysis;
      comprehensiveData = _activeAlert!.comprehensiveAnalysis;

      debugPrint('📦 Loaded agent data from node:');
      debugPrint('  - Soil: ${soilData.isNotEmpty ? "✓" : "✗"}');
      debugPrint('  - Terrain: ${terrainData.isNotEmpty ? "✓" : "✗"}');
      debugPrint('  - Hydrology: ${hydrologyData.isNotEmpty ? "✓" : "✗"}');
      debugPrint('  - Historical: ${historicalData.isNotEmpty ? "✓" : "✗"}');
      debugPrint('  - Risk: ${riskData.isNotEmpty ? "✓" : "✗"}');
      debugPrint('  - Sentinel: ${sentinelData.isNotEmpty ? "✓" : "✗"}');
      debugPrint('  - GIS: ${gisData.isNotEmpty ? "✓" : "✗"}');
      debugPrint(
        '  - Comprehensive: ${comprehensiveData.isNotEmpty ? "✓" : "✗"}',
      );

      // Parse Recovery Potential
      var rp = _activeAlert!.recoveryPotential;
      if (rp.isNotEmpty) {
        recoveryScore = (rp['score'] ?? 0).toInt();
        debugPrint('🔢 recoveryScore: $recoveryScore');
      }

      // Parse Comprehensive Analysis details
      if (comprehensiveData.isNotEmpty) {
        successProbability =
            comprehensiveData['success_probability']?.toString() ?? 'Unknown';
        actionPlan = comprehensiveData['action_plan'] is Map
            ? Map<String, dynamic>.from(comprehensiveData['action_plan'] as Map)
            : {};
      }

      // If no agent data is available, use fallback OR trigger on-demand analysis
      if (soilData.isEmpty && terrainData.isEmpty && hydrologyData.isEmpty) {
        debugPrint(
          "⚠️ No agent data found in node. Attempting on-demand analysis...",
        );
        await _triggerOnDemandAnalysis();
      } else {
        debugPrint('✅ Agent analysis data loaded successfully');
      }
    } catch (e) {
      debugPrint('❌ Comprehensive Analysis Error: $e');
      analysisError =
          'Analysis failed. No data available for this location yet.';
      _clearLayeredData();
    } finally {
      isDeepAnalyzing = false;
      notifyListeners();
    }
  }

  /// Trigger on-demand analysis for nodes that don't have agent data yet.
  /// Cloud Function cold starts can take 5–30s on Python 1GB instances;
  /// we surface a "taking longer than expected" hint after 8s and hard-
  /// timeout at 30s so the UI never freezes indefinitely.
  Future<void> _triggerOnDemandAnalysis() async {
    if (_activeAlert == null) return;

    analysisError = null;
    isAnalysisSlow = false;
    _slowAnalysisTimer?.cancel();
    _slowAnalysisTimer = Timer(const Duration(seconds: 8), () {
      isAnalysisSlow = true;
      notifyListeners();
    });

    try {
      debugPrint('🔄 Triggering on-demand analysis via analyze_location...');
      final data = await _dataService
          .getComprehensiveAnalysis(_activeAlert!.lat, _activeAlert!.lng)
          .timeout(const Duration(seconds: 30));

      if (data.containsKey('error') || data.isEmpty) {
        debugPrint("⚠️ On-demand analysis failed.");
        analysisError =
            'No analysis data available for this location yet. Try a hotspot the deep-dive pipeline has already processed.';
        _clearLayeredData();
        return;
      }

      // Safe Parsing Helper
      Map<String, dynamic> safeMap(String key) {
        if (data[key] == null) return {};
        try {
          return Map<String, dynamic>.from(data[key] as Map);
        } catch (e) {
          debugPrint("⚠️ Error casting key $key: $e");
          return {};
        }
      }

      // Parsing all layers from on-demand analysis
      soilData = safeMap('soil_analysis');
      terrainData = safeMap('terrain_analysis');
      hydrologyData = safeMap('hydrology_analysis');
      historicalData = safeMap('historical_analysis');
      riskData = safeMap('risk_prediction');
      sentinelData = safeMap('sentinel_verification');
      gisData = safeMap('gis_analysis');
      comprehensiveData = safeMap('comprehensive_analysis');

      // Parse Recovery Potential
      if (data.containsKey('recovery_potential')) {
        var rp = data['recovery_potential'];
        if (rp is Map) {
          recoveryScore = rp['score'] ?? 0;
        }
      }

      // Parse action plan
      successProbability =
          comprehensiveData['success_probability']?.toString() ?? 'Unknown';
      actionPlan = comprehensiveData['action_plan'] is Map
          ? Map<String, dynamic>.from(comprehensiveData['action_plan'] as Map)
          : {};

      debugPrint('✅ On-demand analysis complete');
    } on TimeoutException {
      debugPrint('⏱️ On-demand analysis timed out after 30s');
      analysisError =
          'Analysis took too long (server cold-starting). Pull down to retry.';
      _clearLayeredData();
    } catch (e) {
      debugPrint('❌ On-demand analysis failed: $e');
      analysisError = 'Analysis failed. No data shown until retry succeeds.';
      _clearLayeredData();
    } finally {
      _slowAnalysisTimer?.cancel();
      _slowAnalysisTimer = null;
      isAnalysisSlow = false;
    }
  }

  /// Clears all data when exiting detailed view or when analysis fails.
  /// No synthetic fallback is generated — empty data renders an honest
  /// empty state instead of fabricated soil/terrain/hydrology numbers.
  void _clearLayeredData() {
    soilData = {};
    terrainData = {};
    hydrologyData = {};
    historicalData = {};
    comprehensiveData = {};
    riskData = {};
    sentinelData = {};
    gisData = {};
    recoveryScore = 0;
    successProbability = 'Unknown';
    actionPlan = {};
  }

  IntelligenceNode _buildNodeFromMapEvent(Map<String, dynamic> event) {
    final category = _string(
      event['type'] ?? event['category'],
      'environmental',
    );
    final isHistorical =
        event['startDate'] != null || event['areaHectares'] != null;
    final origin =
        _coordinatePair(event['origin']) ?? _coordinatePair(event['center']);
    final lat = _number(event['lat'], origin?[1] ?? 0.0);
    final lng = _number(event['lng'], origin?[0] ?? 0.0);
    final radiusKm = _number(
      event['impactRadiusKm'],
      isHistorical
          ? _radiusFromHectares(_number(event['areaHectares'], 10000))
          : _defaultRadiusFor(category),
    );
    // Area only when the event carries a measured one. The watch radius is an
    // EcoLens display choice, not an observed burn/flood extent, so its circle
    // area is never used as hectares.
    final hectares = _number(event['areaHectares'], 0);
    // The feed's own severity word, carried through as a label. It is never
    // converted into a percentage: no probability was ever measured.
    final severity = _string(event['sev'], '').trim();
    final rawRiskScore = event['riskScore'];
    final riskScored = rawRiskScore is num;
    final riskScore = riskScored ? rawRiskScore.toDouble() : 0.0;
    final title = _string(
      event['title'] ?? event['name'],
      _typeLabel(category),
    );
    final location = _string(event['loc'] ?? event['country'], 'Map event');
    final country = _string(event['country'], _countryFromLocation(location));
    final source = _string(
      event['source'] ?? _metadata(event)['source'],
      'EcoLens map intelligence',
    );
    final drivers = _string(
      event['drivers'] ?? _metadata(event)['cause'],
      _driversFor(category),
    );
    final pattern = _string(
      event['pattern'],
      _patternFor(category, isHistorical: isHistorical),
    );
    final forecast = _string(event['forecast'], _forecastFor(category));
    final description = _string(event['desc'] ?? event['description'], '');
    final status = _string(
      event['status'],
      isHistorical ? 'historical case' : 'active signal',
    );
    final confidence = _string(
      event['confidence'],
      isHistorical ? 'documented event' : 'model/source confidence pending',
    );
    final eventId = _string(
      event['id'],
      'map_event_${DateTime.now().millisecondsSinceEpoch}',
    );
    final startDate = _string(event['startDate'], '');
    final endDate = _string(event['endDate'], '');
    final time = _string(event['time'], startDate);
    final metadata = _metadata(event);
    final evidenceLabel = _string(event['evidenceLabel'], '');
    final evidenceNote = _string(event['evidenceNote'], '');
    final localImpacts = _stringList(event['localImpacts']);
    final timeline = event['timeline'] is List
        ? List<Map<String, dynamic>>.from(
            (event['timeline'] as List).whereType<Map>().map(
              (item) => Map<String, dynamic>.from(item),
            ),
          )
        : <Map<String, dynamic>>[];

    return IntelligenceNode(
      id: eventId,
      type: _typeLabel(category),
      headline: title,
      backgroundInfo: _backgroundFor(
        title: title,
        category: category,
        description: description,
        location: location,
        drivers: drivers,
        pattern: pattern,
        forecast: forecast,
        source: source,
        radiusKm: radiusKm,
        isHistorical: isHistorical,
        startDate: startDate,
        endDate: endDate,
      ),
      lat: lat,
      lng: lng,
      hectares: hectares,
      continent: '',
      country: country,
      region: location,
      provinceState: location,
      riskScore: riskScore,
      riskScored: riskScored,
      legalStatus: LegalStatus(
        enforcementJurisdiction: _jurisdictionFor(country),
      ),
      causeData: {
        'type': category,
        'drivers': drivers,
        'pattern': pattern,
        'forecast': forecast,
        'source': source,
        'confidence': confidence,
        'status': status,
        if (severity.isNotEmpty) 'severity': severity,
        'impact_radius_km': radiusKm,
        'event_id': eventId,
        'observed_time': time,
        if (evidenceLabel.isNotEmpty) 'map_evidence': evidenceLabel,
        if (evidenceNote.isNotEmpty) 'evidence_note': evidenceNote,
        if (localImpacts.isNotEmpty) 'local_impacts': localImpacts,
        'weather_linked':
            event['weatherLinked'] == true ||
            ['wildfire', 'flood', 'drought', 'airquality'].contains(category),
        ...metadata,
      },
      fireData: FireData(
        // activeFires stays 0: the map event carries no detection count, and a
        // constant 1 presented as a zone count is a fabricated measurement.
        // fireRiskLevel stays empty: it was the severity word turned into a
        // number and back, which reads as an independent EcoLens rating.
        fireRadiativePower: _extractFrp(description),
        burnAreaHa: category == 'wildfire' ? hectares : 0,
        lastFireDate: time,
      ),
      // No carbonData: one global carbon density over an unmeasured area is
      // not a measurement.
      waterResources: WaterResources(
        watershedName: category == 'flood' || category == 'drought'
            ? 'Local watershed verification required'
            : '',
        floodRiskIncrease: category == 'flood'
            ? 'HIGH'
            : category == 'wildfire'
            ? 'POST-FIRE ELEVATED'
            : 'LOW',
        aquiferImpact: category == 'drought'
            ? 'Potential groundwater stress and supply pressure'
            : '',
      ),
      // population, settlementsCount and nearestSettlementKm are left at 0.
      // They were computed from the watch-radius circle; only a figure that
      // arrives on the event payload from a named source (OSM / WorldPop /
      // GHSL) may ever populate them.
      displacementRisk: _displacementRiskFor(severity),
      // No livelihoodsAtRisk or healthImpacts: both were fixed per-category
      // word lists keyed off nothing but the event type, and the brief renders
      // them under "What's at risk" for a named place. No settlement, worker,
      // resident or PM2.5 reading was observed at this point. Only lists that
      // arrive on the event payload from a named source may populate them.
      economicImpacts: EconomicImpact(
        // No longTermLossUsd: a constant times a circle's area is not an
        // economic loss estimate for any specific event. The breakdown below
        // is qualitative — it names cost categories, not amounts.
        lossBreakdown: _lossBreakdownFor(category),
        localCommunityImpact: _communityImpactFor(category),
        industriesAffected: _industriesFor(category),
      ),
      landFeatures: [
        LandFeature(
          name: location,
          type: category,
          impactDescription: pattern,
          lat: lat,
          lng: lng,
        ),
      ],
      // No reforestZone: the suitability score was a flat 62 for fire and
      // deforestation events regardless of site, and the sequestration figure
      // was a constant over an unmeasured area.
      urgency: Urgency(
        level: _urgencyLevelFor(severity),
        interventionWindowDays: _interventionWindowFor(category, isHistorical),
        irreversibilityRisk: _irreversibilityFor(category),
        tippingPointProximity: pattern,
      ),
      recommendedActions: _recommendedActionsFor(category, severity),
      // No trend: there is no previous period in this data, so no change can
      // be computed and no year can be forecast. yearlyHistory is left empty
      // for the same reason — the old series was the current area scaled by
      // fixed multipliers.
      dataSources: [
        DataSource(name: source, lastUpdated: time),
        const DataSource(name: 'EcoLens event intelligence'),
      ],
      // No soilAnalysis or terrainAnalysis: both returned identical soil
      // chemistry and elevation for every point on earth. The empty state is
      // the honest one.
      hydrologyAnalysis: _hydrologyIntelFor(category),
      historicalAnalysis: {
        'available': true,
        'event_id': eventId,
        'start_date': startDate,
        'end_date': endDate,
        'narrative': _historicalNarrative(
          title: title,
          category: category,
          description: description,
          drivers: drivers,
          pattern: pattern,
          metadata: metadata,
          isHistorical: isHistorical,
        ),
        if (evidenceLabel.isNotEmpty) 'map_evidence': evidenceLabel,
        if (evidenceNote.isNotEmpty) 'evidence_note': evidenceNote,
        if (localImpacts.isNotEmpty) 'local_impacts': localImpacts,
        if (timeline.isNotEmpty) 'timeline': timeline,
        'metrics': metadata,
      },
      recoveryPotential: {'score': _recoveryScoreFor(category, severity)},
      comprehensiveAnalysis: {
        'available': true,
        'success_probability': _successProbabilityFor(severity),
        'summary': localImpacts.isNotEmpty
            ? '$title is anchored to local evidence: ${localImpacts.take(2).join(' ')}'
            : '$title requires ${_typeLabel(category).toLowerCase()}-specific response, exposure mapping, and source verification.',
        'action_plan': _actionPlanFor(category),
      },
      sentinelVerification: {
        'available': true,
        'metadata': {
          'data_source': source,
          'confidence': confidence,
          'status': status,
          if (evidenceLabel.isNotEmpty) 'map_evidence': evidenceLabel,
          if (evidenceNote.isNotEmpty) 'evidence_note': evidenceNote,
        },
        'imagery': {
          'before_date_range': startDate.isNotEmpty
              ? startDate
              : 'Recent baseline required',
          'after_date_range': endDate.isNotEmpty
              ? endDate
              : 'Current acquisition required',
          'resolution_m': isHistorical ? 10 : 375,
        },
        // No vegetation_indices: nothing here touched a Sentinel scene, and a
        // reader seeing an NDVI change would believe imagery was differenced.
      },
      // No gisAnalysis: the distances and buffer areas were hardcoded while
      // declaring themselves available. Real proximity analysis belongs to the
      // map's OSM-verified drawer.
      riskPrediction: {
        'available': true,
        // No risk_probability: dividing a lookup-table constant by 100 does
        // not make it a probability.
        if (severity.isNotEmpty) 'severity': severity.toUpperCase(),
        'risk_description': forecast,
        'primary_risk_factors': _riskFactorsFor(category, drivers, pattern),
        'recommendations': _recommendationStringsFor(category),
        'metadata': {
          'method': isHistorical
              ? 'historical event reconstruction'
              : 'live event triage from map layers',
          'source': source,
        },
      },
      recoveryScore: _recoveryScoreFor(category, severity).toDouble(),
      successProbability: _successProbabilityFor(severity),
    );
  }

  double _number(dynamic value, [double fallback = 0]) {
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value.replaceAll(',', '')) ?? fallback;
    }
    return fallback;
  }

  String _string(dynamic value, [String fallback = '']) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty || text == 'null' ? fallback : text;
  }

  List<String> _stringList(dynamic value) {
    if (value is List) {
      return value
          .map((item) => item?.toString().trim() ?? '')
          .where((item) => item.isNotEmpty && item != 'null')
          .toList();
    }
    return const [];
  }

  Map<String, dynamic> _metadata(Map<String, dynamic> event) {
    final raw = event['metadata'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return {};
  }

  List<double>? _coordinatePair(dynamic value) {
    if (value is List && value.length >= 2) {
      return [_number(value[0]), _number(value[1])];
    }
    return null;
  }

  double _radiusFromHectares(double hectares) {
    final km2 = hectares / 100;
    if (km2 <= 0) return 10;
    final radius = (km2 / 3.141592653589793);
    return radius <= 0 ? 10 : radius.clamp(5, 180).toDouble();
  }

  double _defaultRadiusFor(String category) {
    switch (category) {
      case 'quake':
        return 60;
      case 'volcano':
        return 45;
      case 'drought':
        return 75;
      case 'airquality':
        return 50;
      case 'flood':
        return 22;
      case 'wildfire':
        return 18;
      default:
        return 25;
    }
  }

  /// Rank of the feed's own severity word, used only to pick qualitative
  /// wording and advice. It is never rendered as a number.
  int _severityRank(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
      case 'extreme':
        return 3;
      case 'high':
        return 2;
      case 'medium':
      case 'moderate':
        return 1;
      default:
        return 0;
    }
  }

  String _urgencyLevelFor(String severity) {
    switch (_severityRank(severity)) {
      case 3:
        return 'CRITICAL';
      case 2:
        return 'ELEVATED';
      default:
        return 'WATCH';
    }
  }

  String _displacementRiskFor(String severity) {
    switch (_severityRank(severity)) {
      case 3:
        return 'HIGH';
      case 2:
        return 'MEDIUM';
      default:
        return 'LOW';
    }
  }

  String _successProbabilityFor(String severity) {
    return _severityRank(severity) >= 3 ? 'Guarded' : 'Moderate';
  }

  String _typeLabel(String category) {
    switch (category) {
      case 'wildfire':
        return 'Wildfire';
      case 'flood':
        return 'Flood';
      case 'drought':
        return 'Drought';
      case 'airquality':
        return 'Air Quality';
      case 'quake':
        return 'Earthquake';
      case 'volcano':
        return 'Volcano';
      case 'glacier':
        return 'Glacial Retreat';
      case 'deforestation':
        return 'Deforestation';
      default:
        return 'Environmental Event';
    }
  }

  String _countryFromLocation(String location) {
    final parts = location.split(',');
    return parts.length > 1 ? parts.last.trim() : '';
  }

  String _driversFor(String category) {
    switch (category) {
      case 'wildfire':
        return 'heat anomaly, dry fuels, wind exposure';
      case 'flood':
        return 'heavy rainfall, runoff, stream stage';
      case 'drought':
        return 'precipitation deficit, heat, vegetation stress';
      case 'airquality':
        return 'smoke transport, stagnant air, temperature inversion';
      case 'quake':
        return 'tectonic rupture, local site amplification';
      case 'volcano':
        return 'volcanic unrest; wind controls ash exposure';
      case 'glacier':
        return 'warming, ice dynamics, meltwater feedbacks';
      default:
        return 'environmental pressure signal';
    }
  }

  String _patternFor(String category, {required bool isHistorical}) {
    final prefix = isHistorical ? 'Historical reconstruction: ' : '';
    switch (category) {
      case 'wildfire':
        return '${prefix}fire behavior shaped by fuels, wind, terrain, and suppression access.';
      case 'flood':
        return '${prefix}inundation follows low-lying corridors, channel capacity, and antecedent saturation.';
      case 'drought':
        return '${prefix}water stress accumulates across soil moisture, vegetation health, and supply systems.';
      case 'airquality':
        return '${prefix}exposure follows wind transport, stagnation, inversions, and nearby emissions.';
      case 'quake':
        return '${prefix}impact decays with distance but can intensify in soft soils and dense settlements.';
      case 'volcano':
        return '${prefix}ash and lahar risk depend on eruption style, wind, drainage, and slope.';
      case 'glacier':
        return '${prefix}retreat exposes unstable slopes and changes downstream runoff timing.';
      default:
        return '${prefix}localized environmental impact pattern requires field validation.';
    }
  }

  String _forecastFor(String category) {
    switch (category) {
      case 'wildfire':
        return 'Escalation risk rises if winds increase, humidity drops, or fuels remain critically dry.';
      case 'flood':
        return 'Risk depends on upstream rainfall, soil saturation, snowmelt, tide, and reservoir operations.';
      case 'drought':
        return 'Watch for crop stress, water restrictions, wildfire amplification, and groundwater pressure.';
      case 'airquality':
        return 'Exposure can worsen under low wind, inversions, heat, or nearby smoke production.';
      case 'quake':
        return 'Aftershock monitoring and exposure mapping should be prioritized over weather triggers.';
      case 'volcano':
        return 'Use wind forecasts and aviation color status to estimate ash exposure corridors.';
      case 'glacier':
        return 'Monitor meltwater pulses, glacial lake growth, and downstream flood pathways.';
      default:
        return 'Monitor source updates and verify exposure before issuing operational guidance.';
    }
  }

  String _backgroundFor({
    required String title,
    required String category,
    required String description,
    required String location,
    required String drivers,
    required String pattern,
    required String forecast,
    required String source,
    required double radiusKm,
    required bool isHistorical,
    required String startDate,
    required String endDate,
  }) {
    final period = startDate.isNotEmpty
        ? ' Period: $startDate${endDate.isNotEmpty ? ' to $endDate' : ''}.'
        : '';
    final lead = description.isNotEmpty
        ? description
        : '$title is a ${_typeLabel(category).toLowerCase()} intelligence event near $location.';
    return '$lead$period Drivers: $drivers. Pattern: $pattern Forecast cue: $forecast '
        'EcoLens is using a ${radiusKm.toStringAsFixed(0)} km watch radius and source context from $source. '
        '${isHistorical ? 'This is a historical reconstruction for briefing and scenario learning.' : 'This is a live triage view for operational screening; verify locally before public action.'}';
  }

  String _jurisdictionFor(String country) {
    return country.isEmpty
        ? 'Local emergency management / relevant agency'
        : '$country emergency management / relevant agency';
  }

  double _extractFrp(String description) {
    final match = RegExp(r'([0-9]+(?:\.[0-9]+)?)\s*MW').firstMatch(description);
    return match == null ? 0 : double.tryParse(match.group(1) ?? '') ?? 0;
  }

  String _lossBreakdownFor(String category) {
    switch (category) {
      case 'wildfire':
        return 'Suppression, structures, utilities, smoke health burden, watershed recovery';
      case 'flood':
        return 'Property damage, transport disruption, cleanup, water quality, business interruption';
      case 'drought':
        return 'Crop yield, water transfers, hydropower, wildfire preparedness, ecosystem stress';
      case 'airquality':
        return 'Health visits, productivity loss, school/work disruption, vulnerable population support';
      case 'quake':
        return 'Buildings, lifelines, emergency shelter, port/road disruption, aftershock response';
      default:
        return 'Direct response, recovery, monitoring, and ecosystem service loss';
    }
  }

  String _communityImpactFor(String category) {
    return 'Exposure, service continuity, and recovery needs should be validated with local responders and community organizations.';
  }

  List<String> _industriesFor(String category) {
    switch (category) {
      case 'wildfire':
        return ['forestry', 'insurance', 'tourism', 'utilities'];
      case 'flood':
        return ['transport', 'insurance', 'agriculture', 'retail'];
      case 'drought':
        return ['agriculture', 'energy', 'municipal water', 'ranching'];
      case 'airquality':
        return ['healthcare', 'education', 'outdoor work', 'tourism'];
      case 'quake':
        return ['construction', 'transport', 'ports', 'utilities'];
      default:
        return ['local economy', 'public services'];
    }
  }

  String _irreversibilityFor(String category) {
    switch (category) {
      case 'glacier':
      case 'deforestation':
        return 'HIGH';
      case 'wildfire':
      case 'drought':
        return 'MEDIUM-HIGH';
      default:
        return 'MEDIUM';
    }
  }

  int _interventionWindowFor(String category, bool isHistorical) {
    if (isHistorical) return 90;
    switch (category) {
      case 'airquality':
        return 2;
      case 'flood':
      case 'quake':
      case 'volcano':
        return 3;
      case 'wildfire':
        return 7;
      case 'drought':
        return 30;
      default:
        return 14;
    }
  }

  List<RecommendedAction> _recommendedActionsFor(
    String category,
    String severity,
  ) {
    final immediate = _severityRank(severity) >= 2;
    return _recommendationStringsFor(category)
        .map(
          (action) => RecommendedAction(
            action: action,
            priority: immediate ? 'IMMEDIATE' : 'SHORT_TERM',
            responsibleEntity: 'Incident lead / local authority',
          ),
        )
        .toList();
  }

  List<String> _recommendationStringsFor(String category) {
    switch (category) {
      case 'wildfire':
        return [
          'Validate perimeter, fuels, wind, and evacuation exposure.',
          'Prioritize high-FRP clusters near communities or critical infrastructure.',
          'Prepare post-fire debris-flow and water-quality monitoring.',
        ];
      case 'flood':
        return [
          'Check upstream precipitation, gauges, and low-lying exposure.',
          'Map roads, shelters, hospitals, and water systems inside the watch radius.',
          'Prepare public messaging for rapid stage changes.',
        ];
      case 'drought':
        return [
          'Compare rainfall deficit with NDVI and soil moisture anomalies.',
          'Identify water-supply systems, crop zones, and wildfire-prone fuels.',
          'Coordinate conservation and heat-health messaging early.',
        ];
      case 'airquality':
        return [
          'Track PM2.5, wind direction, smoke source, and inversion risk.',
          'Prepare clean-air shelter messaging for vulnerable populations.',
          'Cross-check nearby wildfires and stagnant-air forecasts.',
        ];
      case 'quake':
        return [
          'Map exposed population, lifelines, hospitals, and landslide-prone slopes.',
          'Monitor aftershock sequence and tsunami flag where relevant.',
          'Prioritize rapid damage assessment near soft soils and dense settlements.',
        ];
      case 'volcano':
        return [
          'Track alert level, ash plume direction, aviation impact, and lahar paths.',
          'Map drainage channels and communities downwind or downslope.',
          'Coordinate health guidance for ash exposure and water contamination.',
        ];
      default:
        return [
          'Verify source data and local exposure before publishing.',
          'Map affected communities, infrastructure, and ecosystem services.',
          'Define monitoring cadence and escalation thresholds.',
        ];
    }
  }

  Map<String, dynamic> _actionPlanFor(String category) {
    return {
      'immediate': _recommendationStringsFor(category).take(2).toList(),
      'short_term': [
        'Build a source-verified event dossier with map evidence and confidence notes.',
        'Coordinate with local agencies, NGOs, and community leads for ground truth.',
      ],
      'long_term': [
        'Track recovery indicators and compound-risk signals over time.',
        'Convert lessons into preparedness, adaptation, and community story maps.',
      ],
    };
  }

  Map<String, dynamic> _hydrologyIntelFor(String category) {
    return {
      'available': true,
      'water_accessibility': {
        'rating': category == 'drought' ? 'STRESSED' : 'SCREENING',
        'description': _forecastFor(category),
      },
      'water_features': {
        // No distance: nothing measured one. The name states the gap.
        'nearest_water': {'name': 'Nearest mapped waterbody pending'},
      },
      'water_stress': {
        'baseline_stress': category == 'drought' ? 'HIGH' : 'UNKNOWN',
        'drought_risk': category == 'drought' ? 'HIGH' : 'LOW-MEDIUM',
      },
    };
  }

  List<Map<String, dynamic>> _riskFactorsFor(
    String category,
    String drivers,
    String pattern,
  ) {
    return [
      {'factor': 'Primary drivers', 'interpretation': drivers},
      {'factor': 'Spatial pattern', 'interpretation': pattern},
      {'factor': 'Forecast cue', 'interpretation': _forecastFor(category)},
    ];
  }

  String _historicalNarrative({
    required String title,
    required String category,
    required String description,
    required String drivers,
    required String pattern,
    required Map<String, dynamic> metadata,
    required bool isHistorical,
  }) {
    final details = metadata.entries
        .map((e) => '${e.key}: ${e.value}')
        .join('; ');
    return '$title. $description Drivers: $drivers. $pattern '
        '${details.isNotEmpty ? 'Documented metrics include $details.' : ''} '
        '${isHistorical ? 'Use this event as a scenario case study and compare the before/after layers with local response data.' : 'Use this live event as a triage product and verify with operational sources.'}';
  }

  int _recoveryScoreFor(String category, String severity) {
    if (category == 'quake' || category == 'airquality') return 55;
    if (category == 'glacier') return 20;
    switch (_severityRank(severity)) {
      case 3:
        return 20;
      case 2:
        return 30;
      case 1:
        return 45;
      default:
        return 60;
    }
  }
}
