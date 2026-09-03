import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'package:ecolens/core/gis_theme.dart';
import 'package:ecolens/model/hazard_models.dart';
import 'package:ecolens/views/unity_simulation_screen.dart';

// ═══════════════════════════════════════════════════════════════
// HAZARD DETAIL CARD
// Animated bottom card showing details of a selected hazard feature
// ═══════════════════════════════════════════════════════════════

class HazardDetailCard extends StatefulWidget {
  final HazardFeature feature;
  final VoidCallback onDismiss;
  final VoidCallback? onMonitor;
  final VoidCallback? onShare;

  const HazardDetailCard({
    super.key,
    required this.feature,
    required this.onDismiss,
    this.onMonitor,
    this.onShare,
  });

  @override
  State<HazardDetailCard> createState() => _HazardDetailCardState();
}

class _HazardDetailCardState extends State<HazardDetailCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    await _controller.reverse();
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final feature = widget.feature;

    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: GestureDetector(
          onVerticalDragEnd: (details) {
            if (details.primaryVelocity != null &&
                details.primaryVelocity! > 200) {
              _dismiss();
            }
          },
          child: Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: GISTheme.surfaceDark,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: GISTheme.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 20,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 8),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: GISTheme.textTertiary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Colored header bar
                _buildHeader(feature),

                // Content
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Location and timestamp
                      _buildLocationRow(feature),
                      const SizedBox(height: 12),

                      // Key properties table
                      _buildPropertiesTable(feature),

                      // Expandable additional data
                      if (feature.properties.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _buildExpandableSection(feature),
                      ],

                      const SizedBox(height: 16),

                      // Action buttons
                      _buildActionButtons(context, feature),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(HazardFeature feature) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: feature.type.color.withValues(alpha: 0.15),
        border: Border(
          bottom: BorderSide(
            color: feature.type.color.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          // Type icon
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: feature.type.color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              feature.type.icon,
              color: feature.type.color,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),

          // Title and type
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  feature.type.label,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: GISTheme.textPrimary,
                  ),
                ),
                Text(
                  'ID: ${feature.id}',
                  style: GISTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Severity badge
          _buildSeverityBadge(feature.severity),

          const SizedBox(width: 8),

          // Close button
          InkWell(
            onTap: _dismiss,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.close,
                color: GISTheme.textSecondary,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeverityBadge(Severity severity) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: severity.color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: severity.color.withValues(alpha: 0.5)),
      ),
      child: Text(
        severity.label,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: severity.color,
        ),
      ),
    );
  }

  Widget _buildLocationRow(HazardFeature feature) {
    final dateFormat = DateFormat('MMM d, yyyy HH:mm');

    return Row(
      children: [
        Icon(Icons.location_on, size: 14, color: GISTheme.textTertiary),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            '${feature.latitude.toStringAsFixed(4)}, '
            '${feature.longitude.toStringAsFixed(4)}',
            style: GISTheme.bodySmall,
          ),
        ),
        Icon(Icons.access_time, size: 14, color: GISTheme.textTertiary),
        const SizedBox(width: 4),
        Text(
          dateFormat.format(feature.timestamp),
          style: GISTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildPropertiesTable(HazardFeature feature) {
    final rows = <MapEntry<String, String>>[];

    // Type-specific properties
    if (feature is FireHotspot) {
      rows.addAll([
        MapEntry('Brightness', feature.brightness.toStringAsFixed(1)),
        MapEntry('FRP', '${feature.frp.toStringAsFixed(1)} MW'),
        MapEntry('Satellite', feature.satellite),
        MapEntry('Confidence', '${feature.confidence.toStringAsFixed(0)}%'),
      ]);
    } else if (feature is FloodAlert) {
      rows.addAll([
        MapEntry('Observed Stage', '${feature.observedStage.toStringAsFixed(2)} ft'),
        MapEntry('Flood Stage', '${feature.floodStage.toStringAsFixed(2)} ft'),
        MapEntry('Status', feature.status.toUpperCase()),
        if (feature.forecast != null && feature.forecast!.isNotEmpty)
          MapEntry('Forecast Peak', '${feature.forecast!.reduce((a, b) => a > b ? a : b).toStringAsFixed(2)} ft'),
      ]);
    } else if (feature is GlacierOutline) {
      rows.addAll([
        MapEntry('Glacier', feature.glacierName),
        MapEntry('Area', '${feature.areaKm2.toStringAsFixed(2)} km2'),
        if (feature.retreatRateKm2PerYear != null)
          MapEntry('Retreat Rate', '${feature.retreatRateKm2PerYear!.toStringAsFixed(3)} km2/yr'),
      ]);
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: GISTheme.panelDecoration,
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: i < rows.length - 1
                    ? Border(
                        bottom: BorderSide(color: GISTheme.border, width: 1),
                      )
                    : null,
              ),
              child: Row(
                children: [
                  Text(
                    rows[i].key,
                    style: GISTheme.label,
                  ),
                  const Spacer(),
                  Text(
                    rows[i].value,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      color: GISTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildExpandableSection(HazardFeature feature) {
    // Filter out properties already displayed in the table
    final displayedKeys = {
      'hazardType',
      'severity',
      'timestamp',
      'brightness',
      'frp',
      'satellite',
      'confidence',
      'observedStage',
      'floodStage',
      'status',
      'forecast',
      'glacierName',
      'areaKm2',
      'retreatRateKm2PerYear',
    };

    final extraProps = feature.properties.entries
        .where((e) => !displayedKeys.contains(e.key))
        .toList();

    if (extraProps.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Text(
                  'Additional Data',
                  style: GISTheme.label,
                ),
                const Spacer(),
                Icon(
                  _isExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 18,
                  color: GISTheme.textTertiary,
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState:
              _isExpanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          firstChild: Container(
            decoration: GISTheme.panelDecoration,
            child: Column(
              children: [
                for (int i = 0; i < extraProps.length; i++)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      border: i < extraProps.length - 1
                          ? Border(
                              bottom:
                                  BorderSide(color: GISTheme.border, width: 1),
                            )
                          : null,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(
                            extraProps[i].key,
                            style: GISTheme.labelSmall,
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            '${extraProps[i].value}',
                            style: GISTheme.bodySmall,
                            textAlign: TextAlign.right,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          secondChild: const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context, HazardFeature feature) {
    return Row(
      children: [
        // View in 3D — passes geographic metadata for accurate terrain
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () {
              // Compute a ~5km bbox around the feature for DEM fetch
              const double offset = 0.045; // ~5km at mid-latitudes
              final bbox = [
                feature.longitude - offset,
                feature.latitude - offset,
                feature.longitude + offset,
                feature.latitude + offset,
              ];
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => UnitySimulationScreen(
                    simulationType: _mapHazardToSimulation(feature.type),
                    locationName: feature.properties['name'] as String? ??
                        feature.type.label,
                    latitude: feature.latitude,
                    longitude: feature.longitude,
                    bbox: bbox,
                    metadata: {
                      'bbox': bbox,
                      'originLat': feature.latitude,
                      'originLon': feature.longitude,
                      ...feature.properties,
                    },
                  ),
                ),
              );
            },
            icon: const Icon(Icons.view_in_ar, size: 16),
            label: Text(
              'View in 3D',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: GISTheme.accentBlue.withValues(alpha: 0.15),
              foregroundColor: GISTheme.accentBlue,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: BorderSide(
                  color: GISTheme.accentBlue.withValues(alpha: 0.3),
                ),
              ),
            ),
          ),
        ),
        // Monitor and Share render only when the host actually wired them.
        // A tappable control that does nothing is worse than no control.
        if (widget.onMonitor != null) ...[
          const SizedBox(width: 8),
          _IconActionButton(
            icon: Icons.notifications_active_outlined,
            color: GISTheme.accentOrange,
            tooltip: 'Monitor',
            onTap: widget.onMonitor,
          ),
        ],
        if (widget.onShare != null) ...[
          const SizedBox(width: 8),
          _IconActionButton(
            icon: Icons.share_outlined,
            color: GISTheme.accentGreen,
            tooltip: 'Share',
            onTap: widget.onShare,
          ),
        ],
      ],
    );
  }

  String _mapHazardToSimulation(HazardType type) {
    switch (type) {
      case HazardType.wildfire:
        return 'wildfire';
      case HazardType.flood:
        return 'flood';
      case HazardType.drought:
        return 'drought';
      case HazardType.glacier:
        return 'glacialRetreat';
      default:
        return 'wildfire';
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Small icon action button
// ─────────────────────────────────────────────────────────────

class _IconActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onTap;

  const _IconActionButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(color: color.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(6),
            color: color.withValues(alpha: 0.1),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}
