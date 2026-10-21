import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Компактный бейдж напоминания в карточке задачи. Сработавшее или
/// просроченное напоминание ([isActive] == false) приглушено.
class ReminderBadge extends StatelessWidget {
  final DateTime reminderAt;
  final bool isActive;

  const ReminderBadge({
    super.key,
    required this.reminderAt,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = isActive
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.5);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isActive
                ? Icons.notifications_outlined
                : Icons.notifications_off_outlined,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            DateFormat('dd.MM HH:mm').format(reminderAt.toLocal()),
            style: TextStyle(
              fontSize: 11,
              color: isActive
                  ? colorScheme.onSurfaceVariant
                  : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}
