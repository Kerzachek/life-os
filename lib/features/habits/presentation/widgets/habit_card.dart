import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/responsive.dart';
import '../../domain/habit_appearance.dart';
import '../../domain/habit_with_status.dart';
import '../providers/habits_provider.dart';
import 'add_habit_dialog.dart';
import 'streak_badge.dart';

class HabitCard extends ConsumerWidget {
  final HabitWithStatus item;

  const HabitCard({super.key, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final habit = item.habit;
    final isCompleted = item.isCompletedToday;
    final accent = habitColorFromHex(habit.color) ?? theme.colorScheme.primary;

    final unitText = habit.unit != null && habit.unit!.isNotEmpty
        ? '${habit.targetValue} ${habit.unit}'
        : 'Цель: ${habit.targetValue}';

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isCompleted
              ? accent.withValues(alpha: 0.5)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: isCompleted ? 1.5 : 1,
        ),
      ),
      color: isCompleted
          ? accent.withValues(alpha: 0.12)
          : theme.colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openEditor(context),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(30),
                onTap: () {
                  ref.read(habitsControllerProvider).toggleHabitToday(habit);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isCompleted
                        ? accent
                        : theme.colorScheme.surfaceContainerHigh,
                  ),
                  child: Icon(
                    isCompleted ? Icons.check : habitIconByKey(habit.icon),
                    color: isCompleted ? theme.colorScheme.onPrimary : accent,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      habit.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (habit.description?.isNotEmpty == true) ...[
                      const SizedBox(height: 2),
                      Text(
                        habit.description!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          unitText,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 8),
                        StreakBadge(streakCount: item.streakCount),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                key: ValueKey('habit_edit_${habit.id}'),
                icon: const Icon(Icons.edit_outlined, size: 20),
                tooltip: 'Редактировать',
                color: theme.colorScheme.onSurfaceVariant,
                onPressed: () => _openEditor(context),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                tooltip: 'Удалить',
                color: theme.colorScheme.onSurfaceVariant,
                onPressed: () => _confirmDelete(context, ref),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openEditor(BuildContext context) {
    showFormSheet(
      context: context,
      builder: (_) => AddHabitDialog(habit: item.habit),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить привычку?'),
        content: const Text('Вы действительно хотите удалить эту привычку?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      ref.read(habitsControllerProvider).deleteHabit(item.habit.id);
    }
  }
}
