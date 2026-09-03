import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:ecolens/model/location_model.dart';
import 'package:ecolens/core/theme.dart';
import 'package:ecolens/viewmodels/InsightsViewModel.dart';
import 'package:ecolens/services/aggregation_service.dart';
import 'package:ecolens/services/spatial_analysis_service.dart';
import 'package:ecolens/model/spatial_analysis_result.dart';
import 'package:ecolens/widgets/analysis_toolbar.dart';
import 'package:ecolens/widgets/analysis_results_panel.dart';
import 'package:ecolens/views/premium_ar_screen.dart';
import 'package:turf/turf.dart' as turf;

/// Drawing mode enum for GIS tools
enum WebDrawingMode { none, point, line, polygon }

/// Professional Web Map Screen with flutter_map & OpenStreetMap
///
/// Features:
/// - Multiple tile providers (Satellite, Dark, Outdoors)
/// - Zoom-based layer transitions with color changes
/// - GIS drawing tools (points, lines, polygons)
/// - Professional dark satellite hybrid style
/// - Full web compatibility
class WebMapScreen extends StatefulWidget {
  const WebMapScreen({super.key});

  @override
  State<WebMapScreen> createState() => _WebMapScreenState();
}

class _WebMapScreenState extends State<WebMapScreen>
    with TickerProviderStateMixin {
  // Map controller
  final MapController _mapController = MapController();
  bool _mapReady = false;

  // Data
  List<IntelligenceNode> _hotspots = [];
  bool _isLoading = true;
  IntelligenceNode? _selectedHotspot;

  // Map state
  double _currentZoom = 3.0;
  int _mapStyle = 0; // 0=Satellite, 1=Dark, 2=Outdoors

  // Layer visibility
  bool _showHotspots = true;

  // GIS Drawing tools
  WebDrawingMode _drawingMode = WebDrawingMode.none;
  List<LatLng> _drawnPoints = [];
  bool _showDrawingTools = false;

  // GIS Analysis results
  double? _measuredDistance = null;
  double? _measuredArea = null;

  // UI State
  bool _showAlertsList = false;
  bool _showStatsPanel = false;

  // Spatial Analysis State
  final SpatialAnalysisService _analysisService = SpatialAnalysisService();
  SpatialAnalysisType? _activeAnalysis;
  SpatialAnalysisResult? _analysisResult;
  bool _isAnalyzing = false;

  // Animation
  late AnimationController _pulseController;

  // Tile providers
  static const List<String> _tileUrls = [
    // Satellite - ESRI World Imagery
    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    // Dark - CartoDB Dark Matter
    'https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png',
    // Outdoors - OpenTopoMap
    'https://a.tile.opentopomap.org/{z}/{x}/{y}.png',
  ];

  static const List<String> _styleNames = ['Satellite', 'Dark', 'Outdoors'];
  static const List<IconData> _styleIcons = [
    Icons.satellite_alt,
    Icons.dark_mode,
    Icons.terrain,
  ];

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _loadHotspots();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadHotspots() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('hotspots')
          .limit(500)
          .get();

      final nodes = snapshot.docs
          .map((doc) => IntelligenceNode.fromMap(doc.data(), doc.id))
          .toList();

      setState(() {
        _hotspots = nodes;
        _isLoading = false;
        _mapReady = true;
      });
    } catch (e) {
      debugPrint('Error loading hotspots: $e');
      setState(() => _isLoading = false);
    }
  }

  void _onHotspotTapped(IntelligenceNode hotspot) {
    HapticFeedback.mediumImpact();
    setState(() => _selectedHotspot = hotspot);

    // Fly to hotspot
    _mapController.move(
      LatLng(hotspot.lat, hotspot.lng),
      12,
    );
  }

  void _flyToGlobal() {
    setState(() => _selectedHotspot = null);
    _mapController.move(LatLng(-3, -60), 3);
  }

  void _cycleMapStyle() {
    setState(() {
      _mapStyle = (_mapStyle + 1) % _tileUrls.length;
    });
  }

  Color _getRiskColor(double risk) {
    if (risk >= 80) return const Color(0xFFFF3B3B);
    if (risk >= 60) return const Color(0xFFFF8C00);
    if (risk >= 40) return const Color(0xFFFFD700);
    return const Color(0xFF00E676);
  }

  Color _getClusterColor(double avgRisk) {
    if (avgRisk >= 70) return const Color(0xFFFF3B3B);
    if (avgRisk >= 40) return const Color(0xFFFF8C00);
    return const Color(0xFF00E676);
  }

  List<Map<String, dynamic>> _clusterHotspots() {
    final clusters = <String, List<IntelligenceNode>>{};

    for (final hotspot in _hotspots) {
      final key = '${(hotspot.lat / 5).round()}_${(hotspot.lng / 5).round()}';
      clusters.putIfAbsent(key, () => []).add(hotspot);
    }

    return clusters.entries.map((entry) {
      final nodes = entry.value;
      final avgLat = nodes.map((n) => n.lat).reduce((a, b) => a + b) / nodes.length;
      final avgLng = nodes.map((n) => n.lng).reduce((a, b) => a + b) / nodes.length;
      final avgRisk = nodes.map((n) => n.riskScore).reduce((a, b) => a + b) / nodes.length;
      final totalHectares = nodes.map((n) => n.hectares).reduce((a, b) => a + b);

      return {
        'lat': avgLat,
        'lng': avgLng,
        'avgRisk': avgRisk,
        'count': nodes.length,
        'hectares': totalHectares,
      };
    }).toList();
  }

  /// Build markers based on zoom level
  List<Marker> _buildMarkers() {
    if (!_showHotspots || _hotspots.isEmpty) return [];

    final markers = <Marker>[];
    final isClusterView = _currentZoom < 6;
    final isDetailView = _currentZoom >= 10;

    if (isClusterView) {
      // Cluster view
      final clusters = _clusterHotspots();
      for (final cluster in clusters) {
        final color = _getClusterColor(cluster['avgRisk'] as double);
        final size = ((cluster['count'] as int) * 1.5 + 16).clamp(16, 48).toDouble();

        markers.add(
          Marker(
            point: LatLng(cluster['lat'] as double, cluster['lng'] as double),
            width: size,
            height: size,
            child: GestureDetector(
              onTap: () {
                // Zoom into cluster
                _mapController.move(
                  LatLng(cluster['lat'] as double, cluster['lng'] as double),
                  8,
                );
              },
              child: Container(
                decoration: BoxDecoration(
                  color: color.withOpacity(0.8),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.4),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    '${cluster['count']}',
                    style: GoogleFonts.robotoMono(
                      color: Colors.white,
                      fontSize: size / 3,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }
    } else {
      // Individual markers
      for (final hotspot in _hotspots) {
        final color = _getRiskColor(hotspot.riskScore);
        final size = isDetailView ? 24.0 : 16.0;
        final isSelected = _selectedHotspot?.id == hotspot.id;

        markers.add(
          Marker(
            point: LatLng(hotspot.lat, hotspot.lng),
            width: isSelected ? size * 1.5 : size,
            height: isSelected ? size * 1.5 : size,
            child: GestureDetector(
              onTap: () => _onHotspotTapped(hotspot),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.9),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? Colors.white : Colors.white70,
                    width: isSelected ? 3 : 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(isSelected ? 0.6 : 0.3),
                      blurRadius: isSelected ? 12 : 6,
                      spreadRadius: isSelected ? 4 : 2,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
    }

    return markers;
  }

  /// Build drawing polylines and polygons
  List<Polyline> _buildDrawingPolylines() {
    if (_drawnPoints.length < 2) return [];

    final polylines = <Polyline>[];

    // Main line
    polylines.add(
      Polyline(
        points: _drawnPoints,
        color: Colors.cyan,
        strokeWidth: 4,
      ),
    );

    // Closing line for polygon
    if (_drawingMode == WebDrawingMode.polygon && _drawnPoints.length >= 3) {
      polylines.add(
        Polyline(
          points: [_drawnPoints.last, _drawnPoints.first],
          color: Colors.cyan.withOpacity(0.7),
          strokeWidth: 3,
        ),
      );
    }

    return polylines;
  }

  List<Polygon> _buildDrawingPolygons() {
    if (_drawingMode != WebDrawingMode.polygon || _drawnPoints.length < 3) {
      return [];
    }

    return [
      Polygon(
        points: _drawnPoints,
        color: Colors.cyan.withOpacity(0.3),
        borderColor: Colors.cyan,
        borderStrokeWidth: 2,
      ),
    ];
  }

  List<Marker> _buildDrawingMarkers() {
    return _drawnPoints.asMap().entries.map((entry) {
      final index = entry.key;
      final point = entry.value;
      final isFirst = index == 0;
      final isLast = index == _drawnPoints.length - 1;

      return Marker(
        point: point,
        width: isFirst ? 20 : (isLast ? 18 : 14),
        height: isFirst ? 20 : (isLast ? 18 : 14),
        child: Container(
          decoration: BoxDecoration(
            color: isFirst
                ? Colors.green
                : (isLast ? Colors.red : Colors.yellow),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
          ),
        ),
      );
    }).toList();
  }

  /// Calculate measurements using Turf
  void _calculateMeasurements() {
    if (_drawnPoints.isEmpty) {
      setState(() {
        _measuredDistance = null;
        _measuredArea = null;
      });
      return;
    }

    // Calculate distance
    if (_drawnPoints.length >= 2) {
      double totalDistance = 0;
      for (int i = 0; i < _drawnPoints.length - 1; i++) {
        final from = turf.Point(
          coordinates: turf.Position(_drawnPoints[i].longitude, _drawnPoints[i].latitude),
        );
        final to = turf.Point(
          coordinates: turf.Position(_drawnPoints[i + 1].longitude, _drawnPoints[i + 1].latitude),
        );
        totalDistance += turf.distance(from, to, turf.Unit.kilometers);
      }
      setState(() => _measuredDistance = totalDistance);
    }

    // Calculate area
    if (_drawnPoints.length >= 3 && _drawingMode == WebDrawingMode.polygon) {
      final positions = _drawnPoints.map((p) => turf.Position(p.longitude, p.latitude)).toList();
      positions.add(positions.first); // Close the polygon
      final polygon = turf.Polygon(coordinates: [positions]);
      final areaResult = turf.area(polygon);
      final areaKm2 = (areaResult ?? 0) / 1000000;
      setState(() => _measuredArea = areaKm2);
    }
  }

  void _clearDrawing() {
    setState(() {
      _drawnPoints.clear();
      _measuredDistance = null;
      _measuredArea = null;
    });
  }

  /// Get alert counts by severity
  Map<String, int> get _alertCounts {
    int high = 0, medium = 0, low = 0;
    for (final h in _hotspots) {
      if (h.riskScore >= 80) {
        high++;
      } else if (h.riskScore >= 50) {
        medium++;
      } else {
        low++;
      }
    }
    return {'high': high, 'medium': medium, 'low': low};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E14),
      body: Stack(
        children: [
          // Flutter Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(-3, -60),
              initialZoom: 3,
              minZoom: 2,
              maxZoom: 18,
              backgroundColor: const Color(0xFF0A0E14),
              onPositionChanged: (position, hasGesture) {
                if (position.zoom != null && position.zoom != _currentZoom) {
                  setState(() => _currentZoom = position.zoom!);
                }
              },
              onTap: (tapPosition, point) {
                if (_drawingMode != WebDrawingMode.none) {
                  setState(() {
                    _drawnPoints.add(point);
                  });
                  _calculateMeasurements();
                } else if (_selectedHotspot != null) {
                  setState(() => _selectedHotspot = null);
                }
              },
            ),
            children: [
              // Tile layer
              TileLayer(
                urlTemplate: _tileUrls[_mapStyle],
                userAgentPackageName: 'com.example.ecolens',
                maxZoom: 19,
              ),

              // Drawing polygons
              PolygonLayer(
                polygons: _buildDrawingPolygons(),
              ),

              // Drawing polylines
              PolylineLayer(
                polylines: _buildDrawingPolylines(),
              ),

              // Drawing markers
              MarkerLayer(
                markers: _buildDrawingMarkers(),
              ),

              // Hotspot markers
              MarkerLayer(
                markers: _buildMarkers(),
              ),
            ],
          ),

          // Loading overlay
          if (_isLoading || !_mapReady)
            Container(
              color: const Color(0xFF0A0E14).withOpacity(0.8),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 60,
                      height: 60,
                      child: CircularProgressIndicator(
                        color: EcoTheme.neonEmerald,
                        strokeWidth: 3,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Loading Map Data...',
                      style: GoogleFonts.orbitron(
                        color: Colors.white70,
                        fontSize: 14,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Top controls
          _buildTopControls(),

          // Zoom indicator
          _buildZoomIndicator(),

          // Layer panel
          _buildLayerPanel(),

          // Selected hotspot info card
          if (_selectedHotspot != null) _buildInfoCard(_selectedHotspot!),

          // Legend
          _buildLegend(),

          // GIS Drawing Tools Panel
          if (_showDrawingTools) _buildDrawingToolsPanel(),

          // Measurement results
          if (_measuredDistance != null || _measuredArea != null)
            _buildMeasurementResults(),

          // Spatial Analysis Toolbar
          AnalysisToolbar(
            onAnalysisSelected: _runAnalysis,
            activeAnalysis: _activeAnalysis,
            isAnalyzing: _isAnalyzing,
            onClose: _clearAnalysis,
          ),

          // Analysis Loading Overlay
          if (_isAnalyzing && _activeAnalysis != null)
            AnalysisLoadingOverlay(type: _activeAnalysis!),

          // Analysis Results Panel
          if (_analysisResult != null && !_isAnalyzing)
            AnalysisResultsPanel(
              result: _analysisResult!,
              onClose: _clearAnalysis,
              onExport: () => _exportAnalysisResult(_analysisResult!),
            ),

          // Bottom bar (hide when analysis results shown)
          if (_analysisResult == null) _buildMinimalBottomBar(),

          // Alerts list panel
          if (_showAlertsList) _buildAlertsListPanel(),
        ],
      ),
    );
  }

  /// Run a spatial analysis
  Future<void> _runAnalysis(SpatialAnalysisType type) async {
    setState(() {
      _activeAnalysis = type;
      _isAnalyzing = true;
      _analysisResult = null;
    });

    try {
      // Get visible bounds from map
      final bounds = _mapController.camera.visibleBounds;
      final visibleHotspots = _hotspots.where((h) {
        return h.lat >= bounds.south &&
            h.lat <= bounds.north &&
            h.lng >= bounds.west &&
            h.lng <= bounds.east;
      }).toList();

      // Use default config
      const config = AnalysisConfig(
        startYear: 2015,
        endYear: 2024,
        bufferDistanceKm: 10.0,
        forecastYears: 5,
      );

      final result = await _analysisService.runAnalysis(
        type,
        visibleHotspots,
        config,
      );

      setState(() {
        _analysisResult = result;
        _isAnalyzing = false;
      });
    } catch (e) {
      setState(() {
        _analysisResult = SpatialAnalysisResult.error(type, e.toString());
        _isAnalyzing = false;
      });
    }
  }

  /// Clear analysis state
  void _clearAnalysis() {
    setState(() {
      _activeAnalysis = null;
      _analysisResult = null;
      _isAnalyzing = false;
    });
  }

  /// Export analysis result
  void _exportAnalysisResult(SpatialAnalysisResult result) {
    // Convert summary map to readable string
    final summaryText = result.summary.entries
        .map((e) => '${e.key}: ${e.value}')
        .join('\n');

    // Show snackbar with export options
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Export ${result.type.name} analysis'),
        action: SnackBarAction(
          label: 'COPY',
          onPressed: () {
            Clipboard.setData(ClipboardData(text: summaryText));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Analysis copied to clipboard')),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTopControls() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      left: 16,
      right: 16,
      child: Row(
        children: [
          // Back to global button
          _controlButton(
            icon: Icons.public,
            onTap: _flyToGlobal,
            tooltip: 'Global View',
          ),
          const SizedBox(width: 12),

          // Style switcher
          _controlButton(
            icon: _styleIcons[_mapStyle],
            onTap: _cycleMapStyle,
            tooltip: _styleNames[_mapStyle],
            showLabel: true,
            label: _styleNames[_mapStyle],
          ),

          const Spacer(),

          // GIS Drawing Tools
          _controlButton(
            icon: Icons.architecture,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _showDrawingTools = !_showDrawingTools);
            },
            tooltip: 'GIS Tools',
            active: _showDrawingTools,
          ),
        ],
      ),
    );
  }

  Widget _controlButton({
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
    bool active = false,
    bool showLabel = false,
    String? label,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: showLabel ? 16 : 12,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              color: active
                  ? EcoTheme.neonEmerald.withOpacity(0.2)
                  : Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: active ? EcoTheme.neonEmerald : Colors.white24,
                width: active ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  color: active ? EcoTheme.neonEmerald : Colors.white,
                  size: 20,
                ),
                if (showLabel && label != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: active ? EcoTheme.neonEmerald : Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildZoomIndicator() {
    String scaleLabel;
    Color scaleColor;

    if (_currentZoom < 6) {
      scaleLabel = 'Global';
      scaleColor = Colors.cyan;
    } else if (_currentZoom < 10) {
      scaleLabel = 'Regional';
      scaleColor = Colors.amber;
    } else {
      scaleLabel = 'Local';
      scaleColor = EcoTheme.neonEmerald;
    }

    return Positioned(
      top: MediaQuery.of(context).padding.top + 70,
      right: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          scaleLabel,
          style: TextStyle(
            color: scaleColor,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildLayerPanel() {
    final metrics = AggregationService.compute(_hotspots);
    final numberFormat = NumberFormat.compact();

    return Positioned(
      top: MediaQuery.of(context).padding.top + 70,
      left: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Collapsed stats toggle button
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _showStatsPanel = !_showStatsPanel);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.85),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.analytics_outlined,
                    size: 14,
                    color: EcoTheme.electricCyan,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${metrics.totalNodes}',
                    style: GoogleFonts.robotoMono(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _showStatsPanel ? Icons.expand_less : Icons.expand_more,
                    size: 14,
                    color: Colors.white54,
                  ),
                ],
              ),
            ),
          ),

          // Expandable stats panel
          if (_showStatsPanel) ...[
            const SizedBox(height: 8),
            Container(
              width: 160,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _statRow('Area', '${numberFormat.format(metrics.totalHectares.toInt())} ha', Icons.square_foot),
                  _statRow('Avg Risk', '${metrics.avgRiskScore.toStringAsFixed(0)}%', Icons.warning_amber),
                  _statRow('Critical', '${metrics.criticalZoneCount}', Icons.error_outline),
                  if (metrics.hasPopulationData)
                    _statRow('Population', numberFormat.format(metrics.totalPopulation), Icons.people),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 12, color: Colors.white38),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              style: GoogleFonts.robotoMono(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(IntelligenceNode hotspot) {
    final riskColor = _getRiskColor(hotspot.riskScore);
    final numberFormat = NumberFormat.compact();

    final riskLabel = hotspot.riskScore >= 80
        ? 'CRITICAL'
        : hotspot.riskScore >= 60
            ? 'HIGH'
            : hotspot.riskScore >= 40
                ? 'MODERATE'
                : 'LOW';

    return Positioned(
      bottom: 50,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        margin: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1117),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: riskColor.withOpacity(0.6), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: riskColor.withOpacity(0.25),
              blurRadius: 16,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: riskColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${hotspot.riskScore.toInt()}%',
                      style: GoogleFonts.orbitron(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hotspot.headline,
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${hotspot.country} • $riskLabel RISK',
                          style: TextStyle(color: riskColor.withOpacity(0.9), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _selectedHotspot = null),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.close, color: Colors.white54, size: 18),
                    ),
                  ),
                ],
              ),
            ),

            // Metrics Grid
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Row(
                children: [
                  Expanded(child: _compactMetric(Icons.landscape, 'Area', '${numberFormat.format(hotspot.hectares.toInt())} ha', Colors.orange)),
                  Expanded(child: _compactMetric(Icons.people, 'People', hotspot.hasPopulationData ? numberFormat.format(hotspot.population) : '—', Colors.purple)),
                  Expanded(child: _compactMetric(Icons.pets, 'Species', '${hotspot.speciesAtRisk.length}', Colors.amber)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Row(
                children: [
                  Expanded(child: _compactMetric(Icons.cloud, 'CO₂/yr', hotspot.carbonData.annualEmissionsTonnes > 0 ? '${numberFormat.format(hotspot.carbonData.annualEmissionsTonnes.toInt())}t' : '—', Colors.red)),
                  Expanded(child: _compactMetric(Icons.eco, 'Recovery', _getRecoveryValue(hotspot), EcoTheme.neonEmerald)),
                  Expanded(child: _compactMetric(Icons.attach_money, 'Cost', hotspot.hasReforestCostData ? '\$${numberFormat.format(hotspot.reforestZone.costEstimateUsd)}' : '—', Colors.teal)),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Action Buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Row(
                children: [
                  // AR Experience button
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PremiumARScreen(node: hotspot),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: EcoTheme.electricCyan),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.view_in_ar, color: EcoTheme.electricCyan, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              'EXPERIENCE',
                              style: GoogleFonts.poppins(
                                color: EcoTheme.electricCyan,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Insights button
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        // Set the active alert for insights
                        Provider.of<InsightsViewModel>(context, listen: false)
                            .selectAlert(hotspot);
                        // Show snackbar with navigation hint
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Detailed insights ready! Go to Insights tab.'),
                            backgroundColor: Colors.purple,
                            action: SnackBarAction(
                              label: 'VIEW',
                              textColor: Colors.white,
                              onPressed: () {},
                            ),
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.purple),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.insights, color: Colors.purple, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              'INSIGHTS',
                              style: GoogleFonts.poppins(
                                color: Colors.purple,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Focus button
                  GestureDetector(
                    onTap: () {
                      _mapController.move(
                        LatLng(hotspot.lat, hotspot.lng),
                        14,
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: EcoTheme.neonEmerald,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.center_focus_strong, color: Colors.black, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            'FOCUS',
                            style: GoogleFonts.poppins(
                              color: Colors.black,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  String _getRecoveryValue(IntelligenceNode hotspot) {
    if (hotspot.hasSuitabilityData) {
      return '${hotspot.reforestZone.suitabilityScore}%';
    } else if (hotspot.hasRecoveryData) {
      return '${hotspot.recoveryScore.toInt()}%';
    }
    return '—';
  }

  Widget _compactMetric(IconData icon, String label, String value, Color color) {
    return Container(
      margin: const EdgeInsets.all(3),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3), width: 0.5),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 8,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.orbitron(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Positioned(
      bottom: _selectedHotspot != null ? 320 : 24,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.85),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'RISK LEVEL',
              style: GoogleFonts.orbitron(
                color: Colors.white54,
                fontSize: 9,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 10),
            _legendItem('Critical', const Color(0xFFFF3B3B)),
            _legendItem('High', const Color(0xFFFF8C00)),
            _legendItem('Moderate', const Color(0xFFFFD700)),
            _legendItem('Low', const Color(0xFF00E676)),
          ],
        ),
      ),
    );
  }

  Widget _legendItem(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: color.withOpacity(0.5), blurRadius: 4),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawingToolsPanel() {
    return Positioned(
      bottom: 100,
      left: 16,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.92),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: EcoTheme.electricCyan.withOpacity(0.5)),
          boxShadow: [
            BoxShadow(
              color: EcoTheme.electricCyan.withOpacity(0.2),
              blurRadius: 15,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.architecture, size: 14, color: EcoTheme.electricCyan),
                const SizedBox(width: 6),
                Text(
                  'GIS DRAWING',
                  style: GoogleFonts.orbitron(
                    color: EcoTheme.electricCyan,
                    fontSize: 9,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                _drawingModeButton(WebDrawingMode.point, Icons.location_on, 'Point'),
                const SizedBox(width: 8),
                _drawingModeButton(WebDrawingMode.line, Icons.timeline, 'Line'),
                const SizedBox(width: 8),
                _drawingModeButton(WebDrawingMode.polygon, Icons.pentagon, 'Polygon'),
              ],
            ),

            if (_drawnPoints.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  InkWell(
                    onTap: _clearDrawing,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.withOpacity(0.5)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.delete, size: 14, color: Colors.red),
                          const SizedBox(width: 4),
                          const Text('Clear', style: TextStyle(color: Colors.red, fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_drawingMode == WebDrawingMode.polygon && _drawnPoints.length >= 3)
                    InkWell(
                      onTap: () {
                        _calculateMeasurements();
                        setState(() => _drawingMode = WebDrawingMode.none);
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: EcoTheme.neonEmerald.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: EcoTheme.neonEmerald.withOpacity(0.5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check, size: 14, color: EcoTheme.neonEmerald),
                            const SizedBox(width: 4),
                            Text('Done', style: TextStyle(color: EcoTheme.neonEmerald, fontSize: 11)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _drawingModeButton(WebDrawingMode mode, IconData icon, String label) {
    final isActive = _drawingMode == mode;
    final color = isActive ? EcoTheme.electricCyan : Colors.white54;

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _drawingMode = _drawingMode == mode ? WebDrawingMode.none : mode;
          if (_drawingMode != mode) {
            _drawnPoints.clear();
            _measuredDistance = null;
            _measuredArea = null;
          }
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? color.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(isActive ? 0.8 : 0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: color, fontSize: 9)),
          ],
        ),
      ),
    );
  }

  Widget _buildMeasurementResults() {
    final numberFormat = NumberFormat('#,##0.00');

    return Positioned(
      bottom: _showDrawingTools ? 260 : 100,
      left: 16,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.92),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.amber.withOpacity(0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.straighten, size: 14, color: Colors.amber),
                const SizedBox(width: 6),
                Text(
                  'MEASUREMENTS',
                  style: GoogleFonts.orbitron(
                    color: Colors.amber,
                    fontSize: 9,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (_measuredDistance != null)
              _measurementRow(
                'Distance',
                _measuredDistance! < 1
                    ? '${(_measuredDistance! * 1000).toStringAsFixed(0)} m'
                    : '${numberFormat.format(_measuredDistance)} km',
                Icons.straighten,
              ),

            if (_measuredArea != null)
              _measurementRow(
                'Area',
                _measuredArea! < 1
                    ? '${(_measuredArea! * 100).toStringAsFixed(2)} ha'
                    : '${numberFormat.format(_measuredArea)} km²',
                Icons.square_foot,
              ),

            _measurementRow(
              'Points',
              '${_drawnPoints.length}',
              Icons.location_on,
            ),
          ],
        ),
      ),
    );
  }

  Widget _measurementRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 12, color: Colors.white38),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              style: GoogleFonts.robotoMono(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMinimalBottomBar() {
    final counts = _alertCounts;
    final total = _hotspots.length;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withOpacity(0.9),
              Colors.black.withOpacity(0.7),
              Colors.transparent,
            ],
            stops: const [0.0, 0.7, 1.0],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  _quickStat(total.toString(), 'zones', EcoTheme.electricCyan),
                  const SizedBox(width: 16),
                  _quickStat('${counts['high']}', 'critical', Colors.red),
                  const SizedBox(width: 16),
                  _quickStat('${counts['medium']}', 'moderate', Colors.orange),
                ],
              ),
              TextButton.icon(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  setState(() => _showAlertsList = !_showAlertsList);
                },
                icon: Icon(
                  _showAlertsList ? Icons.map : Icons.list,
                  size: 16,
                  color: EcoTheme.neonEmerald,
                ),
                label: Text(
                  _showAlertsList ? 'Map' : 'List',
                  style: TextStyle(color: EcoTheme.neonEmerald, fontSize: 12),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  backgroundColor: EcoTheme.neonEmerald.withOpacity(0.1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickStat(String value, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: GoogleFonts.robotoMono(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildAlertsListPanel() {
    return Positioned(
      bottom: 100,
      left: 0,
      right: 0,
      child: Container(
        height: 220,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.95),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white12)),
              ),
              child: Row(
                children: [
                  Icon(Icons.notifications_active, size: 16, color: EcoTheme.electricCyan),
                  const SizedBox(width: 8),
                  Text(
                    'Environmental Zones (${_hotspots.length})',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () => setState(() => _showAlertsList = false),
                    child: const Icon(Icons.close, size: 18, color: Colors.white38),
                  ),
                ],
              ),
            ),
            // List
            Expanded(
              child: _hotspots.isEmpty
                  ? const Center(
                      child: Text(
                        'No environmental zones found',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: _hotspots.length,
                      itemBuilder: (context, index) {
                        final hotspot = _hotspots[index];
                        final color = _getRiskColor(hotspot.riskScore);
                        return InkWell(
                          onTap: () {
                            _mapController.move(
                              LatLng(hotspot.lat, hotspot.lng),
                              12,
                            );
                            setState(() {
                              _selectedHotspot = hotspot;
                              _showAlertsList = false;
                            });
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: color.withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        hotspot.headline,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${hotspot.hectares.toStringAsFixed(0)} ha • Risk: ${hotspot.riskScore.toInt()}%',
                                        style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Flexible(
                                  child: Text(
                                    hotspot.region.isNotEmpty ? hotspot.region : hotspot.country,
                                    style: const TextStyle(color: Colors.white38, fontSize: 9),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(Icons.chevron_right, size: 16, color: Colors.white24),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
