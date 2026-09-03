import 'package:flutter/material.dart';
import 'package:ecolens/views/maplibre_map_screen.dart';

/// Adaptive Map Screen — routes every platform to MapLibre.
///
/// Mapbox was removed from EcoLens in the May 2026 hardening pass so
/// we don't ship a third-party access token in the build. MapLibre is
/// fully open-source and uses CartoDB/OSM tiles that don't require
/// per-user auth.
class AdaptiveMapScreen extends StatelessWidget {
  const AdaptiveMapScreen({super.key});

  @override
  Widget build(BuildContext context) => const MapLibreMapScreen();
}
