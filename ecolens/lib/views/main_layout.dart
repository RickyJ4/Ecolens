import 'package:ecolens/core/theme.dart';
import 'package:ecolens/services/places_service.dart';
import 'package:ecolens/viewmodels/dashboard_viewmodel.dart';
import 'package:ecolens/viewmodels/navigation_viewmodel.dart';
import 'package:ecolens/viewmodels/restoration_viewmodel.dart';
import 'package:ecolens/viewmodels/carbon_calculator_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:ecolens/views/adaptive_map_screen.dart';
import 'package:ecolens/views/about.dart';
import 'package:ecolens/views/community_screen.dart';
import 'package:ecolens/views/insights_screen.dart';
import 'package:ecolens/views/settings.dart';
import 'package:ecolens/views/restoration_predictor_screen.dart';
import 'package:ecolens/views/carbon_calculator_screen.dart';
import 'package:ecolens/views/simulation_screen.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class MainLayout extends StatefulWidget {
  final int initialIndex;

  /// When set (deep link `/#/insights?place=<id>` from a map story pin),
  /// the Insights local lens is re-anchored on that documented place.
  final String? scopePlaceId;

  const MainLayout({super.key, this.initialIndex = 0, this.scopePlaceId});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  final List<Widget> _screens = [
    const AdaptiveMapScreen(),
    const CommunityScreen(),
    const InsightsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Schedule the tab update after the build to prevent state errors
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialIndex != 0) {
        Provider.of<NavigationViewModel>(
          context,
          listen: false,
        ).setIndex(widget.initialIndex);
      }
      _applyPlaceScope();
    });
  }

  /// Resolve a `?place=<id>` deep link against the Places spine and anchor
  /// the Insights local lens on that geography.
  Future<void> _applyPlaceScope() async {
    final placeId = widget.scopePlaceId;
    if (placeId == null || placeId.isEmpty) return;
    final place = await PlacesService.byId(placeId);
    if (place == null || !mounted) return;
    context.read<DashboardViewModel>().focusOnPlace(
          id: place.id,
          name: place.name,
          lat: place.lat,
          lng: place.lon,
          dek: place.dek,
          storyUrl: place.storyUrl,
          country: place.country,
        );
  }

  @override
  Widget build(BuildContext context) {
    final navVm = Provider.of<NavigationViewModel>(context);

    // On the Map tab the map's own masthead (ChromeShell in the embedded
    // MapLibre page) carries the brand, omnibox and actions — a second
    // AppBar above it would duplicate all three. Other tabs keep it.
    final bool onMapTab = navVm.selectedIndex == 0;

    return Scaffold(
      backgroundColor: EcoPaper.paper,
      appBar: onMapTab
          ? null
          : AppBar(
              backgroundColor: EcoPaper.paper,
              foregroundColor: EcoPaper.ink,
              elevation: 0,
              centerTitle: true, // Force center alignment for Android/iOS
              shape: const Border(bottom: BorderSide(color: EcoPaper.rule)),
              title: Row(
                mainAxisSize: MainAxisSize.min, // Shrinks row to fit content only
                children: [
                  Text(
                    "EcoLens",
                    style: GoogleFonts.lora(
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                      color: EcoPaper.ink,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.only(left: 10),
                    decoration: const BoxDecoration(
                      border: Border(
                        left: BorderSide(color: EcoPaper.rule),
                      ),
                    ),
                    child: Text(
                      "ENVIRONMENTAL INTELLIGENCE",
                      style: GoogleFonts.inter(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                        color: EcoPaper.inkSoft,
                      ),
                    ),
                  ),
                ],
              ),
            ),
      drawer: _buildDrawer(context), // Pass context for navigation
      // All three tabs stay mounted. Swapping the body widget tore down
      // MapLibreMapScreen on every tab change, which reloaded the map iframe
      // (slow) and raced any pending fly-to against a document still loading.
      // IndexedStack keeps the offstage tabs alive and paints only the
      // selected one; expand sizing hands each tab the full body, exactly
      // the constraints a lone body child received before.
      body: IndexedStack(
        index: navVm.selectedIndex,
        sizing: StackFit.expand,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: EcoPaper.paperRaised,
          border: Border(top: BorderSide(color: EcoPaper.rule)),
        ),
        child: BottomNavigationBar(
          currentIndex: navVm.selectedIndex,
          onTap: (index) => navVm.setIndex(index),
          backgroundColor: Colors.transparent,
          selectedItemColor: EcoPaper.survey,
          unselectedItemColor: EcoPaper.inkFaint,
          selectedLabelStyle:
              GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600),
          unselectedLabelStyle: GoogleFonts.inter(fontSize: 11),
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.map_outlined),
              label: 'Map',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.people_outlined),
              label: 'Community',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.newspaper_outlined),
              label: 'Environmental News',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: EcoPaper.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: EcoPaper.rule),
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 48, 20, 18),
            decoration: const BoxDecoration(
              color: EcoPaper.paperRaised,
              border: Border(bottom: BorderSide(color: EcoPaper.ink)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "EcoLens",
                  style: GoogleFonts.lora(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: EcoPaper.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "ENVIRONMENTAL INTELLIGENCE",
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: EcoPaper.inkSoft,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 20, top: 18, bottom: 4),
            child: Text(
              'PROFESSIONAL TOOLS',
              style: GoogleFonts.inter(
                color: EcoPaper.inkFaint,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
          ),
          _drawerItem(
            context,
            icon: Icons.eco_outlined,
            title: "Restoration Predictor",
            subtitle: "Predict restoration success",
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ChangeNotifierProvider(
                  create: (_) => RestorationViewModel(),
                  child: const RestorationPredictorScreen(),
                ),
              ),
            ),
          ),
          _drawerItem(
            context,
            icon: Icons.account_balance_outlined,
            title: "Carbon Calculator",
            subtitle: "Calculate carbon credit value",
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ChangeNotifierProvider(
                  create: (_) => CarbonCalculatorViewModel(),
                  child: const CarbonCalculatorScreen(),
                ),
              ),
            ),
          ),
          _drawerItem(
            context,
            icon: Icons.science_outlined,
            title: "Hazard Simulation",
            subtitle: "Run what-if scenarios & impact analysis",
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SimulationScreen()),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Divider(color: EcoPaper.rule, height: 1, thickness: 1),
          ),
          _drawerItem(
            context,
            icon: Icons.settings_outlined,
            title: "Settings",
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SettingsScreen()),
            ),
          ),
          _drawerItem(
            context,
            icon: Icons.info_outline,
            title: "About",
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AboutScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _drawerItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: EcoPaper.inkSoft, size: 22),
      title: Text(
        title,
        style: GoogleFonts.inter(
          color: EcoPaper.ink,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              style: GoogleFonts.inter(color: EcoPaper.inkFaint, fontSize: 11),
            ),
      onTap: () {
        Navigator.pop(context); // Close drawer first
        onTap();
      },
    );
  }
}
