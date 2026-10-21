import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../finance/presentation/widgets/transaction_dialog.dart';
import '../../../habits/presentation/widgets/add_challenge_dialog.dart';
import '../../../habits/presentation/widgets/add_habit_dialog.dart';
import '../../../settings/domain/app_module.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../tasks/presentation/widgets/add_task_dialog.dart';

class _QuickAction {
  final AppModule module;
  final IconData icon;
  final String label;
  final WidgetBuilder dialogBuilder;

  const _QuickAction(this.module, this.icon, this.label, this.dialogBuilder);
}

/// Быстрые действия. Кнопки отключённых разделов скрываются; если не осталось
/// ни одной кнопки, карточка не отображается.
class QuickActionsCard extends ConsumerWidget {
  const QuickActionsCard({super.key});

  static final List<_QuickAction> _actions = [
    _QuickAction(AppModule.tasks, Icons.add_task, '+ Задача',
        (_) => const AddTaskDialog()),
    _QuickAction(AppModule.habits, Icons.local_fire_department, '+ Привычка',
        (_) => const AddHabitDialog()),
    _QuickAction(AppModule.habits, Icons.emoji_events, '+ Челлендж',
        (_) => const AddChallengeDialog()),
    _QuickAction(AppModule.finance, Icons.receipt_long, '+ Операция',
        (_) => const TransactionDialog()),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final enabled = ref.watch(enabledModulesProvider);
    final actions =
        _actions.where((a) => enabled.contains(a.module)).toList();

    if (actions.isEmpty) return const SizedBox.shrink();

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
              for (final action in actions)
                ActionChip(
                  avatar: Icon(action.icon, size: 16),
                  label: Text(action.label),
                  onPressed: () {
                    showDialog(context: context, builder: action.dialogBuilder);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}
