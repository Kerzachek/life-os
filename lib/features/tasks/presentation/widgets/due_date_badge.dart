import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class DueDateBadge extends StatelessWidget {
  final DateTime dueDate;
  final bool isOverdue;

  const DueDateBadge({
    super.key,
    required this.dueDate,
    required this.isOverdue,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isOverdue
            ? colorScheme.errorContainer
            : colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.event_outlined,
            size: 12,
            color: isOverdue
                ? colorScheme.onErrorContainer
                : colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            DateFormat('dd.MM.yyyy').format(dueDate.toLocal()),
            style: TextStyle(
              fontSize: 11,
              color: isOverdue
                  ? colorScheme.onErrorContainer
                  : colorScheme.onSurfaceVariant,
              fontWeight: isOverdue ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
