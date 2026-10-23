import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Набор иконок привычек. В БД хранится ключ, а не codePoint — так иконки
/// остаются константами и поддерживают tree-shaking.
const Map<String, IconData> habitIcons = {
  'fire': Icons.local_fire_department_outlined,
  'fitness': Icons.fitness_center_outlined,
  'run': Icons.directions_run_outlined,
  'water': Icons.water_drop_outlined,
  'book': Icons.menu_book_outlined,
  'sleep': Icons.bedtime_outlined,
  'meditation': Icons.self_improvement_outlined,
  'food': Icons.restaurant_outlined,
  'health': Icons.favorite_outline,
  'pill': Icons.medication_outlined,
  'school': Icons.school_outlined,
  'code': Icons.code_outlined,
  'music': Icons.music_note_outlined,
  'walk': Icons.directions_walk_outlined,
  'sun': Icons.wb_sunny_outlined,
  'savings': Icons.savings_outlined,
  'clean': Icons.cleaning_services_outlined,
  'no_phone': Icons.phonelink_erase_outlined,
};

const String defaultHabitIconKey = 'fire';

IconData habitIconByKey(String? key) {
  return habitIcons[key] ?? habitIcons[defaultHabitIconKey]!;
}

/// Палитра цветов привычек (в тёмной гамме `AppTheme`).
const List<Color> habitColorPalette = [
  AppTheme.primaryAccent,
  AppTheme.secondaryAccent,
  AppTheme.fireAccent,
  AppTheme.successAccent,
  Color(0xFFFF9F43),
  Color(0xFFFECA57),
  Color(0xFFA29BFE),
  Color(0xFFFD79A8),
  Color(0xFF54A0FF),
];

/// Разбор цвета `#AARRGGBB` / `#RRGGBB`; `null`, если цвет не задан.
Color? habitColorFromHex(String? hex) {
  if (hex == null) return null;
  var raw = hex.replaceFirst('#', '');
  if (raw.length == 6) raw = 'FF$raw';
  final value = int.tryParse(raw, radix: 16);
  return value == null ? null : Color(value);
}

/// Цвет в виде `#AARRGGBB` для хранения в БД.
String habitColorToHex(Color color) {
  return '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';
}
