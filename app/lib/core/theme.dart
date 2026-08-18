import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens — Data-Dense Dashboard style (ui-ux-pro-max).
abstract final class MoneeColors {
  static const primary = Color(0xFF1E40AF); // trust blue
  static const secondary = Color(0xFF3B82F6);
  static const accent = Color(0xFF059669); // profit green
  static const destructive = Color(0xFFDC2626);
  static const darkBackground = Color(0xFF0F172A);
  static const darkSurface = Color(0xFF101A34);
  static const darkBorder = Color(0x14FFFFFF); // white 8%
  static const lightBackground = Color(0xFFF1F5F9); // slate-100
  static const lightSurface = Colors.white;
  static const lightBorder = Color(0x1F000000); // black 12%
}

ThemeData moneeTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: MoneeColors.primary,
    brightness: brightness,
    primary: dark ? MoneeColors.secondary : MoneeColors.primary,
    error: MoneeColors.destructive,
    // Light mode: slate background so white cards read as elevated surfaces.
    surface: dark ? MoneeColors.darkBackground : MoneeColors.lightBackground,
  );

  final text = GoogleFonts.firaSansTextTheme(
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
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: dark ? MoneeColors.darkBorder : MoneeColors.lightBorder,
        ),
      ),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      isDense: true,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? MoneeColors.darkSurface : MoneeColors.lightSurface,
      indicatorColor: scheme.primary.withValues(alpha: 0.2),
    ),
  );
}

/// Fira Code for figures — tabular, precise.
TextStyle moneyStyle(BuildContext context,
    {double? size, Color? color, FontWeight? weight}) {
  return GoogleFonts.firaCode(
    fontSize: size,
    color: color,
    fontWeight: weight ?? FontWeight.w600,
  );
}
