import 'dart:convert';
import 'package:flutter/material.dart';

import 'package:ecolens/core/gis_theme.dart';
import 'package:ecolens/model/cartographic_intelligence_models.dart';
import 'package:ecolens/services/cartographic_intelligence_service.dart';
import 'package:ecolens/widgets/map_result_viewer.dart';

/// Bottom sheet dialog for configuring and generating a cartographic map.
///
/// Can be opened from:
/// - Map screen (area/hotspot selected)
/// - Simulation results
/// - Analysis output panels
/// - Intelligence node detail cards
class GenerateMapDialog extends StatefulWidget {
  /// Pre-filled bounding box from the current map view or selection.
  final List<double> bbox;

  /// Pre-filled theme from the current context.
  final String? theme;

  /// Pre-filled title.
  final String? title;

  /// Optional pre-fetched GeoJSON to render.
  final Map<String, dynamic>? geojsonData;

  /// Optional value field for classification.
  final String? valueField;

  /// Optional showcase ID to render directly.
  final String? showcaseId;

  const GenerateMapDialog({
    super.key,
    required this.bbox,
    this.theme,
    this.title,
    this.geojsonData,
    this.valueField,
    this.showcaseId,
  });

  /// Show the dialog as a bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required List<double> bbox,
    String? theme,
    String? title,
    Map<String, dynamic>? geojsonData,
    String? valueField,
    String? showcaseId,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GenerateMapDialog(
        bbox: bbox,
        theme: theme,
        title: title,
        geojsonData: geojsonData,
        valueField: valueField,
        showcaseId: showcaseId,
      ),
    );
  }

  @override
  State<GenerateMapDialog> createState() => _GenerateMapDialogState();
}

class _GenerateMapDialogState extends State<GenerateMapDialog> {
  final _service = CartographicIntelligenceService();

  // Configuration state
  String _mapType = 'choropleth';
  String _classification = 'natural_breaks';
  int _nClasses = 5;
  String? _palette;
  bool _darkMode = false;
  bool _showLabels = true;
  bool _showGrid = true;
  int _dpi = 150;
  String _format = 'png';

  // Generation state
  bool _isGenerating = false;
  String? _error;

  final _mapTypes = const [
    {'id': 'choropleth', 'name': 'Choropleth', 'icon': Icons.map},
    {'id': 'heatmap', 'name': 'Heat Map', 'icon': Icons.whatshot},
    {'id': 'proportional_symbol', 'name': 'Proportional Symbol', 'icon': Icons.bubble_chart},
    {'id': 'dot_density', 'name': 'Dot Density', 'icon': Icons.scatter_plot},
    {'id': 'isopleth', 'name': 'Contour', 'icon': Icons.layers},
    {'id': 'bivariate_choropleth', 'name': 'Bivariate', 'icon': Icons.grid_on},
    {'id': 'multi_hazard_risk', 'name': 'Multi-Hazard', 'icon': Icons.warning_amber},
  ];

  final _palettes = const [
    {'name': 'Auto', 'id': null},
    {'name': 'YlOrRd', 'id': 'YlOrRd'},
    {'name': 'OrRd', 'id': 'OrRd'},
    {'name': 'PuBu', 'id': 'PuBu'},
    {'name': 'YlGn', 'id': 'YlGn'},
    {'name': 'RdBu', 'id': 'RdBu'},
    {'name': 'BrBG', 'id': 'BrBG'},
    {'name': 'Blues', 'id': 'Blues'},
    {'name': 'Greens', 'id': 'Greens'},
  ];

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: GISTheme.surfaceDark,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            border: Border.all(color: GISTheme.border),
          ),
          child: Column(
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

              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    const Icon(Icons.map_outlined, color: GISTheme.accentBlue, size: 22),
                    const SizedBox(width: 8),
                    Text('Generate Cartographic Map', style: GISTheme.headingMedium),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: GISTheme.textTertiary, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              const Divider(color: GISTheme.border, height: 16),

              // Content
              Expanded(
                child: _isGenerating
                    ? _buildGeneratingState()
                    : ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          if (_error != null) _buildError(),
                          _buildMapTypeSelector(),
                          const SizedBox(height: 16),
                          _buildPaletteSelector(),
                          const SizedBox(height: 16),
                          _buildClassificationRow(),
                          const SizedBox(height: 16),
                          _buildToggles(),
                          const SizedBox(height: 16),
                          _buildOutputSettings(),
                          const SizedBox(height: 24),
                          _buildGenerateButton(),
                          const SizedBox(height: 16),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMapTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('MAP TYPE', style: GISTheme.label),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _mapTypes.map((type) {
            final selected = _mapType == type['id'];
            return ChoiceChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(type['icon'] as IconData, size: 16,
                    color: selected ? GISTheme.backgroundDark : GISTheme.textSecondary),
                  const SizedBox(width: 4),
                  Text(type['name'] as String),
                ],
              ),
              selected: selected,
              onSelected: (_) => setState(() => _mapType = type['id'] as String),
              selectedColor: GISTheme.accentBlue,
              backgroundColor: GISTheme.surfaceLight,
              labelStyle: TextStyle(
                color: selected ? GISTheme.backgroundDark : GISTheme.textSecondary,
                fontSize: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: BorderSide(
                  color: selected ? GISTheme.accentBlue : GISTheme.border,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildPaletteSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('COLOR PALETTE', style: GISTheme.label),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _palettes.map((p) {
            final selected = _palette == p['id'];
            return ChoiceChip(
              label: Text(p['name']!),
              selected: selected,
              onSelected: (_) => setState(() => _palette = p['id'] as String?),
              selectedColor: GISTheme.accentBlue,
              backgroundColor: GISTheme.surfaceLight,
              labelStyle: TextStyle(
                color: selected ? GISTheme.backgroundDark : GISTheme.textSecondary,
                fontSize: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: BorderSide(
                  color: selected ? GISTheme.accentBlue : GISTheme.border,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildClassificationRow() {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('CLASSIFICATION', style: GISTheme.label),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: GISTheme.surfaceLight,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: GISTheme.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _classification,
                    isExpanded: true,
                    dropdownColor: GISTheme.surfaceLight,
                    style: GISTheme.bodySmall.copyWith(color: GISTheme.textPrimary),
                    items: const [
                      DropdownMenuItem(value: 'natural_breaks', child: Text('Natural Breaks')),
                      DropdownMenuItem(value: 'quantile', child: Text('Quantile')),
                      DropdownMenuItem(value: 'equal_interval', child: Text('Equal Interval')),
                    ],
                    onChanged: (v) => setState(() => _classification = v!),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('CLASSES: $_nClasses', style: GISTheme.label),
              const SizedBox(height: 6),
              SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: GISTheme.accentBlue,
                  inactiveTrackColor: GISTheme.border,
                  thumbColor: GISTheme.accentBlue,
                  overlayColor: GISTheme.accentBlue.withValues(alpha: 0.2),
                ),
                child: Slider(
                  value: _nClasses.toDouble(),
                  min: 3,
                  max: 9,
                  divisions: 6,
                  onChanged: (v) => setState(() => _nClasses = v.round()),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildToggles() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('OPTIONS', style: GISTheme.label),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            _toggle('Dark Mode', _darkMode, (v) => setState(() => _darkMode = v)),
            _toggle('Labels', _showLabels, (v) => setState(() => _showLabels = v)),
            _toggle('Grid', _showGrid, (v) => setState(() => _showGrid = v)),
          ],
        ),
      ],
    );
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 24,
          width: 36,
          child: Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: GISTheme.accentBlue,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: GISTheme.bodySmall),
      ],
    );
  }

  Widget _buildOutputSettings() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('FORMAT', style: GISTheme.label),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'png', label: Text('PNG')),
                  ButtonSegment(value: 'pdf', label: Text('PDF')),
                  ButtonSegment(value: 'svg', label: Text('SVG')),
                ],
                selected: {_format},
                onSelectionChanged: (v) => setState(() => _format = v.first),
                style: ButtonStyle(
                  textStyle: WidgetStatePropertyAll(GISTheme.labelSmall),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('DPI', style: GISTheme.label),
              const SizedBox(height: 6),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 100, label: Text('100')),
                  ButtonSegment(value: 150, label: Text('150')),
                  ButtonSegment(value: 300, label: Text('300')),
                ],
                selected: {_dpi},
                onSelectionChanged: (v) => setState(() => _dpi = v.first),
                style: ButtonStyle(
                  textStyle: WidgetStatePropertyAll(GISTheme.labelSmall),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGenerateButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: _generate,
        icon: const Icon(Icons.auto_awesome, size: 20),
        label: const Text('Generate Map'),
        style: ElevatedButton.styleFrom(
          backgroundColor: GISTheme.accentBlue,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: GISTheme.headingSmall.copyWith(color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildGeneratingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(GISTheme.accentBlue),
            ),
          ),
          const SizedBox(height: 24),
          Text('Generating Map...', style: GISTheme.headingMedium),
          const SizedBox(height: 8),
          Text(
            'Fetching data, applying cartographic rules,\nand validating quality',
            style: GISTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: GISTheme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: GISTheme.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: GISTheme.accentRed, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error!,
              style: GISTheme.bodySmall.copyWith(color: GISTheme.accentRed),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: GISTheme.textTertiary),
            onPressed: () => setState(() => _error = null),
          ),
        ],
      ),
    );
  }

  Future<void> _generate() async {
    setState(() {
      _isGenerating = true;
      _error = null;
    });

    try {
      final request = CartographicMapRequest(
        bbox: widget.bbox,
        mapType: _mapType,
        theme: widget.theme,
        title: widget.title,
        geojsonData: widget.geojsonData,
        valueField: widget.valueField,
        classificationMethod: _classification,
        nClasses: _nClasses,
        colorPalette: _palette,
        darkMode: _darkMode,
        showLabels: _showLabels,
        showGrid: _showGrid,
        outputFormat: _format,
        outputDpi: _dpi,
        showcaseId: widget.showcaseId,
      );

      final result = await _service.generateMap(request);

      if (!mounted) return;

      // Close dialog and show result viewer
      Navigator.pop(context);
      MapResultViewer.show(context, result: result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isGenerating = false;
        _error = _service.getErrorMessage(e);
      });
    }
  }
}
