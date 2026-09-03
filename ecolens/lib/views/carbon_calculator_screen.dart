import 'dart:convert';

import 'package:ecolens/core/theme.dart';
import 'package:ecolens/viewmodels/carbon_calculator_viewmodel.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

/// Carbon Credit Calculator Screen
/// Tracks land boundaries and calculates carbon credit value.
///
/// Two input modes:
///  - Mobile (GPS): user walks the perimeter and taps "Add point" at each
///    corner; viewmodel captures Geolocator position.
///  - Web (tap-to-drop): user taps directly on the embedded MapLibre
///    satellite map; tap coords are forwarded to viewmodel via JS bridge.
class CarbonCalculatorScreen extends StatefulWidget {
  const CarbonCalculatorScreen({super.key});

  @override
  State<CarbonCalculatorScreen> createState() => _CarbonCalculatorScreenState();
}

class _CarbonCalculatorScreenState extends State<CarbonCalculatorScreen> {
  InAppWebViewController? _mapController;
  int _lastSyncedPointCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<CarbonCalculatorViewModel>(context, listen: false).init();
    });
  }

  /// Push the current boundary points to the embedded map so visual
  /// state matches the viewmodel (e.g. after Undo / Clear).
  Future<void> _syncMapPoints(CarbonCalculatorViewModel vm) async {
    if (_mapController == null) return;
    if (vm.boundaryPoints.length == _lastSyncedPointCount) return;
    _lastSyncedPointCount = vm.boundaryPoints.length;

    final pointsJson = jsonEncode(
      vm.boundaryPoints
          .map((p) => {'lat': p.latitude, 'lng': p.longitude})
          .toList(),
    );
    await _mapController!.evaluateJavascript(
      source: 'window.carbonMap && window.carbonMap.setPoints($pointsJson);',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EcoTheme.background,
      appBar: AppBar(
        backgroundColor: EcoTheme.background,
        elevation: 0,
        title: Text(
          "Carbon Credit Calculator",
          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          Consumer<CarbonCalculatorViewModel>(
            builder: (context, vm, child) {
              if (vm.hasResult) {
                return IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => vm.clearBoundary(),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: Consumer<CarbonCalculatorViewModel>(
        builder: (context, vm, child) {
          if (vm.hasResult) {
            return _buildResultsView(vm);
          }
          return _buildTrackingView(vm);
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Tracking View
  // ═══════════════════════════════════════════════════════════════

  Widget _buildTrackingView(CarbonCalculatorViewModel vm) {
    return Column(
      children: [
        // Instructions Header
        _buildInstructionsHeader(vm),

        // Map
        Expanded(child: _buildMap(vm)),

        // Control Panel
        _buildControlPanel(vm),
      ],
    );
  }

  Widget _buildInstructionsHeader(CarbonCalculatorViewModel vm) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00AA55), EcoTheme.cyan],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.landscape, size: 32, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Track Land Boundary',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const Text(
                      'Walk around your land to record GPS points',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatChip(
                'Points',
                '${vm.boundaryPoints.length}',
                EcoTheme.cyan,
              ),
              _buildStatChip(
                'Area',
                '${vm.calculateApproximateArea().toStringAsFixed(2)} ha',
                EcoTheme.forestGreen,
              ),
              _buildStatChip(
                'Status',
                vm.isTracking ? 'Tracking' : 'Stopped',
                vm.isTracking ? Colors.green : Colors.grey,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildMap(CarbonCalculatorViewModel vm) {
    // Embed the dedicated MapLibre satellite map (assets/carbon_map/index.html).
    // Tap events come back through the InAppWebView JS bridge and are
    // forwarded to the viewmodel via addPointAtCoords(). Visual polygon
    // state on the map mirrors viewmodel state through _syncMapPoints().
    //
    // After every build, we ask the map to re-sync if the point count
    // changed (e.g. after Undo / Clear from the control panel).
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncMapPoints(vm));

    return Stack(
      children: [
        InAppWebView(
          initialFile: 'assets/carbon_map/index.html',
          initialSettings: InAppWebViewSettings(
            transparentBackground: true,
            javaScriptEnabled: true,
            mediaPlaybackRequiresUserGesture: false,
            iframeAllow: 'fullscreen; geolocation',
          ),
          onWebViewCreated: (controller) {
            _mapController = controller;
            // Register the JS handler that the HTML calls on tap events.
            // On Flutter Web this becomes a postMessage handler instead;
            // the HTML sends to both channels so it works either way.
            if (!kIsWeb) {
              controller.addJavaScriptHandler(
                handlerName: 'onCarbonMapEvent',
                callback: (args) {
                  if (args.isEmpty) return null;
                  _handleMapEvent(args[0], vm);
                  return null;
                },
              );
            }
          },
        ),
        // Tracking-mode badge so the user knows tap-to-drop is active.
        Positioned(
          top: 12, right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: vm.isTracking
                  ? EcoTheme.neonEmerald.withValues(alpha: 0.18)
                  : Colors.white12,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: vm.isTracking
                    ? EcoTheme.neonEmerald
                    : Colors.white24,
              ),
            ),
            child: Text(
              vm.isTracking ? 'TRACKING' : 'TAP "START" TO BEGIN',
              style: TextStyle(
                color: vm.isTracking
                    ? EcoTheme.neonEmerald
                    : Colors.white60,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Route an event from the embedded map back to the viewmodel.
  /// Currently the only event is "pointAdded" — user tapped to drop a corner.
  void _handleMapEvent(dynamic raw, CarbonCalculatorViewModel vm) {
    try {
      final payload = raw is String ? jsonDecode(raw) : raw;
      if (payload is! Map) return;
      final event = payload['event'] as String?;
      final data = payload['data'];
      if (event == 'pointAdded' && data is Map) {
        final lat = (data['lat'] as num?)?.toDouble();
        final lng = (data['lng'] as num?)?.toDouble();
        if (lat != null && lng != null) {
          if (!vm.isTracking) {
            // Auto-start tracking on first tap so the user doesn't have
            // to press a separate button before they can drop points.
            vm.startTracking();
          }
          vm.addPointAtCoords(lat, lng);
          // Bump our sync counter so the map state stays consistent.
          _lastSyncedPointCount = vm.boundaryPoints.length;
        }
      }
    } catch (_) {
      // Ignore malformed bridge payloads — the map will just look out of sync.
    }
  }

  Widget _buildControlPanel(CarbonCalculatorViewModel vm) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EcoTheme.cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Error Display
          if (vm.error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                border: Border.all(color: Colors.red),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      vm.error!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Control Buttons
          Row(
            children: [
              if (!vm.isTracking) ...[
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: vm.isCalculating
                        ? null
                        : () => vm.startTracking(),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start Tracking'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: EcoTheme.forestGreen,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ] else ...[
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => vm.addBoundaryPoint(),
                    icon: const Icon(Icons.add_location),
                    label: Text('Add Point (${vm.boundaryPoints.length})'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: EcoTheme.cyan,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => vm.stopTracking(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 16,
                    ),
                  ),
                  child: const Icon(Icons.stop),
                ),
              ],
            ],
          ),

          const SizedBox(height: 8),

          // Secondary Actions
          Row(
            children: [
              if (vm.boundaryPoints.isNotEmpty && !vm.isTracking) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => vm.removeLastPoint(),
                    icon: const Icon(Icons.undo),
                    label: const Text('Remove Last'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange,
                      side: const BorderSide(color: Colors.orange),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => vm.clearBoundary(),
                    icon: const Icon(Icons.delete),
                    label: const Text('Clear All'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 12),

          // Calculate Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: vm.canCalculate && !vm.isCalculating && !vm.isTracking
                  ? () => vm.calculateCarbon()
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00AA55),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: vm.isCalculating
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        ),
                        SizedBox(width: 12),
                        Text('Calculating...'),
                      ],
                    )
                  : Text(
                      'Calculate Carbon Value (${vm.boundaryPoints.length} points)',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Results View
  // ═══════════════════════════════════════════════════════════════

  Widget _buildResultsView(CarbonCalculatorViewModel vm) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Card
          _buildHeaderCard(vm),

          const SizedBox(height: 16),

          // Results based on land type
          if (vm.isExistingForest) ...[
            _buildCarbonStockCard(vm),
            const SizedBox(height: 16),
            _buildMarketValueCard(vm),
            const SizedBox(height: 16),
            _buildEcosystemServicesCard(vm),
          ] else ...[
            _buildRestorationPotentialCard(vm),
            const SizedBox(height: 16),
            _buildInvestmentCard(vm),
            const SizedBox(height: 16),
            _buildROICard(vm),
          ],

          const SizedBox(height: 16),

          // Recommendations
          _buildRecommendationsCard(vm),
        ],
      ),
    );
  }

  Widget _buildHeaderCard(CarbonCalculatorViewModel vm) {
    final isForest = vm.isExistingForest;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isForest
              ? [EcoTheme.forestGreen, const Color(0xFF00AA55)]
              : [Colors.orange, Colors.deepOrange],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(
            isForest ? Icons.forest : Icons.restore,
            size: 48,
            color: Colors.white,
          ),
          const SizedBox(height: 12),
          Text(
            isForest ? 'Existing Forest' : 'Restorable Land',
            style: GoogleFonts.inter(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${vm.areaHectares.toStringAsFixed(2)} hectares',
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildCarbonStockCard(CarbonCalculatorViewModel vm) {
    final stock = vm.carbonStock;
    return _buildInfoCard('Carbon Stock', Icons.co2, [
      _buildLargeValue('${stock['total_tons_co2e']} tons', 'Total CO₂e'),
      const SizedBox(height: 12),
      _buildInfoRow('Per Hectare', '${stock['tons_per_hectare']} tons'),
      _buildInfoRow('Biomass', '${stock['biomass_tons_per_ha']} tons/ha'),
    ]);
  }

  Widget _buildMarketValueCard(CarbonCalculatorViewModel vm) {
    final market = vm.marketValue;
    final carbonValue =
        market['carbon_value_range_usd'] as Map<String, dynamic>?;
    final totalValue = market['total_range_usd'] as Map<String, dynamic>?;

    return _buildInfoCard('Market Value', Icons.payments, [
      _buildLargeValue(
        '\$${totalValue?['low'] ?? 0} - \$${totalValue?['high'] ?? 0}',
        'Total Value Range',
        color: EcoTheme.cyan,
      ),
      const SizedBox(height: 12),
      _buildInfoRow(
        'Carbon Credits',
        '\$${carbonValue?['low']} - \$${carbonValue?['high']}',
      ),
      _buildInfoRow(
        'Biodiversity Credits',
        '\$${market['biodiversity_credits_value_usd']}',
      ),
    ]);
  }

  Widget _buildEcosystemServicesCard(CarbonCalculatorViewModel vm) {
    final services = vm.ecosystemServices;
    final servicesList = List<String>.from(services['services'] ?? []);

    return _buildInfoCard('Ecosystem Services', Icons.nature, [
      _buildLargeValue(
        '\$${services['annual_value_usd']}/year',
        'Annual Value',
        color: EcoTheme.forestGreen,
      ),
      const SizedBox(height: 12),
      ...servicesList.map(
        (service) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: EcoTheme.cyan, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  service,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
      ),
    ]);
  }

  Widget _buildRestorationPotentialCard(CarbonCalculatorViewModel vm) {
    final potential = vm.restorationPotential;
    final year10 = potential['10_years'] as Map<String, dynamic>?;
    final year20 = potential['20_years'] as Map<String, dynamic>?;

    return _buildInfoCard('Restoration Potential', Icons.trending_up, [
      _buildTimelineRow('10 Years', year10),
      const Divider(color: Colors.white24),
      _buildTimelineRow('20 Years', year20),
    ]);
  }

  Widget _buildTimelineRow(String label, Map<String, dynamic>? data) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.bold,
              color: EcoTheme.cyan,
            ),
          ),
          const SizedBox(height: 8),
          _buildInfoRow(
            'Carbon Sequestered',
            '${data?['carbon_sequestered_tons_co2e']} tons CO₂e',
          ),
          _buildInfoRow(
            'Market Value',
            '\$${data?['market_value_usd']}',
            valueColor: EcoTheme.forestGreen,
          ),
          _buildInfoRow('Expected NDVI', '${data?['expected_ndvi']}'),
        ],
      ),
    );
  }

  Widget _buildInvestmentCard(CarbonCalculatorViewModel vm) {
    final investment = vm.investmentRequired;
    return _buildInfoCard('Investment Required', Icons.account_balance, [
      _buildLargeValue(
        '\$${investment['establishment_cost_usd']}',
        'Establishment Cost',
        color: Colors.orange,
      ),
      const SizedBox(height: 12),
      _buildInfoRow('Per Hectare', '\$${investment['cost_per_hectare']}'),
      _buildInfoRow(
        '5-Year Maintenance',
        '\$${investment['maintenance_5yr_usd']}',
      ),
    ]);
  }

  Widget _buildROICard(CarbonCalculatorViewModel vm) {
    final roi = vm.roiAnalysis;
    return _buildInfoCard('ROI Analysis', Icons.show_chart, [
      _buildInfoRow(
        '10-Year Net Value',
        '\$${roi['10yr_net_value_usd']}',
        valueColor: EcoTheme.cyan,
      ),
      _buildInfoRow(
        '20-Year Net Value',
        '\$${roi['20yr_net_value_usd']}',
        valueColor: EcoTheme.forestGreen,
      ),
      _buildInfoRow('Payback Period', '${roi['payback_period_years']} years'),
    ]);
  }

  Widget _buildRecommendationsCard(CarbonCalculatorViewModel vm) {
    final recommendations = vm.recommendations;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EcoTheme.cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.recommend, color: EcoTheme.cyan),
              const SizedBox(width: 8),
              Text(
                'Next Steps',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...recommendations.asMap().entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: EcoTheme.cyan,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${entry.key + 1}',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      entry.value,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String title, IconData icon, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EcoTheme.cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: EcoTheme.cyan),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildLargeValue(String value, String label, {Color? color}) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: color ?? Colors.white,
          ),
          textAlign: TextAlign.center,
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 14),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// Custom painter for boundary polygon
class BoundaryPainter extends CustomPainter {
  final List<dynamic> boundaryPoints;

  BoundaryPainter({required this.boundaryPoints});

  @override
  void paint(Canvas canvas, Size size) {
    if (boundaryPoints.length < 3) return;

    final paint = Paint()
      ..color = const Color(0xFF00D26A).withOpacity(0.3)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = const Color(0xFF00D26A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final path = Path();
    // Simple normalization for visualization (just scaling to fit box)
    // In production, this needs Mapbox projection
    if (boundaryPoints.isEmpty) return;

    // Just draw a placeholder polygon for now since we can't project GPS to Canvas easily
    // without the Map controller's context
    path.moveTo(size.width * 0.5, size.height * 0.2);
    path.lineTo(size.width * 0.8, size.height * 0.8);
    path.lineTo(size.width * 0.2, size.height * 0.8);
    path.close();

    canvas.drawPath(path, paint);
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
