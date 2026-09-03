import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class EcoTheme {
  // --- Updated to Organic Hex Values ---
  static const Color background = Color.fromARGB(
    255,
    19,
    18,
    18,
  ); // Deepest Forest Green (instead of black)
  static const Color forestGreen = Color(0xFF40916C); // Rich Leaf Green
  static const Color cyan = Color(
    0xFFB7E4C7,
  ); // Pale Mint/Sage (softer than neon)
  static const Color electricCyan = Color(0xFF95D5B2); // Soft Spring Growth
  static const Color neonEmerald = Color(0xFF74C69D); // Healthy Grass
  static const Color hazardRed = Color(
    0xFFBC4749,
  ); // Terracotta/Dry Soil (less "glitchy", more "fire/warning")
  static const Color starlight = Color(0xFFF8F9FA); // Bone/Off-white
  static const Color amber = Color(0xFFEE9B00); // Sunset Orange
  static const Color softWhite = Color(0xFFD8E2DC); // Misty Air white
  static const Color cardColor = Color.fromARGB(
    255,
    0,
    0,
    0,
  ); // Mossy Bark green

  // --- Organic Decoration (Softened Glass) ---
  static BoxDecoration glassDecoration = BoxDecoration(
    color: const Color(
      0xFF2D6A4F,
    ).withValues(alpha: 0.3), // Tinted with forest green
    borderRadius: BorderRadius.circular(24), // More rounded, organic corners
    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
  );

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: forestGreen,
      // Switching the default text to Montserrat or Inter for a cleaner, modern look
      textTheme: GoogleFonts.montserratTextTheme(
        ThemeData.dark().textTheme,
      ).apply(bodyColor: softWhite, displayColor: softWhite),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────
/// Paper & Ink — the EcoLens editorial design system.
/// Print-born: warm paper surfaces, ink text, one survey-blue accent.
/// Color belongs to data; chrome stays neutral. Serif = judgment,
/// sans = controls, mono = numbers. Mirrors the map's paper theme
/// (assets/maplibre_map/css/paper-theme.css) token for token.
/// ─────────────────────────────────────────────────────────────────
class EcoPaper {
  // Surfaces
  static const Color paper = Color(0xFFF2EFE4); // page
  static const Color paperRaised = Color(0xFFFBF9F1); // cards
  static const Color paperDeep = Color(0xFFEAE6D6); // wells, insets

  // Ink
  static const Color ink = Color(0xFF232019); // primary text
  static const Color inkSoft = Color(0xFF5B564A); // secondary text
  static const Color inkFaint = Color(0xFF8C8574); // captions, labels
  static const Color rule = Color(0xFFD9D2BF); // hairlines, borders

  // Accent — survey blue is the ONLY UI accent
  static const Color survey = Color(0xFF2B5A73);

  // Data colors — reserved for data, never decoration
  static const Color fire = Color(0xFFC3402B);
  static const Color fireDeep = Color(0xFF8E1B12);
  static const Color okGreen = Color(0xFF3E7A4C);
  static const Color amber = Color(0xFFB07D2B); // caution on paper

  // Typography — serif carries judgment, sans carries controls,
  // mono carries coordinates and figures.
  static TextStyle headline({double size = 22, Color color = ink}) =>
      GoogleFonts.lora(
        fontSize: size,
        fontWeight: FontWeight.w600,
        color: color,
        height: 1.25,
      );

  static TextStyle deck({double size = 14, Color color = inkSoft}) =>
      GoogleFonts.lora(
        fontSize: size,
        fontWeight: FontWeight.w400,
        color: color,
        height: 1.45,
        fontStyle: FontStyle.italic,
      );

  static TextStyle body({double size = 13.5, Color color = ink}) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: FontWeight.w400,
        color: color,
        height: 1.5,
      );

  static TextStyle label({double size = 10, Color color = inkFaint}) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: 1.4,
      );

  static TextStyle data({double size = 13, Color color = ink}) =>
      GoogleFonts.jetBrainsMono(
        fontSize: size,
        fontWeight: FontWeight.w500,
        color: color,
      );

  // Decorations — sharp corners, hairline rules, a hard offset
  // shadow (a print plate, not a floating glass pane).
  static BoxDecoration card = BoxDecoration(
    color: paperRaised,
    borderRadius: BorderRadius.circular(3),
    border: Border.all(color: rule),
    boxShadow: const [
      BoxShadow(color: Color(0x1A232019), offset: Offset(3, 3), blurRadius: 0),
    ],
  );

  static BoxDecoration well = BoxDecoration(
    color: paperDeep,
    borderRadius: BorderRadius.circular(3),
    border: Border.all(color: rule),
  );

  static BoxDecoration flat = BoxDecoration(
    color: paperRaised,
    borderRadius: BorderRadius.circular(3),
    border: Border.all(color: rule),
  );

  /// A thin editorial divider.
  static const Divider hairline =
      Divider(color: rule, height: 1, thickness: 1);

  /// App-wide light theme — the paper standard for every screen.
  static ThemeData get theme {
    final base = ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: paper,
      primaryColor: survey,
      colorScheme: ColorScheme.light(
        primary: survey,
        secondary: survey,
        surface: paperRaised,
        error: fire,
        onPrimary: paperRaised,
        onSurface: ink,
      ),
      dividerColor: rule,
      canvasColor: paper,
      cardColor: paperRaised,
    );
    return base.copyWith(
      textTheme: GoogleFonts.interTextTheme(base.textTheme)
          .apply(bodyColor: ink, displayColor: ink),
      appBarTheme: AppBarTheme(
        backgroundColor: paper,
        foregroundColor: ink,
        elevation: 0,
        centerTitle: true,
        shape: const Border(bottom: BorderSide(color: rule)),
        titleTextStyle: GoogleFonts.lora(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
        iconTheme: const IconThemeData(color: inkSoft),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: paperRaised,
        selectedItemColor: survey,
        unselectedItemColor: inkFaint,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: ink,
        contentTextStyle: GoogleFonts.inter(color: paperRaised, fontSize: 13),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: paperRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(3),
          side: const BorderSide(color: rule),
        ),
      ),
    );
  }
}
