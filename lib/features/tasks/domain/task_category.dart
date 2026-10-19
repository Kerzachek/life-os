import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Категория задачи. [id] хранится в колонке `tasks.category_id`
/// (и как `categories.id` в БД).
enum TaskCategory {
  work('work', 'Работа', Icons.work_outline, AppTheme.primaryAccent), // Indigo
  personal(
    'personal',
    'Личное',
    Icons.person_outline,
    AppTheme.secondaryAccent, // Cyan
  ),
  home(
    'home',
    'Дом / Быт',
    Icons.home_outlined,
    AppTheme.fireAccent, // Coral
  ),
  health(
    'health',
    'Здоровье',
    Icons.favorite_outline,
    AppTheme.successAccent, // Green
  ),
  finance(
    'finance',
    'Финансы',
    Icons.attach_money_outlined,
    Color(0xFFFF9F43), // Orange
  ),
  other(
    'other',
    'Прочее',
    Icons.more_horiz_outlined,
    Color(0xFF8B949E), // Grey
  );

  /// Категория по умолчанию для новых задач и для неизвестных id.
  static const TaskCategory defaultCategory = TaskCategory.other;

  final String id;
  final String label;
  final IconData icon;
  final Color color;

  const TaskCategory(this.id, this.label, this.icon, this.color);

  /// Цвет в виде `#AARRGGBB` для хранения в таблице `categories`.
  String get colorHex =>
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

  /// Категория по id; `null`/неизвестный id → [defaultCategory].
  static TaskCategory fromId(String? id) {
    return TaskCategory.values.firstWhere(
      (c) => c.id == id,
      orElse: () => defaultCategory,
    );
  }
}
