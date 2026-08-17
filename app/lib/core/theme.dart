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
}

ThemeData moneeTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: MoneeColors.primary,
    brightness: brightness,
    primary: dark ? MoneeColors.secondary : MoneeColors.primary,
    error: MoneeColors.destructive,
    surface: dark ? MoneeColors.darkBackground : Colors.white,
  );

  final text = GoogleFonts.firaSansTextTheme(
    dark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    textTheme: text,
    cardTheme: CardTheme(
      color: dark ? MoneeColors.darkSurface : Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: dark ? MoneeColors.darkBorder : Colors.black12,
        ),
      ),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      isDense: true,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? MoneeColors.darkSurface : Colors.white,
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
