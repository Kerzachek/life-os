import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../routine/presentation/providers/routine_provider.dart';
import '../../../routine/presentation/widgets/routine_item_dialog.dart';
import '../../../routine/presentation/widgets/routine_item_tile.dart';

/// Компактный чек-лист рутины на дашборде.
class RoutineOverviewCard extends ConsumerWidget {
  const RoutineOverviewCard({super.key});

  static const String title = 'Рутина на сегодня';

  /// Максимум пунктов в карточке; остальные — на экране «Рутина».
  static const int itemsLimit = 6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final itemsAsync = ref.watch(routineItemsStreamProvider);
    final summary = ref.watch(routineTodaySummaryProvider).value;

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
              const Icon(
                Icons.wb_sunny_outlined,
                size: 18,
                color: Color(0xFFFDCB6E),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              if (summary != null && summary.total > 0)
                Text(
                  '${summary.completed} / ${summary.total}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          itemsAsync.when(
            data: (items) {
              if (items.isEmpty) {
                return Center(
                  child: TextButton.icon(
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => const RoutineItemDialog(),
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('Добавить первое действие'),
                  ),
                );
              }
              final shown = items.take(itemsLimit).toList();
              final hidden = items.length - shown.length;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final item in shown)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: RoutineItemTile(
                        key: ValueKey(item.id),
                        item: item,
                        compact: true,
                      ),
                    ),
                  if (hidden > 0)
                    Text(
                      'Ещё $hidden — в разделе «Рутина»',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
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
