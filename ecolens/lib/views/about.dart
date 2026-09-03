import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ecolens/core/theme.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EcoPaper.paper,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: EcoPaper.ink,
        iconTheme: const IconThemeData(color: EcoPaper.ink),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "ABOUT",
          style: EcoPaper.label(size: 12, color: EcoPaper.inkSoft),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Logo and Version
          Center(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: EcoPaper.paperDeep,
                    shape: BoxShape.circle,
                    border: Border.all(color: EcoPaper.rule),
                  ),
                  child: const Icon(
                    Icons.public,
                    size: 60,
                    color: EcoPaper.survey,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  "EcoLens",
                  style: EcoPaper.headline(size: 30),
                ),
                const SizedBox(height: 6),
                Text(
                  "ENVIRONMENTAL INTELLIGENCE",
                  style: EcoPaper.label(color: EcoPaper.inkFaint),
                ),
                const SizedBox(height: 6),
                Text(
                  "v1.0.4 (Beta)",
                  style: EcoPaper.data(size: 11, color: EcoPaper.inkFaint),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Mission Statement
          _buildSection(
            "OUR MISSION",
            "EcoLens utilizes real-time satellite telemetry and agentic AI to detect, analyze, and forecast environmental degradation events globally. Our mission is to provide actionable intelligence to conservationists, researchers, and organizations worldwide.",
            Icons.eco,
            EcoPaper.survey,
          ),

          const SizedBox(height: 24),

          // Features
          _buildSection(
            "KEY FEATURES",
            null,
            Icons.star,
            EcoPaper.survey,
            features: [
              "🛰️ Real-time satellite monitoring (Sentinel-2, Landsat)",
              "🔥 FIRMS fire detection & alerts",
              "🌳 GFW deforestation tracking",
              "🧠 AI-powered risk prediction",
              "📊 Comprehensive soil, terrain & hydrology analysis",
              "🗺️ Professional GIS visualization",
              "👥 Community reporting & collaboration",
            ],
          ),

          const SizedBox(height: 24),

          // Data Sources
          _buildSection(
            "DATA SOURCES",
            null,
            Icons.storage,
            EcoPaper.survey,
            dataSources: [
              ("Global Forest Watch", "https://globalforestwatch.org"),
              ("NASA FIRMS", "https://firms.modaps.eosdis.nasa.gov"),
              ("Copernicus Sentinel-2", "https://scihub.copernicus.eu"),
              ("USGS Earth Explorer", "https://earthexplorer.usgs.gov"),
              ("SoilGrids", "https://soilgrids.org"),
              ("OpenTopography", "https://opentopography.org"),
            ],
          ),

          const SizedBox(height: 24),

          // Technology Stack
          _buildSection(
            "POWERED BY",
            null,
            Icons.memory,
            EcoPaper.survey,
            techStack: [
              ("Google Gemini AI", "Agentic intelligence & analysis"),
              ("Firebase", "Cloud infrastructure & real-time sync"),
              ("MapLibre + OpenStreetMap", "Open-source mapping & visualization"),
              ("Flutter", "Cross-platform framework"),
            ],
          ),

          const SizedBox(height: 24),

          // Disclaimer — informational-use / no-liability notice for
          // forecasts, simulations, and modelled estimates.
          _buildSection(
            "DISCLAIMER",
            "EcoLens presents environmental data and modelled projections for "
            "informational and educational purposes only. Forecasts, "
            "simulations, risk scores, and restoration or carbon estimates are "
            "approximations derived from third-party datasets and published "
            "scientific methodologies, and carry inherent uncertainty. They are "
            "not guarantees of future conditions and must not be used as the "
            "sole basis for safety, emergency, financial, legal, or "
            "land-management decisions. EcoLens is not a substitute for official "
            "warnings from authorities or for professional advice. All data is "
            "provided \"as is,\" without warranty of any kind.",
            Icons.gavel,
            EcoPaper.survey,
          ),

          const SizedBox(height: 24),

          // Contact
          _buildSection(
            "CONTACT",
            "Have questions, feedback, or want to contribute? We'd love to hear from you!",
            Icons.email,
            EcoPaper.survey,
          ),

          const SizedBox(height: 12),

          // Contact Button
          GestureDetector(
            onTap: () => _launchEmail(),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: EcoPaper.paperRaised,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: EcoPaper.survey),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.email, color: EcoPaper.survey, size: 20),
                  SizedBox(width: 12),
                  Text(
                    "hello@rickyj.io",
                    style: TextStyle(
                      color: EcoPaper.survey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),

          // Footer
          Center(
            child: Column(
              children: [
                Text(
                  "Made with 💚 for our planet",
                  style: EcoPaper.body(size: 12, color: EcoPaper.inkFaint),
                ),
                const SizedBox(height: 8),
                Text(
                  "© 2026 EcoLens. All rights reserved.",
                  style: EcoPaper.body(size: 10, color: EcoPaper.inkFaint),
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSection(
    String title,
    String? description,
    IconData icon,
    Color color, {
    List<String>? features,
    List<(String, String)>? dataSources,
    List<(String, String)>? techStack,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: EcoPaper.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 12),
              Text(
                title,
                style: EcoPaper.label(size: 11, color: EcoPaper.inkSoft),
              ),
            ],
          ),
          if (description != null) ...[
            const SizedBox(height: 12),
            Text(
              description,
              style: EcoPaper.body(color: EcoPaper.inkSoft),
            ),
          ],
          if (features != null) ...[
            const SizedBox(height: 12),
            ...features.map(
              (f) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  f,
                  style: EcoPaper.body(size: 12, color: EcoPaper.inkSoft),
                ),
              ),
            ),
          ],
          if (dataSources != null) ...[
            const SizedBox(height: 12),
            ...dataSources.map(
              (source) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  onTap: () => _launchUrl(source.$2),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.link,
                        color: EcoPaper.inkFaint,
                        size: 14,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        source.$1,
                        style: const TextStyle(
                          color: EcoPaper.survey,
                          fontSize: 12,
                          decoration: TextDecoration.underline,
                          decorationColor: EcoPaper.survey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          if (techStack != null) ...[
            const SizedBox(height: 12),
            ...techStack.map(
              (tech) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Text(
                      tech.$1,
                      style: const TextStyle(
                        color: EcoPaper.ink,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "— ${tech.$2}",
                        style: const TextStyle(
                          color: EcoPaper.inkSoft,
                          fontSize: 11,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _launchEmail() async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'hello@rickyj.io',
      queryParameters: {'subject': 'EcoLens App Inquiry'},
    );
    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri);
    }
  }
}
