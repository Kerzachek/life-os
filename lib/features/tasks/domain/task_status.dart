import 'package:flutter/material.dart';

enum TaskStatus {
  todo(0, 'К выполнению', Icons.circle_outlined),
  inProgress(1, 'В процессе', Icons.timelapse_rounded),
  completed(2, 'Завершено', Icons.check_circle_rounded),
  cancelled(3, 'Отменено', Icons.cancel_outlined);

  final int value;
  final String label;
  final IconData icon;

  const TaskStatus(this.value, this.label, this.icon);

  static TaskStatus fromValue(int value) {
    return TaskStatus.values.firstWhere(
      (e) => e.value == value,
      orElse: () => TaskStatus.todo,
    );
  }
}
