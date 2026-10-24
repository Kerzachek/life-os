import 'package:flutter/material.dart';

/// Цвета поверхностей одной яркости (тёмной или светлой) палитры.
class PaletteSurfaces {
  const PaletteSurfaces({
    required this.background,
    required this.surface,
    required this.card,
    required this.border,
    required this.onSurface,
    required this.onSurfaceVariant,
  });

  /// Фон экранов.
  final Color background;

  /// Диалоги, поля ввода, подложки.
  final Color surface;

  /// Карточки.
  final Color card;
  final Color border;
  final Color onSurface;
  final Color onSurfaceVariant;
}

/// Цветовые схемы приложения. У каждой есть тёмный и светлый вариант:
/// режим (тёмная / светлая / системная) выбирается отдельно.
enum AppPalette {
  cyberObsidian(
    key: 'cyber_obsidian',
    label: 'Cyber Obsidian',
    naturalBrightness: Brightness.dark,
    primary: Color(0xFF6366F1),
    secondary: Color(0xFF00CEC9),
    dark: PaletteSurfaces(
      background: Color(0xFF0D1117),
      surface: Color(0xFF151921),
      card: Color(0xFF1C212B),
      border: Color(0xFF2B3245),
      onSurface: Color(0xFFF0F6FC),
      onSurfaceVariant: Color(0xFF8B949E),
    ),
    light: PaletteSurfaces(
      background: Color(0xFFF5F6FB),
      surface: Color(0xFFEDEFF7),
      card: Color(0xFFFFFFFF),
      border: Color(0xFFDCE0EC),
      onSurface: Color(0xFF1B1E2B),
      onSurfaceVariant: Color(0xFF5F6577),
    ),
  ),
  midnightBlue(
    key: 'midnight_blue',
    label: 'Midnight Blue',
    naturalBrightness: Brightness.dark,
    primary: Color(0xFF3B82F6),
    secondary: Color(0xFF38BDF8),
    dark: PaletteSurfaces(
      background: Color(0xFF0A1325),
      surface: Color(0xFF0F1B33),
      card: Color(0xFF13223F),
      border: Color(0xFF213659),
      onSurface: Color(0xFFE6EEFF),
      onSurfaceVariant: Color(0xFF8D9DC0),
    ),
    light: PaletteSurfaces(
      background: Color(0xFFF2F6FC),
      surface: Color(0xFFE7EEF9),
      card: Color(0xFFFFFFFF),
      border: Color(0xFFD2DCEF),
      onSurface: Color(0xFF14213D),
      onSurfaceVariant: Color(0xFF56658A),
    ),
  ),
  cleanLight(
    key: 'clean_light',
    label: 'Clean Light',
    naturalBrightness: Brightness.light,
    primary: Color(0xFF2F6FED),
    secondary: Color(0xFF0E9F9A),
    dark: PaletteSurfaces(
      background: Color(0xFF121417),
      surface: Color(0xFF181B20),
      card: Color(0xFF1F2329),
      border: Color(0xFF30353D),
      onSurface: Color(0xFFECEEF1),
      onSurfaceVariant: Color(0xFF9AA1AC),
    ),
    light: PaletteSurfaces(
      background: Color(0xFFF4F5F7),
      surface: Color(0xFFECEEF1),
      card: Color(0xFFFFFFFF),
      border: Color(0xFFD9DCE2),
      onSurface: Color(0xFF1A1D23),
      onSurfaceVariant: Color(0xFF5E6470),
    ),
  ),
  forestEmerald(
    key: 'forest_emerald',
    label: 'Forest Emerald',
    naturalBrightness: Brightness.dark,
    primary: Color(0xFF10B981),
    secondary: Color(0xFF6EE7B7),
    dark: PaletteSurfaces(
      background: Color(0xFF0A1612),
      surface: Color(0xFF0F1F19),
      card: Color(0xFF132820),
      border: Color(0xFF1F3D31),
      onSurface: Color(0xFFE6F4EE),
      onSurfaceVariant: Color(0xFF8BA89C),
    ),
    light: PaletteSurfaces(
      background: Color(0xFFF2F8F5),
      surface: Color(0xFFE5F1EB),
      card: Color(0xFFFFFFFF),
      border: Color(0xFFCDE2D8),
      onSurface: Color(0xFF12261E),
      onSurfaceVariant: Color(0xFF55705F),
    ),
  );

  const AppPalette({
    required this.key,
    required this.label,
    required this.naturalBrightness,
    required this.primary,
    required this.secondary,
    required this.dark,
    required this.light,
  });

  /// Ключ в настройках.
  final String key;
  final String label;

  /// Для какой яркости палитра задумана: при её выборе режим переключается
  /// на эту яркость (если не выбран «Как в системе»).
  final Brightness naturalBrightness;
  final Color primary;
  final Color secondary;
  final PaletteSurfaces dark;
  final PaletteSurfaces light;

  static const AppPalette defaultPalette = AppPalette.cyberObsidian;

  PaletteSurfaces surfaces(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  static AppPalette fromKey(String? key) => AppPalette.values.firstWhere(
    (p) => p.key == key,
    orElse: () => defaultPalette,
  );
}

/// Режим темы в настройках. По умолчанию — тёмная.
enum AppThemeMode {
  dark('dark', 'Тёмная', ThemeMode.dark, Icons.dark_mode_rounded),
  light('light', 'Светлая', ThemeMode.light, Icons.light_mode_rounded),
  system(
    'system',
    'Как в системе',
    ThemeMode.system,
    Icons.brightness_auto_rounded,
  );

  const AppThemeMode(this.key, this.label, this.themeMode, this.icon);

  final String key;
  final String label;
  final ThemeMode themeMode;
  final IconData icon;

  static const AppThemeMode defaultMode = AppThemeMode.dark;

  static AppThemeMode fromKey(String? key) => AppThemeMode.values.firstWhere(
    (m) => m.key == key,
    orElse: () => defaultMode,
  );
}
