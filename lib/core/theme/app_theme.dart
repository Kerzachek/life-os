import 'package:flutter/material.dart';

import 'app_palette.dart';

class AppTheme {
  // Поверхности палитры Cyber Obsidian (тёмная тема по умолчанию). В
  // виджетах вместо них — цвета текущей темы (`colorScheme`).
  static const Color darkBackground = Color(0xFF0D1117);
  static const Color darkSurface = Color(0xFF151921);
  static const Color darkSurfaceCard = Color(0xFF1C212B);
  static const Color darkBorder = Color(0xFF2B3245);

  static const Color primaryAccent = Color(0xFF6366F1); // Indigo / Purple
  static const Color secondaryAccent = Color(0xFF00CEC9); // Cyan
  static const Color fireAccent = Color(0xFFFF7675); // Flame / Coral
  static const Color successAccent = Color(0xFF00B894); // Green
  static const Color adminAccent = Color(0xFFFFB300); // Amber — режим администратора

  /// Тема по умолчанию: Cyber Obsidian, тёмная.
  static ThemeData get darkLauncherTheme =>
      build(AppPalette.defaultPalette, Brightness.dark);

  static Color _onColor(Color color) =>
      ThemeData.estimateBrightnessForColor(color) == Brightness.dark
      ? Colors.white
      : Colors.black;

  /// Тема приложения для палитры [palette] в яркости [brightness].
  static ThemeData build(AppPalette palette, Brightness brightness) {
    final s = palette.surfaces(brightness);
    // Конструкторы, а не copyWith: незаданные контейнеры (FAB, выбранный
    // сегмент) берутся из primary/secondary палитры, а не из цветов
    // Material по умолчанию.
    final scheme = brightness == Brightness.dark
        ? ColorScheme.dark(
            primary: palette.primary,
            onPrimary: _onColor(palette.primary),
            secondary: palette.secondary,
            onSecondary: _onColor(palette.secondary),
            surface: s.card,
            surfaceContainerHighest: s.surface,
            outline: s.border,
            outlineVariant: s.border,
            onSurface: s.onSurface,
            onSurfaceVariant: s.onSurfaceVariant,
          )
        : ColorScheme.light(
            primary: palette.primary,
            onPrimary: _onColor(palette.primary),
            secondary: palette.secondary,
            onSecondary: _onColor(palette.secondary),
            surface: s.card,
            surfaceContainerHighest: s.surface,
            outline: s.border,
            outlineVariant: s.border,
            onSurface: s.onSurface,
            onSurfaceVariant: s.onSurfaceVariant,
          );
    return ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: s.background,
      colorScheme: scheme,
      useMaterial3: true,
      visualDensity: VisualDensity.compact,
      cardTheme: CardThemeData(
        color: s.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: s.border, width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: s.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: s.border, width: 1),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: s.background,
        foregroundColor: s.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: s.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      dividerTheme: DividerThemeData(color: s.border, thickness: 1),
    );
  }
}
