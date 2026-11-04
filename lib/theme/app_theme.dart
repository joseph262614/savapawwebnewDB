import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color primaryOrange = Color(0xFFFF926B);
  static const Color primaryTeal = Color(0xFF4DB6AC);
  static const Color accentOrange = Color(0xFFFFAB91);
  static const Color backgroundWhite = Color(0xFFFAFAFA);

  // Desktop-specific colors
  static const Color sidebarBg = Color(0xFF2D2D3A);
  static const Color sidebarActiveItem = Color(0xFF3D3D4E);
  static const Color cardHoverBorder = Color(0xFFFFCBB8);

  // Standardized Typographic Tokens (Impeccable Hierarchy)
  static const TextStyle pageTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.bold,
    letterSpacing: -0.3,
    color: Colors.black87,
  );

  static const TextStyle sectionTitle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.bold,
    letterSpacing: -0.2,
    color: Colors.black87,
  );

  static const TextStyle dialogTitle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.bold,
    letterSpacing: -0.2,
    color: Colors.black87,
  );

  static const TextStyle tableHeader = TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.6,
    color: Color(0xFF616161),
  );

  static const TextStyle primaryCell = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: Colors.black87,
  );

  static const TextStyle secondaryCell = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.normal,
    color: Color(0xFF616161),
  );

  static const TextStyle caption = TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.normal,
    color: Color(0xFF757575),
  );

  static const TextStyle metricValue = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
    fontFeatures: [FontFeature.tabularFigures()],
    color: Colors.black87,
  );

  static const TextStyle badgeText = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.4,
  );

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryOrange,
        primary: primaryOrange,
        secondary: primaryTeal,
        surface: backgroundWhite,
      ),
      textTheme: GoogleFonts.poppinsTextTheme().copyWith(
        headlineMedium: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: -0.3),
        titleLarge: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: -0.2),
        titleMedium: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.1),
        bodyLarge: const TextStyle(fontSize: 14, height: 1.45),
        bodyMedium: const TextStyle(fontSize: 13, height: 1.4),
        labelLarge: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.2),
        labelSmall: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: Colors.black87),
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        clipBehavior: Clip.antiAlias,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryOrange,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: primaryOrange, width: 2),
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 8,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        width: 400,
      ),
    );
  }
}
