import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ecolens/model/spatial_analysis_result.dart';
import 'package:ecolens/core/theme.dart';

/// Floating toolbar for selecting spatial analysis types
class AnalysisToolbar extends StatefulWidget {
  final Function(SpatialAnalysisType) onAnalysisSelected;
  final SpatialAnalysisType? activeAnalysis;
  final bool isAnalyzing;
  final VoidCallback? onClose;

  const AnalysisToolbar({
    super.key,
    required this.onAnalysisSelected,
    this.activeAnalysis,
    this.isAnalyzing = false,
    this.onClose,
  });

  @override
  State<AnalysisToolbar> createState() => _AnalysisToolbarState();
}

class _AnalysisToolbarState extends State<AnalysisToolbar>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = true;
  late AnimationController _animController;
  late Animation<double> _expandAnim;

  // Organized analysis types by category
  static const List<List<SpatialAnalysisType>> _analysisCategories = [
    // Row 1: Temporal & Vegetation
    [
      SpatialAnalysisType.changeDetection,
      SpatialAnalysisType.vegetationIndex,
    ],
    // Row 2: Spatial Geometry
    [
      SpatialAnalysisType.bufferAnalysis,
      SpatialAnalysisType.proximityAnalysis,
    ],
    // Row 3: Statistical Analysis
    [
      SpatialAnalysisType.hotspotAnalysis,
      SpatialAnalysisType.patternAnalysis,
    ],
    // Row 4: Prediction & Fragmentation
    [
      SpatialAnalysisType.predictiveRiskMap,
      SpatialAnalysisType.fragmentationAnalysis,
    ],
    // Row 5: Risk Modeling
    [
      SpatialAnalysisType.riskModeling,
    ],
  ];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _expandAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _animController.value = 1.0; // Start expanded
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _toggleExpand() {
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
    return Positioned(
      top: MediaQuery.of(context).padding.top + 70,
      right: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Header bar
          _buildHeader(),

          // Expandable content
          SizeTransition(
            sizeFactor: _expandAnim,
            axisAlignment: -1,
            child: FadeTransition(
              opacity: _expandAnim,
              child: _buildContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return GestureDetector(
      onTap: _toggleExpand,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(230),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(_isExpanded ? 0 : 12),
            bottomRight: Radius.circular(_isExpanded ? 0 : 12),
          ),
          border: Border.all(
            color: EcoTheme.electricCyan.withAlpha(128),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.analytics,
              color: EcoTheme.electricCyan,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              'SPATIAL ANALYSIS',
              style: GoogleFonts.orbitron(
                color: EcoTheme.electricCyan,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(width: 8),
            if (widget.isAnalyzing)
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: EcoTheme.electricCyan,
                ),
              )
            else
              Icon(
                _isExpanded ? Icons.expand_less : Icons.expand_more,
                color: Colors.white54,
                size: 18,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(230),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
          topLeft: Radius.circular(12),
        ),
        border: Border.all(
          color: EcoTheme.electricCyan.withAlpha(76),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Analysis buttons organized by category
          for (final row in _analysisCategories) ...[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final type in row) ...[
                  _buildAnalysisButton(type),
                  if (type != row.last) const SizedBox(width: 6),
                ],
              ],
            ),
            const SizedBox(height: 6),
          ],

          // Clear button if analysis is active
          if (widget.activeAnalysis != null) ...[
            const SizedBox(height: 4),
            Center(
              child: TextButton.icon(
                onPressed: widget.onClose,
                icon: const Icon(Icons.clear, size: 14),
                label: Text(
                  'CLEAR ANALYSIS',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white54,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAnalysisButton(SpatialAnalysisType type) {
    final isActive = widget.activeAnalysis == type;
    final color = type.color;

    return GestureDetector(
      onTap: widget.isAnalyzing ? null : () => widget.onAnalysisSelected(type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 70,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: isActive ? color.withAlpha(51) : Colors.white.withAlpha(13),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? color : Colors.white.withAlpha(26),
            width: isActive ? 1.5 : 0.5,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: color.withAlpha(77),
                    blurRadius: 8,
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              type.icon,
              color: isActive ? color : Colors.white70,
              size: 18,
            ),
            const SizedBox(height: 4),
            Text(
              _getShortName(type),
              style: GoogleFonts.inter(
                color: isActive ? color : Colors.white54,
                fontSize: 8,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  String _getShortName(SpatialAnalysisType type) {
    switch (type) {
      case SpatialAnalysisType.changeDetection:
        return 'CHANGE';
      case SpatialAnalysisType.vegetationIndex:
        return 'NDVI';
      case SpatialAnalysisType.bufferAnalysis:
        return 'BUFFER';
      case SpatialAnalysisType.proximityAnalysis:
        return 'PROXIMITY';
      case SpatialAnalysisType.hotspotAnalysis:
        return 'HOTSPOT';
      case SpatialAnalysisType.patternAnalysis:
        return 'PATTERN';
      case SpatialAnalysisType.riskModeling:
        return 'RISK';
      case SpatialAnalysisType.predictiveRiskMap:
        return 'PREDICT';
      case SpatialAnalysisType.fragmentationAnalysis:
        return 'FRAGMENT';
    }
  }
}

/// Compact version of toolbar for when space is limited
class AnalysisToolbarCompact extends StatelessWidget {
  final Function(SpatialAnalysisType) onAnalysisSelected;
  final SpatialAnalysisType? activeAnalysis;
  final bool isAnalyzing;

  const AnalysisToolbarCompact({
    super.key,
    required this.onAnalysisSelected,
    this.activeAnalysis,
    this.isAnalyzing = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(204),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: EcoTheme.electricCyan.withAlpha(76)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.analytics, color: EcoTheme.electricCyan, size: 16),
          const SizedBox(width: 8),
          for (final type in SpatialAnalysisType.values) ...[
            _buildCompactButton(type),
          ],
        ],
      ),
    );
  }

  Widget _buildCompactButton(SpatialAnalysisType type) {
    final isActive = activeAnalysis == type;
    final color = type.color;

    return GestureDetector(
      onTap: isAnalyzing ? null : () => onAnalysisSelected(type),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: isActive ? color.withAlpha(51) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: isActive ? Border.all(color: color, width: 1) : null,
        ),
        child: Icon(
          type.icon,
          color: isActive ? color : Colors.white54,
          size: 16,
        ),
      ),
    );
  }
}
