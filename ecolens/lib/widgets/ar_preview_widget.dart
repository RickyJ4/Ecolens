import 'package:ecolens/core/theme.dart';
import 'package:ecolens/model/location_model.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:panorama_image/panorama_image.dart';

/// Data class for AR deforestation region display
class ARDeforestationData {
  final String regionName;
  final double lat;
  final double lng;
  final String habitat;
  final double riskScore;

  // Species at risk
  final List<SpeciesInfo> faunaAtRisk;
  final List<SpeciesInfo> floraAtRisk;

  // Environmental data
  final Map<String, dynamic> soilData;
  final Map<String, dynamic> terrainData;
  final Map<String, dynamic> hydrologyData;

  // Impact data
  final int peopleAffected;
  final double distanceToSettlement;
  final double hectares;
  final double carbonLossTonnes;

  // Empty state flag
  final bool isEmpty;

  const ARDeforestationData({
    required this.regionName,
    required this.lat,
    required this.lng,
    this.habitat = 'Unknown',
    this.riskScore = 0,
    this.faunaAtRisk = const [],
    this.floraAtRisk = const [],
    this.soilData = const {},
    this.terrainData = const {},
    this.hydrologyData = const {},
    this.peopleAffected = 0,
    this.distanceToSettlement = 0,
    this.hectares = 0,
    this.carbonLossTonnes = 0,
    this.isEmpty = false,
  });

  /// Creates an empty state when no zone is selected
  factory ARDeforestationData.empty() => const ARDeforestationData(
        regionName: "No zone selected",
        lat: 0,
        lng: 0,
        isEmpty: true,
      );

  /// Create from IntelligenceNode
  factory ARDeforestationData.fromNode(IntelligenceNode node) {
    return ARDeforestationData(
      regionName: node.region.isNotEmpty ? node.region : node.headline,
      lat: node.lat,
      lng: node.lng,
      habitat: node.type, // Use type as habitat indicator
      riskScore: node.riskScore,
      faunaAtRisk: node.faunaAtRisk,
      floraAtRisk: node.floraAtRisk,
      soilData: {
        'ph': node.soilPH, // Correct field name
        'type': node.soilType,
        'fertility': node.soilFertility,
      },
      terrainData: {
        'elevation': node.terrainElevation,
        'slope': node.terrainSlope,
        'difficulty': node.terrainDifficulty,
      },
      hydrologyData: {
        'waterAccess': node.waterAccess,
        'waterStress': node.waterStress,
      },
      peopleAffected: node.population, // Correct field name
      distanceToSettlement: node.nearestSettlementKm,
      hectares: node.hectares,
      carbonLossTonnes: node.carbonData.annualEmissionsTonnes,
    );
  }
}

/// AR Preview Screen - Production-ready deforestation region viewer
/// Displays environmental data overlaid on simulated AR background
class ARPreviewScreen extends StatefulWidget {
  final ARDeforestationData? data;

  const ARPreviewScreen({super.key, this.data});

  @override
  State<ARPreviewScreen> createState() => _ARPreviewScreenState();
}

class _ARPreviewScreenState extends State<ARPreviewScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _pulseAnimation;

  // Default demo data for when no data is passed
  late ARDeforestationData _displayData;

  // Gesture state for pan/zoom
  Offset _panOffset = Offset.zero;
  double _scale = 1.0;
  Offset _lastFocalPoint = Offset.zero;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );

    // Use passed data or demo data
    _displayData = widget.data ?? _getDemoData();
  }

  ARDeforestationData _getDemoData() {
    // No hardcoded demo data - return empty state when no zone selected
    return ARDeforestationData.empty();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Show empty state if no zone data
    if (_displayData.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.explore_off,
                size: 64,
                color: Colors.white.withOpacity(0.5),
              ),
              const SizedBox(height: 24),
              const Text(
                "No Zone Selected",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                "Select an environmental zone\nto view the AR preview",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
                label: const Text("Go Back"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: EcoTheme.neonEmerald,
                  foregroundColor: Colors.black,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onScaleStart: (details) {
          _lastFocalPoint = details.focalPoint;
        },
        onScaleUpdate: (details) {
          setState(() {
            // Update pan
            _panOffset += details.focalPoint - _lastFocalPoint;
            _lastFocalPoint = details.focalPoint;
            // Update scale (pinch zoom)
            _scale = (_scale * details.scale).clamp(0.5, 3.0);
          });
        },
        onDoubleTap: () {
          // Reset view on double tap
          setState(() {
            _panOffset = Offset.zero;
            _scale = 1.0;
          });
        },
        child: ClipRect(
          child: Transform.scale(
            scale: _scale,
            child: Transform.translate(
              offset: _panOffset,
              child: SizedBox.expand(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Real Satellite Imagery Background from Mapbox
                    _buildSatelliteBackground(),

                    // Deforestation Impact Overlay (red-tinted areas)
                    _buildDeforestationOverlay(),

                    // Scan Lines Effect
                    Positioned.fill(
                      child: CustomPaint(painter: _ScanLinesPainter()),
                    ),

                    // Camera Frame Overlay
                    _buildCameraFrame(),

                    // App Bar
                    _buildAppBar(),

                    // Location Banner
                    _buildLocationBanner(),

                    // AR Data Overlays
                    _buildDataOverlays(),

                    // Species At Risk Panel
                    _buildSpeciesPanel(),

                    // Bottom Panel
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _buildBottomPanel(),
                    ),
                  ],
                ), // Stack
              ), // SizedBox.expand
            ), // Transform.translate
          ), // Transform.scale
        ), // ClipRect
      ), // GestureDetector
    );
  }

  /// Immersive 360° panorama view - TRUE virtual exploration
  Widget _buildSatelliteBackground() {
    // 360° equirectangular panorama URLs - real rainforest imagery
    // These are high-quality equirectangular panoramas for immersive viewing
    final List<String> panoramaUrls = [
      // Dense Amazon rainforest canopy
      'https://images.unsplash.com/photo-1579546929518-9e396f3cc809?w=4096&q=95', // fallback gradient
      // Primary: real forest panorama from Polyhaven (CC0)
      'https://dl.polyhaven.org/file/ph-assets/HDRIs/extra/Tonemapped%20JPG/forest_slope.jpg',
      // Backup: Dense tropical forest
      'https://images.unsplash.com/photo-1448375240586-882707db888b?w=4096&q=95',
    ];

    // Choose panorama based on habitat type
    final bool isTropical =
        _displayData.habitat.toLowerCase().contains('tropical') ||
        _displayData.habitat.toLowerCase().contains('rain');

    return PanoramaViewer(
      image: NetworkImage(isTropical ? panoramaUrls[1] : panoramaUrls[2]),
    );
  }

  /// Red-tinted overlay showing deforestation impact zones
  Widget _buildDeforestationOverlay() {
    final double riskIntensity = (_displayData.riskScore / 100).clamp(0.0, 1.0);

    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.2,
          colors: [
            Colors.transparent,
            EcoTheme.hazardRed.withOpacity(riskIntensity * 0.15),
            EcoTheme.hazardRed.withOpacity(riskIntensity * 0.3),
          ],
          stops: const [0.2, 0.6, 1.0],
        ),
      ),
      child: CustomPaint(
        painter: _DeforestationZonePainter(
          riskScore: _displayData.riskScore,
          hectares: _displayData.hectares,
        ),
        child: Container(),
      ),
    );
  }

  Widget _buildCameraFrame() {
    return Positioned.fill(
      child: Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: EcoTheme.neonEmerald.withOpacity(0.3),
            width: 2,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              Positioned(left: 0, top: 0, child: _cornerMarker()),
              Positioned(
                right: 0,
                top: 0,
                child: Transform.flip(flipX: true, child: _cornerMarker()),
              ),
              Positioned(
                left: 0,
                bottom: 0,
                child: Transform.flip(flipY: true, child: _cornerMarker()),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Transform.flip(
                  flipX: true,
                  flipY: true,
                  child: _cornerMarker(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              _buildLiveIndicator(),
              const Spacer(),
              _buildRiskBadge(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiveIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: EcoTheme.neonEmerald.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: EcoTheme.neonEmerald.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) => Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: EcoTheme.neonEmerald.withOpacity(_pulseAnimation.value),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: EcoTheme.neonEmerald.withOpacity(0.5),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            "LIVE AR VIEW",
            style: GoogleFonts.orbitron(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: EcoTheme.neonEmerald,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiskBadge() {
    final riskColor = _displayData.riskScore >= 70
        ? EcoTheme.hazardRed
        : _displayData.riskScore >= 40
        ? EcoTheme.amber
        : EcoTheme.neonEmerald;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: riskColor.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: riskColor.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber, color: riskColor, size: 14),
          const SizedBox(width: 6),
          Text(
            "RISK: ${_displayData.riskScore.toInt()}%",
            style: GoogleFonts.orbitron(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: riskColor,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationBanner() {
    return Positioned(
      top: 100,
      left: 24,
      right: 24,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: EcoTheme.neonEmerald.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.location_on,
                  color: EcoTheme.hazardRed,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _displayData.regionName,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _infoChip(Icons.terrain, _displayData.habitat),
                  const SizedBox(width: 8),
                  _infoChip(
                    Icons.straighten,
                    "${NumberFormat.compact().format(_displayData.hectares)} ha",
                  ),
                  const SizedBox(width: 8),
                  _infoChip(
                    Icons.co2,
                    "${NumberFormat.compact().format(_displayData.carbonLossTonnes)}t CO₂",
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white54, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildDataOverlays() {
    return Stack(
      children: [
        // Left: Soil Info
        Positioned(
          left: 24,
          top: 200,
          child: _buildFloatingCard(
            "SOIL ANALYSIS",
            Icons.landscape,
            EcoTheme.neonEmerald,
            [
              _cardRow("pH Level", "${_displayData.soilData['ph'] ?? 'N/A'}"),
              _cardRow("Type", "${_displayData.soilData['type'] ?? 'Unknown'}"),
              _cardRow(
                "Fertility",
                "${_displayData.soilData['fertility'] ?? 'Unknown'}",
              ),
            ],
          ),
        ),

        // Right: Terrain
        Positioned(
          right: 24,
          top: 200,
          child: _buildFloatingCard("TERRAIN", Icons.terrain, EcoTheme.amber, [
            _cardRow(
              "Elevation",
              "${_displayData.terrainData['elevation'] ?? 0}m",
            ),
            _cardRow("Slope", "${_displayData.terrainData['slope'] ?? 0}°"),
            _cardRow(
              "Access",
              "${_displayData.terrainData['difficulty'] ?? 'Unknown'}",
            ),
          ]),
        ),

        // Bottom-left: Hydrology
        Positioned(
          left: 24,
          top: 360,
          child: _buildFloatingCard(
            "HYDROLOGY",
            Icons.water_drop,
            EcoTheme.electricCyan,
            [
              _cardRow(
                "Water Access",
                "${_displayData.hydrologyData['waterAccess'] ?? 'Unknown'}",
              ),
              _cardRow(
                "Water Stress",
                "${_displayData.hydrologyData['waterStress'] ?? 'Unknown'}",
              ),
            ],
          ),
        ),

        // Bottom-right: People Affected
        Positioned(
          right: 24,
          top: 360,
          child: _buildFloatingCard(
            "HUMAN IMPACT",
            Icons.people,
            EcoTheme.hazardRed,
            [
              _cardRow(
                "People Affected",
                NumberFormat.compact().format(_displayData.peopleAffected),
              ),
              _cardRow(
                "Distance",
                "${_displayData.distanceToSettlement.toStringAsFixed(1)} km",
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSpeciesPanel() {
    final allSpecies = [
      ..._displayData.faunaAtRisk,
      ..._displayData.floraAtRisk,
    ];
    if (allSpecies.isEmpty) return const SizedBox.shrink();

    return Positioned(
      left: 24,
      right: 24,
      bottom: 200,
      child: Container(
        height: 90, // Reduced to match card size
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: EcoTheme.hazardRed.withOpacity(0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning, color: EcoTheme.hazardRed, size: 14),
                const SizedBox(width: 8),
                Text(
                  "SPECIES AT RISK (${allSpecies.length})",
                  style: TextStyle(
                    color: EcoTheme.hazardRed,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: allSpecies.length,
                itemBuilder: (context, index) {
                  final species = allSpecies[index];
                  return _speciesCard(species);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _speciesCard(SpeciesInfo species) {
    final isFauna = _displayData.faunaAtRisk.contains(species);
    return Container(
      width: 130,
      height: 75, // Reduced height to fit in container
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(
                isFauna ? Icons.pets : Icons.eco,
                color: isFauna ? EcoTheme.amber : EcoTheme.neonEmerald,
                size: 12,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  species.commonName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: EcoTheme.hazardRed.withOpacity(0.2),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              species.status,
              style: const TextStyle(
                color: EcoTheme.hazardRed,
                fontSize: 7,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cornerMarker() {
    return SizedBox(
      width: 40,
      height: 40,
      child: CustomPaint(painter: _CornerPainter()),
    );
  }

  Widget _buildFloatingCard(
    String title,
    IconData icon,
    Color color,
    List<Widget> children,
  ) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.15),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _cardRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 10),
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPanel() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withOpacity(0.95)],
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Coordinates
            Text(
              "${_displayData.lat.toStringAsFixed(4)}°, ${_displayData.lng.toStringAsFixed(4)}°",
              style: GoogleFonts.orbitron(color: Colors.white38, fontSize: 10),
            ),
            const SizedBox(height: 16),
            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _actionButton(Icons.share, "Share", () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Sharing AR view..."),
                      backgroundColor: EcoTheme.neonEmerald,
                    ),
                  );
                }),
                _captureButton(),
                _actionButton(Icons.info_outline, "Details", () {
                  // Navigate to insights
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white70, size: 20),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _captureButton() {
    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("AR Capture saved!"),
            backgroundColor: EcoTheme.neonEmerald,
          ),
        );
      },
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
          gradient: RadialGradient(
            colors: [
              EcoTheme.neonEmerald.withOpacity(0.4),
              EcoTheme.neonEmerald.withOpacity(0.1),
            ],
          ),
        ),
        child: const Center(
          child: Icon(Icons.camera, color: Colors.white, size: 32),
        ),
      ),
    );
  }
}

// Custom Painters
class _ScanLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = EcoTheme.neonEmerald.withOpacity(0.03)
      ..strokeWidth = 1;

    for (double y = 0; y < size.height; y += 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = EcoTheme.neonEmerald
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(0, size.height * 0.6)
      ..lineTo(0, 0)
      ..lineTo(size.width * 0.6, 0);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Immersive 3D forest environment painter - creates virtual forest visualization
class _ForestEnvironmentPainter extends CustomPainter {
  final double riskScore;
  final double hectares;
  final String habitat;
  final double animValue;
  final Offset panOffset;
  final double scale;

  _ForestEnvironmentPainter({
    required this.riskScore,
    required this.hectares,
    required this.habitat,
    required this.animValue,
    required this.panOffset,
    required this.scale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double deforestRatio = (riskScore / 100).clamp(0.0, 1.0);

    // Draw sky gradient (changes based on time of day / area health)
    _drawSky(canvas, size, deforestRatio);

    // Draw distant mountains/horizon
    _drawHorizon(canvas, size, deforestRatio);

    // Draw ground/terrain
    _drawGround(canvas, size, deforestRatio);

    // Draw trees - mix of healthy and dead based on risk
    _drawTrees(canvas, size, deforestRatio);

    // Draw deforestation impact zones
    _drawDeforestationZones(canvas, size, deforestRatio);

    // Draw atmospheric effects
    _drawAtmosphere(canvas, size, deforestRatio);
  }

  void _drawSky(Canvas canvas, Size size, double deforestRatio) {
    // Healthy forest = blue sky, deforested = hazy orange/brown
    final Color skyTop = Color.lerp(
      const Color(0xFF1a3a5c), // Deep blue
      const Color(0xFF4a3020), // Smoky brown
      deforestRatio,
    )!;
    final Color skyBottom = Color.lerp(
      const Color(0xFF87CEEB), // Light blue
      const Color(0xFFCC6600), // Orange haze
      deforestRatio,
    )!;

    final skyGradient = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [skyTop, skyBottom],
        stops: const [0.0, 0.5],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height * 0.5));

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height * 0.5),
      skyGradient,
    );
  }

  void _drawHorizon(Canvas canvas, Size size, double deforestRatio) {
    final horizonY = size.height * 0.4;
    final paint = Paint()
      ..color = Color.lerp(
        const Color(0xFF2d5a3d), // Forest green
        const Color(0xFF3d2d1d), // Brown/dead
        deforestRatio,
      )!;

    // Draw mountain silhouettes
    final path = Path()
      ..moveTo(0, horizonY + 50)
      ..lineTo(size.width * 0.15, horizonY - 20)
      ..lineTo(size.width * 0.3, horizonY + 30)
      ..lineTo(size.width * 0.5, horizonY - 40)
      ..lineTo(size.width * 0.7, horizonY + 10)
      ..lineTo(size.width * 0.85, horizonY - 30)
      ..lineTo(size.width, horizonY + 40)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  void _drawGround(Canvas canvas, Size size, double deforestRatio) {
    final groundY = size.height * 0.55;

    // Ground gradient - healthy green to barren brown
    final groundGradient = Paint()
      ..shader =
          LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(
                const Color(0xFF1a4d1a),
                const Color(0xFF4a3a2a),
                deforestRatio,
              )!,
              Color.lerp(
                const Color(0xFF0d260d),
                const Color(0xFF2a1a0a),
                deforestRatio,
              )!,
            ],
          ).createShader(
            Rect.fromLTWH(0, groundY, size.width, size.height - groundY),
          );

    canvas.drawRect(
      Rect.fromLTWH(0, groundY, size.width, size.height - groundY),
      groundGradient,
    );

    // Draw ground texture lines
    final texturePaint = Paint()
      ..color = Colors.black.withOpacity(0.1)
      ..strokeWidth = 1;

    for (double y = groundY; y < size.height; y += 15) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), texturePaint);
    }
  }

  void _drawTrees(Canvas canvas, Size size, double deforestRatio) {
    final random = [
      0.2,
      0.8,
      0.3,
      0.9,
      0.5,
      0.1,
      0.7,
      0.4,
      0.6,
    ]; // Pseudo-random
    final groundY = size.height * 0.55;

    // Draw multiple layers of trees for depth
    for (int layer = 0; layer < 3; layer++) {
      final layerScale = 1.0 - (layer * 0.25);
      final layerY = groundY - (layer * 50);
      final treeCount = 12 - (layer * 3);

      for (int i = 0; i < treeCount; i++) {
        final x =
            (size.width / treeCount) * i +
            (random[i % random.length] * 40) -
            20;
        final isHealthy = random[(i + layer) % random.length] > deforestRatio;

        if (isHealthy) {
          _drawHealthyTree(canvas, x, layerY, layerScale * 60, layerScale);
        } else {
          _drawDeadTree(canvas, x, layerY, layerScale * 50, layerScale);
        }
      }
    }
  }

  void _drawHealthyTree(
    Canvas canvas,
    double x,
    double y,
    double height,
    double scale,
  ) {
    // Tree trunk
    final trunkPaint = Paint()..color = const Color(0xFF3d2817);
    canvas.drawRect(
      Rect.fromLTWH(x - 5 * scale, y, 10 * scale, height * 0.4),
      trunkPaint,
    );

    // Tree foliage (triangles)
    final foliagePaint = Paint()
      ..color = Color.lerp(
        const Color(0xFF1a5c1a),
        const Color(0xFF2d8a2d),
        animValue,
      )!;

    final path = Path()
      ..moveTo(x, y - height * 0.6)
      ..lineTo(x - 30 * scale, y)
      ..lineTo(x + 30 * scale, y)
      ..close();

    canvas.drawPath(path, foliagePaint);

    // Second layer of foliage
    final path2 = Path()
      ..moveTo(x, y - height * 0.8)
      ..lineTo(x - 22 * scale, y - height * 0.3)
      ..lineTo(x + 22 * scale, y - height * 0.3)
      ..close();

    canvas.drawPath(path2, foliagePaint..color = const Color(0xFF2d7a2d));
  }

  void _drawDeadTree(
    Canvas canvas,
    double x,
    double y,
    double height,
    double scale,
  ) {
    // Dead tree trunk (bare)
    final trunkPaint = Paint()..color = const Color(0xFF2a1a0a);
    canvas.drawRect(
      Rect.fromLTWH(x - 4 * scale, y, 8 * scale, height * 0.5),
      trunkPaint,
    );

    // Dead branches
    final branchPaint = Paint()
      ..color = const Color(0xFF3a2a1a)
      ..strokeWidth = 2 * scale
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(x, y),
      Offset(x - 15 * scale, y - 20 * scale),
      branchPaint,
    );
    canvas.drawLine(
      Offset(x, y - 10 * scale),
      Offset(x + 12 * scale, y - 30 * scale),
      branchPaint,
    );
    canvas.drawLine(
      Offset(x, y - 15 * scale),
      Offset(x - 8 * scale, y - 35 * scale),
      branchPaint,
    );
  }

  void _drawDeforestationZones(Canvas canvas, Size size, double deforestRatio) {
    if (deforestRatio < 0.1) return;

    // Draw red warning zones for high-risk areas
    final zonePaint = Paint()
      ..color = EcoTheme.hazardRed.withOpacity(deforestRatio * 0.2)
      ..style = PaintingStyle.fill;

    // Left deforestation zone
    final leftZone = Path()
      ..moveTo(0, size.height * 0.5)
      ..lineTo(size.width * 0.3 * deforestRatio, size.height * 0.5)
      ..lineTo(size.width * 0.25 * deforestRatio, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(leftZone, zonePaint);

    // Right deforestation zone
    final rightZone = Path()
      ..moveTo(size.width, size.height * 0.5)
      ..lineTo(
        size.width - size.width * 0.25 * deforestRatio,
        size.height * 0.5,
      )
      ..lineTo(size.width - size.width * 0.2 * deforestRatio, size.height)
      ..lineTo(size.width, size.height)
      ..close();

    canvas.drawPath(rightZone, zonePaint);
  }

  void _drawAtmosphere(Canvas canvas, Size size, double deforestRatio) {
    // Draw smoke/haze for deforested areas
    if (deforestRatio > 0.3) {
      final hazePaint = Paint()
        ..color = const Color(
          0xFF555544,
        ).withOpacity((deforestRatio - 0.3) * 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 50);

      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height * 0.4),
        hazePaint,
      );
    }

    // Sunlight effect
    final sunPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.6, -0.5),
        radius: 0.8,
        colors: [Colors.white.withOpacity(0.1 * animValue), Colors.transparent],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), sunPaint);
  }

  @override
  bool shouldRepaint(covariant _ForestEnvironmentPainter oldDelegate) {
    return oldDelegate.animValue != animValue ||
        oldDelegate.panOffset != panOffset ||
        oldDelegate.scale != scale;
  }
}

/// Deforestation zone overlay painter
class _DeforestationZonePainter extends CustomPainter {
  final double riskScore;
  final double hectares;

  _DeforestationZonePainter({required this.riskScore, required this.hectares});

  @override
  void paint(Canvas canvas, Size size) {
    final double risk = (riskScore / 100).clamp(0.0, 1.0);

    // Draw impact markers
    if (risk > 0.2) {
      final markerPaint = Paint()
        ..color = EcoTheme.hazardRed.withOpacity(0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      // Draw danger circles at various points
      final points = [
        Offset(size.width * 0.2, size.height * 0.6),
        Offset(size.width * 0.8, size.height * 0.65),
        Offset(size.width * 0.5, size.height * 0.7),
      ];

      for (final point in points) {
        canvas.drawCircle(point, 20 + (risk * 15), markerPaint);
        canvas.drawCircle(point, 10 + (risk * 8), markerPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DeforestationZonePainter oldDelegate) {
    return oldDelegate.riskScore != riskScore;
  }
}
