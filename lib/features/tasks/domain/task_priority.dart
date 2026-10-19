import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

enum TaskPriority {
  low(0, 'Низкий', Color(0xFF8B949E), Icons.arrow_downward_rounded),
  medium(1, 'Средний', AppTheme.primaryAccent, Icons.remove_rounded),
  high(2, 'Высокий', Color(0xFFFF9F43), Icons.priority_high_rounded),
  urgent(3, 'Срочный', Color(0xFFFF4757), Icons.local_fire_department_rounded);

  final int value;
  final String label;
  final Color color;
  final IconData icon;

  const TaskPriority(this.value, this.label, this.color, this.icon);

  static TaskPriority fromValue(int value) {
    return TaskPriority.values.firstWhere(
      (e) => e.value == value,
      orElse: () => TaskPriority.medium,
    );
  }
}

