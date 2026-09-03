import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Professional GIS Basemap Switcher
class GISBasemapSwitcher extends StatefulWidget {
  final String currentStyle;
  final Function(String) onStyleChanged;

  const GISBasemapSwitcher({
    super.key,
    required this.currentStyle,
    required this.onStyleChanged,
  });

  @override
  State<GISBasemapSwitcher> createState() => _GISBasemapSwitcherState();
}

class _GISBasemapSwitcherState extends State<GISBasemapSwitcher> {
  bool _expanded = false;

  final List<Map<String, dynamic>> _basemaps = [
    {
      'name': 'Satellite',
      'style': 'mapbox://styles/mapbox/satellite-streets-v12',
      'icon': Icons.satellite_alt,
      'color': Colors.blue,
    },
    {
      'name': 'Dark',
      'style': 'mapbox://styles/mapbox/dark-v11',
      'icon': Icons.dark_mode,
      'color': Colors.purple,
    },
    {
      'name': 'Streets',
      'style': 'mapbox://styles/mapbox/streets-v12',
      'icon': Icons.map,
      'color': Colors.orange,
    },
    {
      'name': 'Outdoors',
      'style': 'mapbox://styles/mapbox/outdoors-v12',
      'icon': Icons.terrain,
      'color': Colors.green,
    },
  ];

  @override
  Widget build(BuildContext context) {
    final currentBasemap = _basemaps.firstWhere(
      (b) => b['style'] == widget.currentStyle,
      orElse: () => _basemaps[0],
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: _expanded ? 180 : 56,
      height: _expanded ? 220 : 56,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A).withOpacity(0.9),
        borderRadius: BorderRadius.circular(_expanded ? 16 : 28),
        border: Border.all(color: Colors.white12),
        boxShadow: [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: _expanded ? _buildExpanded() : _buildCollapsed(currentBasemap),
    );
  }

  Widget _buildCollapsed(Map<String, dynamic> basemap) {
    return InkWell(
      onTap: () => setState(() => _expanded = true),
      borderRadius: BorderRadius.circular(28),
      child: Center(
        child: Icon(
          basemap['icon'],
          color: basemap['color'],
          size: 24,
        ),
      ),
    );
  }

  Widget _buildExpanded() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        GestureDetector(
          onTap: () => setState(() => _expanded = false),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white12)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.layers, color: Colors.cyan, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'BASEMAP',
                      style: GoogleFonts.orbitron(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const Icon(Icons.close, color: Colors.white54, size: 18),
              ],
            ),
          ),
        ),
        // Basemap options
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: _basemaps.length,
            itemBuilder: (context, index) {
              final basemap = _basemaps[index];
              final isSelected = basemap['style'] == widget.currentStyle;

              return GestureDetector(
                onTap: () {
                  widget.onStyleChanged(basemap['style']);
                  setState(() => _expanded = false);
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? basemap['color'].withOpacity(0.2)
                        : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                          ? basemap['color'].withOpacity(0.5)
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        basemap['icon'],
                        color: isSelected ? basemap['color'] : Colors.white54,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        basemap['name'],
                        style: TextStyle(
                          color: isSelected ? basemap['color'] : Colors.white70,
                          fontSize: 13,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      if (isSelected) ...[
                        const Spacer(),
                        Icon(Icons.check, color: basemap['color'], size: 18),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
