import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ecolens/model/spatial_analysis_result.dart';

/// Bottom panel showing spatial analysis results
class AnalysisResultsPanel extends StatelessWidget {
  final SpatialAnalysisResult result;
  final VoidCallback onClose;
  final VoidCallback? onExport;
  final VoidCallback? onGenerateMap;

  const AnalysisResultsPanel({
    super.key,
    required this.result,
    required this.onClose,
    this.onExport,
    this.onGenerateMap,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0D1117),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(
            color: result.type.color.withAlpha(128),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: result.type.color.withAlpha(51),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              _buildHeader(),

              // Statistics grid
              _buildStatisticsGrid(),

              // Legend
              if (result.legend.isNotEmpty) _buildLegend(),

              // Processing info
              _buildProcessingInfo(),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: result.type.color.withAlpha(38),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              result.type.icon,
              color: result.type.color,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.type.displayName.toUpperCase(),
                  style: GoogleFonts.orbitron(
                    color: result.type.color,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  '${result.nodeCount} zones analyzed',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (onGenerateMap != null)
            IconButton(
              icon: const Icon(Icons.auto_awesome, size: 20),
              color: Colors.white54,
              onPressed: onGenerateMap,
              tooltip: 'Generate Cartographic Map',
            ),
          if (onExport != null)
            IconButton(
              icon: const Icon(Icons.share, size: 20),
              color: Colors.white54,
              onPressed: onExport,
              tooltip: 'Export',
            ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            color: Colors.white54,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }

  Widget _buildStatisticsGrid() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: result.statistics.map((stat) => _buildStatCard(stat)).toList(),
      ),
    );
  }

  Widget _buildStatCard(AnalysisStatistic stat) {
    return Container(
      constraints: const BoxConstraints(minWidth: 90, maxWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: (stat.color ?? Colors.white).withAlpha(20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: (stat.color ?? Colors.white).withAlpha(51),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (stat.icon != null) ...[
                Icon(
                  stat.icon,
                  color: stat.color ?? Colors.white70,
                  size: 12,
                ),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  stat.label.toUpperCase(),
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 8,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                stat.value,
                style: GoogleFonts.orbitron(
                  color: stat.color ?? Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (stat.unit != null)
                Text(
                  stat.unit!,
                  style: TextStyle(
                    color: (stat.color ?? Colors.white).withAlpha(179),
                    fontSize: 8,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'LEGEND',
            style: GoogleFonts.orbitron(
              color: Colors.white38,
              fontSize: 9,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: result.legend.map((item) => _buildLegendItem(item)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(LegendItem item) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: item.color,
            borderRadius: BorderRadius.circular(3),
            boxShadow: [
              BoxShadow(
                color: item.color.withAlpha(102),
                blurRadius: 4,
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          item.label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Widget _buildProcessingInfo() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.timer_outlined,
            color: Colors.white24,
            size: 12,
          ),
          const SizedBox(width: 4),
          Text(
            'Processed in ${result.processingTime.inMilliseconds}ms',
            style: TextStyle(
              color: Colors.white24,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

/// Dynamic legend widget that can be positioned on the map
class AnalysisLegend extends StatelessWidget {
  final SpatialAnalysisType type;
  final List<LegendItem> items;
  final bool isVisible;

  const AnalysisLegend({
    super.key,
    required this.type,
    required this.items,
    this.isVisible = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!isVisible || items.isEmpty) return const SizedBox.shrink();

    return Positioned(
      bottom: 200,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(217),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: type.color.withAlpha(76),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(type.icon, color: type.color, size: 12),
                const SizedBox(width: 6),
                Text(
                  type.displayName.toUpperCase(),
                  style: GoogleFonts.orbitron(
                    color: type.color,
                    fontSize: 8,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...items.map((item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: item.color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    item.label,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }
}

/// Loading overlay shown during analysis
class AnalysisLoadingOverlay extends StatelessWidget {
  final SpatialAnalysisType type;

  const AnalysisLoadingOverlay({
    super.key,
    required this.type,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withAlpha(128),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1117),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: type.color.withAlpha(128)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    color: type.color,
                    strokeWidth: 3,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Running ${type.displayName}...',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Analyzing spatial patterns',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
