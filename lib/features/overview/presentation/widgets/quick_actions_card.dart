import 'package:flutter/material.dart';

import '../../../habits/presentation/widgets/add_challenge_dialog.dart';
import '../../../habits/presentation/widgets/add_habit_dialog.dart';
import '../../../tasks/presentation/widgets/add_task_dialog.dart';

class QuickActionsCard extends StatelessWidget {
  const QuickActionsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flash_on_rounded, size: 18, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Быстрые действия',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                avatar: const Icon(Icons.add_task, size: 16),
                label: const Text('+ Задача'),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => const AddTaskDialog(),
                  );
                },
              ),
              ActionChip(
                avatar: const Icon(Icons.local_fire_department, size: 16),
                label: const Text('+ Привычка'),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => const AddHabitDialog(),
                  );
                },
              ),
              ActionChip(
                avatar: const Icon(Icons.emoji_events, size: 16),
                label: const Text('+ Челлендж'),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => const AddChallengeDialog(),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
