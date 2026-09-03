import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:ecolens/core/gis_theme.dart';
import 'package:ecolens/model/hazard_models.dart';
import 'package:ecolens/viewmodels/hazard_viewmodel.dart';
import 'package:ecolens/widgets/hazard_chip_bar.dart';

// ═══════════════════════════════════════════════════════════════
// HAZARD LEGEND
// Interactive map legend that doubles as a filter control.
// Bottom-left on web, bottom-left above chip bar on mobile.
// ═══════════════════════════════════════════════════════════════

// ─────────────────────────────────────────────────────────────
// Official colour scales
// ─────────────────────────────────────────────────────────────

/// USDM drought classification (exact hex).
class DroughtColors {
  static const d0 = Color(0xFFFFFF00); // D0 Abnormally Dry
  static const d1 = Color(0xFFFCD37F); // D1 Moderate
  static const d2 = Color(0xFFFFAA00); // D2 Severe
  static const d3 = Color(0xFFE60000); // D3 Extreme
  static const d4 = Color(0xFF730000); // D4 Exceptional

  static const List<_CategoryEntry> scale = [
    _CategoryEntry('D0 Abnormally Dry', d0),
    _CategoryEntry('D1 Moderate', d1),
    _CategoryEntry('D2 Severe', d2),
    _CategoryEntry('D3 Extreme', d3),
    _CategoryEntry('D4 Exceptional', d4),
  ];
}

/// Fire confidence Low→High.
class FireColors {
  static const low = Color(0xFFFFEDA0);
  static const high = Color(0xFFBD0026);
}

/// Flood severity scale (NWS).
class FloodColors {
  static const action = Color(0xFF00FF00);
  static const minor = Color(0xFFFFFF00);
  static const moderate = Color(0xFFFF8C00);
  static const major = Color(0xFFFF0000);
  static const record = Color(0xFFCC00CC);

  static const List<_CategoryEntry> scale = [
    _CategoryEntry('Action', action),
    _CategoryEntry('Minor', minor),
    _CategoryEntry('Moderate', moderate),
    _CategoryEntry('Major', major),
    _CategoryEntry('Record', record),
  ];
}

class _CategoryEntry {
  final String label;
  final Color color;
  const _CategoryEntry(this.label, this.color);
}

// ─────────────────────────────────────────────────────────────
// Main widget
// ─────────────────────────────────────────────────────────────

class HazardLegend extends StatefulWidget {
  /// Whether the legend starts expanded (default: expanded on web, collapsed on mobile).
  final bool? initiallyExpanded;

  const HazardLegend({super.key, this.initiallyExpanded});

  @override
  State<HazardLegend> createState() => _HazardLegendState();
}

class _HazardLegendState extends State<HazardLegend>
    with SingleTickerProviderStateMixin {
  late bool _isExpanded;
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _isExpanded = widget.initiallyExpanded ?? kIsWeb;

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: _isExpanded ? 1.0 : 0.0,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.3, 1.0, curve: Curves.easeIn),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _animController.forward();
      } else {
        _animController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final maxLegendHeight = screenHeight * 0.4;

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, _) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              constraints: BoxConstraints(
                maxWidth: _isExpanded ? 260 : 100,
                maxHeight: _isExpanded ? maxLegendHeight : 36,
              ),
              decoration: BoxDecoration(
                color: GISTheme.backgroundDark.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: GISTheme.border.withValues(alpha: 0.6),
                  width: 1,
                ),
              ),
              child: _isExpanded
                  ? _buildExpanded(maxLegendHeight)
                  : _buildCollapsed(),
            ),
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Collapsed state
  // ─────────────────────────────────────────────────────────────

  Widget _buildCollapsed() {
    return InkWell(
      onTap: _toggle,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.layers, size: 16, color: GISTheme.accentBlue),
            const SizedBox(width: 6),
            Text(
              'Legend',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: GISTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Expanded state
  // ─────────────────────────────────────────────────────────────

  Widget _buildExpanded(double maxHeight) {
    final vm = context.watch<HazardViewModel>();

    // Collect only visible layers
    final visibleTypes = HazardType.values
        .where((t) => vm.layerVisibility[t] == true)
        .toList();

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          _buildExpandedHeader(),

          // Divider
          Container(height: 1, color: GISTheme.border.withValues(alpha: 0.5)),

          // Scrollable legend entries
          Flexible(
            child: visibleTypes.isEmpty
                ? _buildEmptyState()
                : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    itemCount: visibleTypes.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      final type = visibleTypes[index];
                      return _LegendEntry(type: type);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.layers, size: 16, color: GISTheme.accentBlue),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Legend',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: GISTheme.textPrimary,
              ),
            ),
          ),
          InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(4),
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(
                Icons.keyboard_arrow_down,
                size: 18,
                color: GISTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        'No layers active.\nToggle layers to see their legend.',
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
          fontSize: 11,
          color: GISTheme.textTertiary,
          height: 1.4,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Legend entry per hazard type
// ─────────────────────────────────────────────────────────────

class _LegendEntry extends StatelessWidget {
  final HazardType type;
  const _LegendEntry({required this.type});

  @override
  Widget build(BuildContext context) {
    final vm = context.read<HazardViewModel>();
    final isVisible = vm.layerVisibility[type] ?? false;

    return GestureDetector(
      onTap: () => vm.toggleLayer(type),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: isVisible ? 1.0 : 0.4,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: GISTheme.surfaceLight.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row: icon + label
              Row(
                children: [
                  Icon(
                    type.icon,
                    size: 14,
                    color: HazardColors.forType(type),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    type.label,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: GISTheme.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),

              // Symbology
              _buildSymbology(type),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSymbology(HazardType type) {
    switch (type) {
      case HazardType.wildfire:
        return _buildGradientBar(
          colors: [FireColors.low, FireColors.high],
          minLabel: 'Low',
          maxLabel: 'High',
          title: 'Confidence',
        );

      case HazardType.flood:
        return _buildCategorySwatches(FloodColors.scale);

      case HazardType.drought:
        return _buildCategorySwatches(DroughtColors.scale);

      case HazardType.glacier:
        return _buildPointSymbols();

      case HazardType.ndvi:
        return _buildGradientBar(
          colors: [
            const Color(0xFFD73027), // Red (bare)
            const Color(0xFFFEE08B), // Yellow (sparse)
            const Color(0xFF1A9850), // Green (dense)
          ],
          minLabel: '-1 Bare',
          maxLabel: '+1 Dense',
          title: 'NDVI',
        );

      case HazardType.watershed:
        return _buildLineSymbol();

      case HazardType.riskSurface:
        return _buildGradientBar(
          colors: [
            const Color(0xFF2166AC), // Blue (low)
            const Color(0xFFFEE08B), // Yellow (mid)
            const Color(0xFFD73027), // Red (high)
          ],
          minLabel: 'Low',
          maxLabel: 'High',
          title: 'Risk',
        );
    }
  }

  // ─────────────── Gradient bar ───────────────

  Widget _buildGradientBar({
    required List<Color> colors,
    required String minLabel,
    required String maxLabel,
    required String title,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 10,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            gradient: LinearGradient(colors: colors),
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(minLabel, style: _scaleLabelStyle),
            Text(maxLabel, style: _scaleLabelStyle),
          ],
        ),
      ],
    );
  }

  // ─────────────── Category swatches ───────────────

  Widget _buildCategorySwatches(List<_CategoryEntry> entries) {
    return Wrap(
      spacing: 4,
      runSpacing: 2,
      children: entries.map((e) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: e.color,
                borderRadius: BorderRadius.circular(2),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2),
                  width: 0.5,
                ),
              ),
            ),
            const SizedBox(width: 3),
            Text(e.label, style: _scaleLabelStyle),
          ],
        );
      }).toList(),
    );
  }

  // ─────────────── Point symbols (glaciers) ───────────────

  Widget _buildPointSymbols() {
    return Row(
      children: [
        // Small circle
        _circle(6, HazardColors.glacier.withValues(alpha: 0.5)),
        const SizedBox(width: 3),
        Text('Small', style: _scaleLabelStyle),
        const SizedBox(width: 8),
        // Medium circle
        _circle(9, HazardColors.glacier.withValues(alpha: 0.7)),
        const SizedBox(width: 3),
        Text('Medium', style: _scaleLabelStyle),
        const SizedBox(width: 8),
        // Large circle
        _circle(12, HazardColors.glacier),
        const SizedBox(width: 3),
        Text('Large', style: _scaleLabelStyle),
      ],
    );
  }

  Widget _circle(double diameter, Color color) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
    );
  }

  // ─────────────── Line symbol (watersheds) ───────────────

  Widget _buildLineSymbol() {
    return Row(
      children: [
        Container(
          width: 24,
          height: 3,
          decoration: BoxDecoration(
            color: HazardColors.watershed,
            borderRadius: BorderRadius.circular(1.5),
          ),
        ),
        const SizedBox(width: 4),
        Text('Boundary', style: _scaleLabelStyle),
        const SizedBox(width: 10),
        CustomPaint(
          size: const Size(24, 3),
          painter: _DashedLinePainter(color: HazardColors.watershed),
        ),
        const SizedBox(width: 4),
        Text('Sub-basin', style: _scaleLabelStyle),
      ],
    );
  }

  static TextStyle get _scaleLabelStyle => GoogleFonts.inter(
        fontSize: 9,
        fontWeight: FontWeight.w400,
        color: GISTheme.textTertiary,
      );
}

// ─────────────────────────────────────────────────────────────
// Dashed line painter for watershed sub-basin symbol
// ─────────────────────────────────────────────────────────────

class _DashedLinePainter extends CustomPainter {
  final Color color;
  _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    const dashWidth = 4.0;
    const dashSpace = 3.0;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset((x + dashWidth).clamp(0, size.width), size.height / 2),
        paint,
      );
      x += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) =>
      color != oldDelegate.color;
}
