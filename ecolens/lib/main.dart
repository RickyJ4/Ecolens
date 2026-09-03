import 'package:ecolens/core/theme.dart';
import 'package:ecolens/viewmodels/InsightsViewModel.dart';
import 'package:ecolens/viewmodels/community_viewmodel.dart';
import 'package:ecolens/viewmodels/dashboard_viewmodel.dart';
import 'package:ecolens/viewmodels/hazard_viewmodel.dart';
import 'package:ecolens/viewmodels/map_viewmodel.dart';
import 'package:ecolens/viewmodels/map_mode_viewmodel.dart';
import 'package:ecolens/viewmodels/navigation_viewmodel.dart';
import 'package:ecolens/views/main_layout.dart';
import 'package:ecolens/views/maplibre_map_screen.dart';
import 'package:ecolens/views/onboarding_screen.dart';
import 'package:ecolens/views/country_intelligence_screen.dart';
import 'package:ecolens/views/simulation_screen.dart';
import 'package:ecolens/services/onboarding_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'firebase_options.dart';

/// reCAPTCHA v3 site key from Firebase Console → App Check → Apps → Web.
/// NOT a secret — ships in client JS by design. Public site keys are paired
/// with a private secret stored only in Google's servers; the secret never
/// reaches the client.
const String _recaptchaV3SiteKey = '6LdcIP4sAAAAAPH7ro_igXb8j7GudsFgwlmWmnYL';

// --- MAIN ENTRY POINT ---
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Activate App Check so every callable / Firestore request from this
  // client carries a verified attestation token. Without this, anyone with
  // your function URLs could call them from curl/Postman and bill the
  // project — same blast radius as a leaked API key.
  try {
    await FirebaseAppCheck.instance.activate(
      // Web: reCAPTCHA v3 (free, no app install). Wire mobile providers
      // (Play Integrity / App Attest) when those targets ship.
      providerWeb: kIsWeb
          ? ReCaptchaV3Provider(_recaptchaV3SiteKey)
          : null,
    );
  } catch (e) {
    debugPrint('App Check activation failed: $e');
    // App still boots; protected backend calls will start failing but
    // the user sees a useful empty/error state rather than a crash.
  }

  // Check onboarding status before launching
  final hasCompletedOnboarding =
      await OnboardingService.hasCompletedOnboarding();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DashboardViewModel()),
        ChangeNotifierProvider(create: (_) => MapViewModel()),
        ChangeNotifierProvider(create: (_) => CommunityViewModel()),
        ChangeNotifierProvider(create: (_) => InsightsViewModel()),
        ChangeNotifierProvider(create: (_) => MapModeViewModel()),
        ChangeNotifierProvider(create: (_) => NavigationViewModel()),
        ChangeNotifierProvider(create: (_) => HazardViewModel()),
      ],
      child: EcoLensApp(showOnboarding: !hasCompletedOnboarding),
    ),
  );
}

class EcoLensApp extends StatelessWidget {
  final bool showOnboarding;

  const EcoLensApp({super.key, required this.showOnboarding});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EcoLens',
      theme: EcoPaper.theme,
      debugShowCheckedModeBanner: false,
      navigatorObservers: [mapRouteObserver],
      routes: {
        '/map': (context) => const MainLayout(initialIndex: 0),
        '/community': (context) => const MainLayout(initialIndex: 1),
        '/insights': (context) => const MainLayout(initialIndex: 2),
        // The tab is called Environmental News; /insights stays for links
        // already in the wild.
        '/news': (context) => const MainLayout(initialIndex: 2),
        '/onboarding': (context) => const OnboardingScreen(),
        '/hazard-monitor': (context) => const MapLibreMapScreen(),
        '/country': (context) => const CountryIntelligenceScreen(),
        '/simulation': (context) => const SimulationScreen(),
      },
      // Deep links with query params (e.g. /#/insights?place=daylighting-vancouver
      // from the map's story pins) miss the exact-match table above and land
      // here. Parse the path + `place` param and open the right tab scoped.
      onGenerateRoute: (settings) {
        final uri = Uri.tryParse(settings.name ?? '');
        if (uri == null) return null;
        const tabPaths = {
          '/map': 0,
          '/community': 1,
          '/insights': 2,
          '/news': 2,
        };
        final tabIndex = tabPaths[uri.path];
        if (tabIndex == null) return null;
        final placeId = uri.queryParameters['place'];
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => MainLayout(
            initialIndex: tabIndex,
            scopePlaceId: placeId,
          ),
        );
      },
      // Web visitors land straight on the map — onboarding is a mobile-only flow.
      home: (showOnboarding && !kIsWeb)
          ? const OnboardingScreen()
          : const MainLayout(),
    );
  }
}
