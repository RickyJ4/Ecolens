import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Professional GIS Theme for Desktop Web Application
/// Inspired by industry-standard GIS software (QGIS, ArcGIS Pro, etc.)
class GISTheme {
  // Professional Dark GIS Palette
  static const Color backgroundDark = Color(0xFF0D1117); // Deep charcoal
  static const Color surfaceDark = Color(0xFF161B22); // Panel background
  static const Color surfaceLight = Color(0xFF1C2128); // Card background
  static const Color surfaceHover = Color(0xFF21262D); // Hover state

  // Borders and dividers
  static const Color border = Color(0xFF30363D);
  static const Color borderLight = Color(0xFF373E47);
  static const Color divider = Color(0xFF21262D);

  // Text colors
  static const Color textPrimary = Color(0xFFE6EDF3);
  static const Color textSecondary = Color(0xFF7D8590);
  static const Color textTertiary = Color(0xFF6E7681);
  static const Color textLabel = Color(0xFF8B949E);

  // Accent colors (muted, professional)
  static const Color accentBlue = Color(0xFF58A6FF);
  static const Color accentGreen = Color(0xFF56D364);
  static const Color accentOrange = Color(0xFFDB6D28);
  static const Color accentRed = Color(0xFFDA3633);
  static const Color accentYellow = Color(0xFFD29922);
  static const Color accentPurple = Color(0xFFA371F7);

  // Semantic colors
  static const Color success = Color(0xFF238636);
  static const Color warning = Color(0xFF9E6A03);
  static const Color error = Color(0xFFCF222E);
  static const Color info = Color(0xFF0969DA);

  // Data visualization colors (muted, professional)
  static const Color dataViz1 = Color(0xFF3FB950);
  static const Color dataViz2 = Color(0xFF58A6FF);
  static const Color dataViz3 = Color(0xFFBC8CFF);
  static const Color dataViz4 = Color(0xFFD29922);
  static const Color dataViz5 = Color(0xFFFF7B72);

  // Typography
  static TextStyle get headingLarge => GoogleFonts.inter(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: textPrimary,
    letterSpacing: -0.5,
  );

  static TextStyle get headingMedium => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: textPrimary,
    letterSpacing: -0.25,
  );

  static TextStyle get headingSmall => GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: textPrimary,
    letterSpacing: 0,
  );

  static TextStyle get bodyLarge => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: textPrimary,
    height: 1.5,
  );

  static TextStyle get bodyMedium => GoogleFonts.inter(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: textSecondary,
    height: 1.4,
  );

  static TextStyle get bodySmall => GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: textSecondary,
    height: 1.3,
  );

  static TextStyle get label => GoogleFonts.inter(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: textLabel,
    letterSpacing: 0.5,
  );

  static TextStyle get labelSmall => GoogleFonts.inter(
    fontSize: 10,
    fontWeight: FontWeight.w500,
    color: textLabel,
    letterSpacing: 0.5,
  );

  static TextStyle get code => GoogleFonts.jetBrainsMono(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: textPrimary,
  );

  // Compact spacing system
  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 12.0;
  static const double spacingLg = 16.0;
  static const double spacingXl = 24.0;

  // Compact padding for data tables
  static const EdgeInsets tableCellPadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 8,
  );

  static const EdgeInsets panelPadding = EdgeInsets.all(16);
  static const EdgeInsets compactPadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 8,
  );

  // Professional panel decoration
  static BoxDecoration get panelDecoration => BoxDecoration(
    color: surfaceLight,
    border: Border.all(color: border, width: 1),
    borderRadius: BorderRadius.circular(6),
  );

  static BoxDecoration get cardDecoration => BoxDecoration(
    color: surfaceDark,
    border: Border.all(color: border, width: 1),
    borderRadius: BorderRadius.circular(6),
  );

  static BoxDecoration get tableHeaderDecoration => BoxDecoration(
    color: surfaceDark,
    border: Border(
      bottom: BorderSide(color: borderLight, width: 1),
    ),
  );

  static BoxDecoration get tableRowDecoration => BoxDecoration(
    border: Border(
      bottom: BorderSide(color: border, width: 1),
    ),
  );

  static BoxDecoration get hoverDecoration => BoxDecoration(
    color: surfaceHover,
    borderRadius: BorderRadius.circular(4),
  );
}
