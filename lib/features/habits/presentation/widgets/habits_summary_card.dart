import 'package:flutter/material.dart';
import '../../domain/habit_with_status.dart';

class HabitsSummaryCard extends StatelessWidget {
  final List<HabitWithStatus> habits;

  const HabitsSummaryCard({super.key, required this.habits});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final completedCount = habits.where((h) => h.isCompletedToday).length;
    final totalCount = habits.length;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              Icons.today_outlined,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Прогресс на сегодня',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  '$completedCount из $totalCount выполнено',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
