import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ecolens/core/theme.dart';

class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key});

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  final PageController _controller = PageController();
  int _currentPage = 0;

  final List<Map<String, dynamic>> _pages = [
    {
      "title": "EcoLens Platform",
      "description":
          "Professional-grade GIS intelligence for environmental monitoring. Access real-time satellite data, 3D terrain visualization, and AI-powered risk analysis.",
      "icon": Icons.public,
      "color": EcoTheme.cyan,
      "features": ["NASA/ESA Data", "Global Coverage", "Real-Time Alerts"],
    },
    {
      "title": "Command Dashboard",
      "description":
          "Your mission control for environmental action. Monitor critical metrics including deforestation rates, carbon emissions, population impact, and restoration progress.",
      "icon": Icons.dashboard_customize,
      "color": EcoTheme.neonEmerald,
      "features": ["Live Metrics", "Risk Scoring", "Trend Analysis"],
    },
    {
      "title": "3D Satellite Map",
      "description":
          "Explore terrain with Mapbox 3D visualization. Zoom from global to local scale with dynamic layer transitions. View hotspots with risk-colored markers and detailed forensic data.",
      "icon": Icons.satellite_alt,
      "color": Colors.orangeAccent,
      "features": ["3D Terrain", "Multi-Layer GIS", "Dynamic Zoom"],
    },
    {
      "title": "Augmented Reality",
      "description":
          "Visualize environmental data in AR. Point your camera at any location to see projected deforestation, restoration timelines, and species impact overlays.",
      "icon": Icons.view_in_ar,
      "color": Colors.blueAccent,
      "features": ["AR Overlays", "Time Projection", "Species Data"],
    },
    {
      "title": "AI Insights Engine",
      "description":
          "Machine learning models analyze patterns across 10+ years of satellite imagery. Get predictions on risk trajectory, optimal restoration sites, and carbon credit potential.",
      "icon": Icons.auto_graph,
      "color": Colors.purpleAccent,
      "features": ["ML Predictions", "Trend Forecasts", "Carbon Analysis"],
    },
    {
      "title": "Professional Tools",
      "description":
          "Access spatial analysis tools, restoration predictors, and carbon calculators. Export data for reports or integrate with your existing GIS workflows.",
      "icon": Icons.build_circle,
      "color": EcoTheme.softWhite,
      "features": ["Spatial Analysis", "Calculators", "Data Export"],
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EcoTheme.background,
      body: Stack(
        children: [
          // Background Gradient
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [const Color(0xFF0A0F14), const Color(0xFF050505)],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Header (Skip)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 20,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (_currentPage < _pages.length - 1)
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            "SKIP",
                            style: GoogleFonts.inter(
                              color: Colors.white54,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // Page Content
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    onPageChanged: (index) =>
                        setState(() => _currentPage = index),
                    itemCount: _pages.length,
                    itemBuilder: (context, index) {
                      final page = _pages[index];
                      final color = page["color"] as Color;
                      final features = page["features"] as List<String>?;
                      return Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(36),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    color.withOpacity(0.2),
                                    color.withOpacity(0.05),
                                  ],
                                ),
                                border: Border.all(
                                  color: color.withOpacity(0.4),
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: color.withOpacity(0.3),
                                    blurRadius: 30,
                                    spreadRadius: 5,
                                  ),
                                ],
                              ),
                              child: Icon(
                                page["icon"] as IconData,
                                size: 72,
                                color: color,
                              ),
                            ),
                            const SizedBox(height: 40),
                            Text(
                              page["title"] as String,
                              style: GoogleFonts.orbitron(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 1,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 20),
                            Text(
                              page["description"] as String,
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                color: Colors.white70,
                                height: 1.6,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            if (features != null) ...[
                              const SizedBox(height: 24),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                alignment: WrapAlignment.center,
                                children: features.map((f) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: color.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: color.withOpacity(0.3),
                                    ),
                                  ),
                                  child: Text(
                                    f,
                                    style: GoogleFonts.inter(
                                      color: color,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                )).toList(),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),

                // Indicators & Controls
                Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    children: [
                      // Dots
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          _pages.length,
                          (index) => AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            height: 8,
                            width: _currentPage == index ? 24 : 8,
                            decoration: BoxDecoration(
                              color: _currentPage == index
                                  ? EcoTheme.neonEmerald
                                  : Colors.white24,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: EcoTheme.neonEmerald,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () {
                            if (_currentPage < _pages.length - 1) {
                              _controller.nextPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            } else {
                              Navigator.pop(context);
                            }
                          },
                          child: Text(
                            _currentPage < _pages.length - 1
                                ? "NEXT"
                                : "GET STARTED",
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
