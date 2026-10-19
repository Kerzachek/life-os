import 'package:flutter/material.dart';

class AppTheme {
  static const Color darkBackground = Color(0xFF0D1117);
  static const Color darkSurface = Color(0xFF151921);
  static const Color darkSurfaceCard = Color(0xFF1C212B);
  static const Color darkBorder = Color(0xFF2B3245);

  static const Color primaryAccent = Color(0xFF6366F1); // Indigo / Purple
  static const Color secondaryAccent = Color(0xFF00CEC9); // Cyan
  static const Color fireAccent = Color(0xFFFF7675); // Flame / Coral
  static const Color successAccent = Color(0xFF00B894); // Green

  static ThemeData get darkLauncherTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBackground,
      colorScheme: const ColorScheme.dark(
        primary: primaryAccent,
        secondary: secondaryAccent,
        surface: darkSurfaceCard,
        surfaceContainerHighest: darkSurface,
        outline: darkBorder,
        outlineVariant: darkBorder,
        onSurface: Color(0xFFF0F6FC),
        onSurfaceVariant: Color(0xFF8B949E),
      ),
      useMaterial3: true,
      visualDensity: VisualDensity.compact,
      cardTheme: CardThemeData(
        color: darkSurfaceCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: darkBorder, width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: darkBorder, width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: darkBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: Color(0xFFF0F6FC),
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: darkBorder,
        thickness: 1,
      ),
    );
  }
}
