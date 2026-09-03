import 'package:flutter/material.dart';

import 'package:ecolens/core/gis_theme.dart';
import 'package:ecolens/model/cartographic_intelligence_models.dart';
import 'package:ecolens/services/cartographic_intelligence_service.dart';
import 'package:ecolens/widgets/map_result_viewer.dart';

/// Standalone full-screen page for generating a cartographic map.
/// Works on web (no iframe issues) because it's a full Navigator route.
class GenerateMapScreen extends StatefulWidget {
  const GenerateMapScreen({super.key});

  @override
  State<GenerateMapScreen> createState() => _GenerateMapScreenState();
}

class _GenerateMapScreenState extends State<GenerateMapScreen> {
  final _service = CartographicIntelligenceService();
  bool _isGenerating = false;
  String? _error;
  CartographicMapResult? _result;

  // Default to Mindanao (earthquake hotspot) for demo
  List<double> _bbox = [122.0, 5.0, 127.5, 10.5];
  String _theme = 'earthquake';
  String _title = 'Seismic Risk Assessment';

  final _presets = [
    {'name': 'Mindanao Earthquakes', 'bbox': [122.0, 5.0, 127.5, 10.5], 'theme': 'earthquake', 'title': 'Mindanao — Seismic Risk Assessment'},
    {'name': 'Sumatra Earthquakes', 'bbox': [95.0, -6.0, 106.0, 6.0], 'theme': 'earthquake', 'title': 'Sumatra — Sunda Megathrust Risk'},
    {'name': 'Japan Earthquakes', 'bbox': [128.0, 30.0, 146.0, 46.0], 'theme': 'earthquake', 'title': 'Japan — Seismic Hazard Profile'},
    {'name': 'Caribbean Earthquakes', 'bbox': [-85.0, 10.0, -60.0, 25.0], 'theme': 'earthquake', 'title': 'Caribbean — Seismic Risk'},
    {'name': 'Chile Earthquakes', 'bbox': [-76.0, -45.0, -66.0, -17.0], 'theme': 'earthquake', 'title': 'Chile — Subduction Zone Risk'},
  ];

  @override
  Widget build(BuildContext context) {
    if (_result != null) {
      return MapResultViewer(result: _result!);
    }

    return Scaffold(
      backgroundColor: GISTheme.backgroundDark,
      appBar: AppBar(
        backgroundColor: GISTheme.surfaceDark,
        title: Text('Generate Cartographic Map', style: GISTheme.headingMedium),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: GISTheme.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _isGenerating ? _buildLoading() : _buildForm(),
      ),
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Select a region to generate a risk assessment map.',
            style: GISTheme.bodyLarge),
          const SizedBox(height: 8),
          Text('The engine fetches live data, analyses risk zones, and renders with QGIS.',
            style: GISTheme.bodySmall),
          const SizedBox(height: 24),

          if (_error != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: GISTheme.error.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: GISTheme.accentRed.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: GISTheme.accentRed, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: const TextStyle(color: GISTheme.accentRed))),
                ],
              ),
            ),

          // Region presets
          Text('REGION', style: GISTheme.label),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _presets.map((preset) {
              final selected = preset['name'] == _getSelectedPresetName();
              return ChoiceChip(
                label: Text(preset['name'] as String),
                selected: selected,
                onSelected: (_) {
                  setState(() {
                    _bbox = List<double>.from(preset['bbox'] as List);
                    _theme = preset['theme'] as String;
                    _title = preset['title'] as String;
                  });
                },
                selectedColor: GISTheme.accentBlue,
                backgroundColor: GISTheme.surfaceLight,
                labelStyle: TextStyle(
                  color: selected ? Colors.white : GISTheme.textSecondary,
                  fontSize: 13,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                  side: BorderSide(color: selected ? GISTheme.accentBlue : GISTheme.border),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 24),
          Text('Selected: $_title', style: GISTheme.bodyMedium),
          Text('Bbox: ${_bbox[0].toStringAsFixed(1)}°, ${_bbox[1].toStringAsFixed(1)}° → ${_bbox[2].toStringAsFixed(1)}°, ${_bbox[3].toStringAsFixed(1)}°',
            style: GISTheme.bodySmall),

          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _generate,
              icon: const Icon(Icons.auto_awesome, size: 22),
              label: const Text('Generate Risk Map'),
              style: ElevatedButton.styleFrom(
                backgroundColor: GISTheme.accentBlue,
                foregroundColor: Colors.white,
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 60, height: 60,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: GISTheme.accentBlue,
            ),
          ),
          const SizedBox(height: 24),
          Text('Generating Map...', style: GISTheme.headingMedium),
          const SizedBox(height: 8),
          Text(
            'Fetching earthquake data from USGS\n'
            'Computing seismic risk surface\n'
            'Downloading elevation data (SRTM)\n'
            'Rendering with QGIS + Pillow',
            textAlign: TextAlign.center,
            style: GISTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  String _getSelectedPresetName() {
    for (final p in _presets) {
      final pb = List<double>.from(p['bbox'] as List);
      if (pb[0] == _bbox[0] && pb[1] == _bbox[1]) return p['name'] as String;
    }
    return '';
  }

  Future<void> _generate() async {
    setState(() { _isGenerating = true; _error = null; });

    try {
      final result = await _service.generateMap(
        CartographicMapRequest(
          bbox: _bbox,
          mapType: 'proportional_symbol',
          theme: _theme,
          title: _title,
          subtitle: 'Generated by EcoLens Cartographic Intelligence Engine | USGS 2020-2025',
          valueField: 'mag',
          nClasses: 5,
          darkMode: true,
          showLabels: true,
          showScaleBar: true,
          outputDpi: 200,
          widthInches: 14,
          heightInches: 10,
          dateRange: const ['2020-01-01', '2025-04-01'],
        ),
      );

      if (!mounted) return;
      setState(() { _result = result; _isGenerating = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isGenerating = false;
        _error = _service.getErrorMessage(e);
      });
    }
  }
}
