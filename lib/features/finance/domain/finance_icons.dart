import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Набор иконок для категорий. В БД хранится ключ, а не codePoint — так
/// иконки остаются константами и поддерживают tree-shaking.
const Map<String, IconData> financeIcons = {
  'bank': Icons.account_balance_outlined,
  'card': Icons.credit_card_outlined,
  'receipt': Icons.receipt_long_outlined,
  'fastfood': Icons.fastfood_outlined,
  'cart': Icons.shopping_bag_outlined,
  'transport': Icons.directions_bus_outlined,
  'movie': Icons.movie_outlined,
  'health': Icons.favorite_outline,
  'home': Icons.home_outlined,
  'salary': Icons.payments_outlined,
  'gift': Icons.card_giftcard_outlined,
  'pets': Icons.pets_outlined,
  'travel': Icons.flight_outlined,
  'school': Icons.school_outlined,
  'fitness': Icons.fitness_center_outlined,
  'coffee': Icons.local_cafe_outlined,
  'savings': Icons.savings_outlined,
  'wifi': Icons.wifi_outlined,
  'phone': Icons.smartphone_outlined,
  'more': Icons.more_horiz_outlined,
};

const String defaultFinanceIconKey = 'more';

IconData financeIconByKey(String? key) {
  return financeIcons[key] ?? Icons.category_outlined;
}

/// Палитра цветов для пользовательских категорий (в тёмной гамме `AppTheme`).
const List<Color> financeColorPalette = [
  AppTheme.primaryAccent,
  AppTheme.secondaryAccent,
  AppTheme.fireAccent,
  AppTheme.successAccent,
  Color(0xFFFF9F43),
  Color(0xFFFECA57),
  Color(0xFFA29BFE),
  Color(0xFFFD79A8),
  Color(0xFF54A0FF),
  Color(0xFF8B949E),
];

const Color _fallbackColor = Color(0xFF8B949E);

/// Разбор цвета `#AARRGGBB` / `#RRGGBB`.
Color financeColorFromHex(String? hex) {
  if (hex == null) return _fallbackColor;
  var raw = hex.replaceFirst('#', '');
  if (raw.length == 6) raw = 'FF$raw';
  final value = int.tryParse(raw, radix: 16);
  return value == null ? _fallbackColor : Color(value);
}

/// Цвет в виде `#AARRGGBB` для хранения в БД.
String financeColorToHex(Color color) {
  return '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';
}
