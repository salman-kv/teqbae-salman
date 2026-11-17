import 'package:flutter/material.dart';

const brandBlue = Color(0xFF1A5FDB);
const brandNavy = Color(0xFF0A2F7A);
const brandSky = Color(0xFF3D8BFF);
const successGreen = Color(0xFF1E9E4A);
const warnAmber = Color(0xFFD98200);
const dangerRed = Color(0xFFD93025);

/// Blue gradient used by the dashboard hero and the page headers.
const brandGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [brandNavy, brandBlue, brandSky],
  stops: [0, 0.55, 1],
);

ThemeData buildTheme(Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: brandBlue, brightness: b)
      .copyWith(primary: brandBlue, onPrimary: Colors.white);
  final dark = b == Brightness.dark;
  final border = dark ? Colors.white12 : const Color(0xFFE3E8F2);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? const Color(0xFF0E1217) : const Color(0xFFF4F6FB),
    appBarTheme: AppBarTheme(
      centerTitle: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      foregroundColor: scheme.onSurface,
      titleTextStyle:
          TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: dark ? const Color(0xFF171D25) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        side: const BorderSide(color: brandBlue),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: BorderSide(color: border),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      elevation: 8,
      backgroundColor: dark ? const Color(0xFF131921) : Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: brandBlue.withValues(alpha: 0.12),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: s.contains(WidgetState.selected) ? brandBlue : Colors.grey,
          )),
      iconTheme: WidgetStateProperty.resolveWith((s) =>
          IconThemeData(color: s.contains(WidgetState.selected) ? brandBlue : Colors.grey)),
    ),
  );
}
