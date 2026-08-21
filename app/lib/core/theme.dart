import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens — Minimal + Modern Finance (spec 2026-08-21).
abstract final class MoneeColors {
  // Primary accent: teal.
  static const primary = Color(0xFF0F766E); // teal-700 (light theme)
  static const primaryDark = Color(0xFF2DD4BF); // teal-400 (dark theme)

  // Semantic.
  static const accent = Color(0xFF059669); // success / income
  static const destructive = Color(0xFFDC2626); // danger / expense
  static const warning = Color(0xFFD97706);

  // Neutrals (spec token table).
  static const lightBackground = Color(0xFFFFFFFF);
  static const lightSurface = Color(0xFFF8FAFC); // card
  static const lightBorder = Color(0xFFE2E8F0);
  static const lightTextSecondary = Color(0xFF64748B);
  static const darkBackground = Color(0xFF0F172A);
  static const darkSurface = Color(0xFF1E293B); // card
  static const darkBorder = Color(0xFF334155);
  static const darkTextSecondary = Color(0xFF94A3B8);
}

ThemeData moneeTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final primary = dark ? MoneeColors.primaryDark : MoneeColors.primary;
  final scheme = ColorScheme.fromSeed(
    seedColor: MoneeColors.primary,
    brightness: brightness,
    primary: primary,
    error: MoneeColors.destructive,
    surface: dark ? MoneeColors.darkBackground : MoneeColors.lightBackground,
  );

  final text = GoogleFonts.interTextTheme(
    dark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    textTheme: text,
    cardTheme: CardThemeData(
      color: dark ? MoneeColors.darkSurface : MoneeColors.lightSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: dark ? MoneeColors.darkBorder : MoneeColors.lightBorder,
        ),
      ),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      isDense: true,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: primary,
      foregroundColor: dark ? MoneeColors.darkBackground : Colors.white,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? MoneeColors.darkSurface : Colors.white,
      indicatorColor: primary.withValues(alpha: 0.15),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: dark ? MoneeColors.darkSurface : Colors.white,
      indicatorColor: primary.withValues(alpha: 0.15),
      selectedIconTheme: IconThemeData(color: primary),
      selectedLabelTextStyle:
          TextStyle(color: primary, fontWeight: FontWeight.w600, fontSize: 13),
      unselectedLabelTextStyle: const TextStyle(fontSize: 13),
    ),
  );
}

/// Numbers: Inter semibold with tabular figures so columns line up.
TextStyle moneyStyle(BuildContext context,
    {double? size, Color? color, FontWeight? weight}) {
  return GoogleFonts.inter(
    fontSize: size,
    color: color,
    fontWeight: weight ?? FontWeight.w600,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

/// Signature teal gradient (hero cards, primary emphasis) — per the mockups.
const moneeGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
);

/// Spec breakpoint: below this the app uses the mobile pattern
/// (bottom navigation, bottom sheets); at or above it, sidebar + top bar.
const kWideBreakpoint = 768.0;

/// Secondary text color for the current theme.
Color mutedColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? MoneeColors.darkTextSecondary
        : MoneeColors.lightTextSecondary;
