import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../habits/presentation/providers/habits_provider.dart';
import '../../../habits/presentation/widgets/habit_card.dart';

class HabitsOverviewCard extends ConsumerWidget {
  const HabitsOverviewCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final habitsAsync = ref.watch(habitsWithStatusProvider);

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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.local_fire_department_rounded,
                    size: 18,
                    color: Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Привычки и Стрики',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          habitsAsync.when(
            data: (habits) {
              if (habits.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      'Привычек пока нет',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                );
              }

              final displayHabits = habits.take(4).toList();

              return Column(
                children: displayHabits.map((item) {
                  return HabitCard(key: ValueKey(item.habit.id), item: item);
                }).toList(),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Text('Ошибка: $err'),
          ),
        ],
      ),
    );
  }
}
