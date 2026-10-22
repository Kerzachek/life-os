import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/responsive.dart';
import '../providers/routine_provider.dart';
import 'routine_item_dialog.dart';

/// Сводка дня: «выполнено X из Y», круговой индикатор и кнопка добавления.
class RoutineSummaryCard extends ConsumerWidget {
  const RoutineSummaryCard({super.key});

  /// Ширина карточки, ниже которой кнопка уходит под текст: в одной строке
  /// с ней текст сжимается до столбика по одной букве.
  static const double stackedBreakpoint = 600;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final summary =
        ref.watch(routineTodaySummaryProvider).value ??
        const RoutineTodaySummary(completed: 0, total: 0);
    final ratio = summary.ratio ?? 0.0;
    final allDone = summary.total > 0 && summary.completed == summary.total;
    final accent = allDone ? AppTheme.successAccent : colorScheme.primary;

    final progress = SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        fit: StackFit.expand,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(end: ratio),
            duration: const Duration(milliseconds: 500),
            builder: (context, value, _) => CircularProgressIndicator(
              value: value,
              strokeWidth: 6,
              backgroundColor: colorScheme.surfaceContainerHighest,
              color: accent,
            ),
          ),
          Center(
            child: Text(
              '${(ratio * 100).round()}%',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: accent,
              ),
            ),
          ),
        ],
      ),
    );

    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Сегодня',
          style: theme.textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Выполнено ${summary.completed} из ${summary.total}',
          softWrap: true,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          allDone
              ? 'Вся рутина на сегодня выполнена'
              : 'Отметки сбрасываются каждый день в 00:00',
          softWrap: true,
          style: theme.textTheme.bodySmall?.copyWith(
            color: allDone ? accent : colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    final addButton = FilledButton.icon(
      onPressed: () => showFormSheet<void>(
        context: context,
        builder: (_) => const RoutineItemDialog(),
      ),
      icon: const Icon(Icons.add),
      label: const Text('Добавить действие'),
    );

    final header = Row(
      children: [
        progress,
        const SizedBox(width: 16),
        Flexible(fit: FlexFit.loose, child: texts),
      ],
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < stackedBreakpoint) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  const SizedBox(height: 16),
                  SizedBox(width: double.infinity, child: addButton),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: header),
                const SizedBox(width: 12),
                addButton,
              ],
            );
          },
        ),
      ),
    );
  }
}
