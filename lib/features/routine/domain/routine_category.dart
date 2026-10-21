import 'package:flutter/material.dart';

/// Время дня, к которому относится пункт рутины.
enum RoutineCategory {
  general(0, 'Общее', Icons.checklist_rtl_rounded, Color(0xFF8B949E)),
  morning(1, 'Утро', Icons.wb_twilight_rounded, Color(0xFFFDCB6E)),
  day(2, 'День', Icons.wb_sunny_outlined, Color(0xFF00CEC9)),
  evening(3, 'Вечер', Icons.nightlight_round, Color(0xFF6366F1));

  const RoutineCategory(this.value, this.label, this.icon, this.color);

  /// Значение в колонке `routine_items.category`.
  final int value;
  final String label;
  final IconData icon;
  final Color color;

  static RoutineCategory fromValue(int value) {
    return RoutineCategory.values.firstWhere(
      (c) => c.value == value,
      orElse: () => RoutineCategory.general,
    );
  }
}
