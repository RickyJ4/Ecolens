import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ecolens/core/gis_theme.dart';
import 'package:ecolens/model/cartographic_intelligence_models.dart';
import 'package:ecolens/widgets/quality_score_badge.dart';

/// Full-screen viewer for a generated cartographic map.
///
/// Displays the map image with zoom/pan, quality scores,
/// violations, suggestions, and export/share options.
class MapResultViewer extends StatefulWidget {
  final CartographicMapResult result;

  const MapResultViewer({super.key, required this.result});

  /// Show the viewer as a full-screen route.
  static Future<void> show(
    BuildContext context, {
    required CartographicMapResult result,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MapResultViewer(result: result),
      ),
    );
  }

  @override
  State<MapResultViewer> createState() => _MapResultViewerState();
}

class _MapResultViewerState extends State<MapResultViewer> {
  final TransformationController _transformController = TransformationController();
  bool _showDetails = false;

  Uint8List? get _imageBytes {
    final b64 = widget.result.imageBase64;
    if (b64 != null && b64.isNotEmpty) {
      return base64Decode(b64);
    }
    return null;
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GISTheme.backgroundDark,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          // Map image (expandable)
          Expanded(
            child: _buildMapView(),
          ),

          // Bottom panel with quality + details
          _buildBottomPanel(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: GISTheme.surfaceDark,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: GISTheme.textPrimary),
        onPressed: () => Navigator.pop(context),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cartographic Map',
            style: GISTheme.headingSmall,
          ),
          Text(
            '${widget.result.widthPx}x${widget.result.heightPx} ${widget.result.format.toUpperCase()}',
            style: GISTheme.labelSmall,
          ),
        ],
      ),
      actions: [
        // Reset zoom
        IconButton(
          icon: const Icon(Icons.fit_screen, color: GISTheme.textSecondary, size: 20),
          tooltip: 'Fit to screen',
          onPressed: () => _transformController.value = Matrix4.identity(),
        ),
        // Share/export
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: GISTheme.textSecondary),
          color: GISTheme.surfaceLight,
          onSelected: _handleAction,
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'copy_url',
              child: Row(
                children: [
                  Icon(Icons.link, size: 18, color: GISTheme.textSecondary),
                  SizedBox(width: 8),
                  Text('Copy Image URL'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'copy_quality',
              child: Row(
                children: [
                  Icon(Icons.assessment, size: 18, color: GISTheme.textSecondary),
                  SizedBox(width: 8),
                  Text('Copy Quality Report'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMapView() {
    final bytes = _imageBytes;
    final url = widget.result.imageUrl;

    Widget imageWidget;

    if (bytes != null) {
      imageWidget = Image.memory(
        bytes,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      );
    } else if (url != null && url.isNotEmpty) {
      imageWidget = Image.network(
        url,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return Center(
            child: CircularProgressIndicator(
              value: progress.expectedTotalBytes != null
                  ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                  : null,
              color: GISTheme.accentBlue,
            ),
          );
        },
        errorBuilder: (_, error, __) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.broken_image, color: GISTheme.textTertiary, size: 48),
              const SizedBox(height: 8),
              Text('Failed to load image', style: GISTheme.bodySmall),
              Text(error.toString(), style: GISTheme.labelSmall),
            ],
          ),
        ),
      );
    } else {
      imageWidget = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.image_not_supported, color: GISTheme.textTertiary, size: 48),
            const SizedBox(height: 8),
            Text('No image data available', style: GISTheme.bodySmall),
          ],
        ),
      );
    }

    return InteractiveViewer(
      transformationController: _transformController,
      minScale: 0.5,
      maxScale: 5.0,
      child: Center(child: imageWidget),
    );
  }

  Widget _buildBottomPanel() {
    return Container(
      decoration: BoxDecoration(
        color: GISTheme.surfaceDark,
        border: const Border(top: BorderSide(color: GISTheme.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Quality badge row
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: QualityScoreBadge(
                    report: widget.result.qualityReport,
                    compact: true,
                  ),
                ),
                const SizedBox(width: 8),
                // Projection badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: GISTheme.surfaceLight,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: GISTheme.border),
                  ),
                  child: Text(
                    widget.result.projection.name,
                    style: GISTheme.labelSmall,
                  ),
                ),
                const SizedBox(width: 8),
                // Toggle details
                IconButton(
                  icon: Icon(
                    _showDetails ? Icons.expand_more : Icons.expand_less,
                    color: GISTheme.textSecondary,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _showDetails = !_showDetails),
                ),
              ],
            ),
          ),

          // Expandable details
          if (_showDetails) _buildDetailsPanel(),
        ],
      ),
    );
  }

  Widget _buildDetailsPanel() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 300),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(color: GISTheme.border, height: 16),

            // Attributions
            if (widget.result.attributions.isNotEmpty) ...[
              Text('DATA SOURCES', style: GISTheme.label),
              const SizedBox(height: 4),
              ...widget.result.attributions.map(
                (a) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('  \u2022 ', style: TextStyle(color: GISTheme.textTertiary, fontSize: 11)),
                      Expanded(
                        child: Text(a, style: GISTheme.labelSmall),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Suggestions
            if (widget.result.suggestions.isNotEmpty) ...[
              Text('SUGGESTIONS', style: GISTheme.label),
              const SizedBox(height: 4),
              ...widget.result.suggestions.map(
                (s) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        s.startsWith('CRITICAL')
                            ? Icons.error
                            : s.startsWith('Fix')
                                ? Icons.warning_amber
                                : Icons.lightbulb_outline,
                        size: 14,
                        color: s.startsWith('CRITICAL')
                            ? GISTheme.accentRed
                            : s.startsWith('Fix')
                                ? GISTheme.accentOrange
                                : GISTheme.accentYellow,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(s, style: GISTheme.bodySmall),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Violations
            if (widget.result.violations.isNotEmpty) ...[
              Text(
                'VIOLATIONS (${widget.result.violations.length})',
                style: GISTheme.label,
              ),
              const SizedBox(height: 4),
              ...widget.result.violations.map(
                (v) => Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _severityColor(v.severity).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: _severityColor(v.severity).withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        v.ruleId,
                        style: GISTheme.code.copyWith(
                          fontSize: 10,
                          color: _severityColor(v.severity),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(v.message, style: GISTheme.labelSmall),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // Projection details
            Text('PROJECTION', style: GISTheme.label),
            const SizedBox(height: 4),
            Text(widget.result.projection.rationale, style: GISTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              widget.result.projection.distortionNote,
              style: GISTheme.labelSmall.copyWith(fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }

  Color _severityColor(String severity) {
    switch (severity) {
      case 'critical':
        return GISTheme.accentRed;
      case 'error':
        return GISTheme.accentOrange;
      case 'warning':
        return GISTheme.accentYellow;
      default:
        return GISTheme.accentBlue;
    }
  }

  void _handleAction(String action) {
    switch (action) {
      case 'copy_url':
        final url = widget.result.imageUrl;
        if (url != null) {
          Clipboard.setData(ClipboardData(text: url));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Image URL copied to clipboard')),
          );
        }
        break;
      case 'copy_quality':
        final report = widget.result.qualityReport;
        final text = 'Quality: ${report.overallScore}/100 '
            '(${report.passed ? "PASSED" : "FAILED"})\n'
            'Dimensions: ${report.dimensions.entries.map((e) => "${e.key}: ${e.value}").join(", ")}';
        Clipboard.setData(ClipboardData(text: text));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Quality report copied to clipboard')),
        );
        break;
    }
  }
}
