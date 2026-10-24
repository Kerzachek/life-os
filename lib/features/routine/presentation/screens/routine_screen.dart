import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/responsive.dart';
import '../providers/routine_provider.dart';
import '../widgets/routine_chart_card.dart';
import '../widgets/routine_item_tile.dart';
import '../widgets/routine_summary_card.dart';

/// Экран «Рутина»: сводка дня, чек-лист и диаграмма продуктивности.
class RoutineScreen extends ConsumerWidget {
  const RoutineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final itemsAsync = ref.watch(routineItemsStreamProvider);

    final intro = <Widget>[
      Row(
        children: [
          Icon(Icons.wb_sunny_outlined, color: colorScheme.primary),
          const SizedBox(width: 10),
          Text(
            'Рутина',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      Text(
        'Базовые ежедневные действия. Отметки снимаются автоматически '
        'в 00:00, итог дня попадает в историю.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 20),
      const RoutineSummaryCard(),
    ];

    final checklist = itemsAsync.when(
      data: (items) {
        if (items.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(
              children: [
                Icon(
                  Icons.checklist_rtl_rounded,
                  size: 48,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 12),
                Text(
                  'Рутина пока пуста',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Добавьте базовые действия: зарядка, вода, '
                  'прогулка, сон до 23:00…',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          );
        }
        return ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: items.length,
          onReorderItem: (oldIndex, newIndex) {
            final ids = [for (final i in items) i.id];
            ids.insert(newIndex, ids.removeAt(oldIndex));
            ref.read(routineControllerProvider).reorder(ids);
          },
          itemBuilder: (context, index) {
            final item = items[index];
            return Padding(
              key: ValueKey(item.id),
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  ReorderableDragStartListener(
                    index: index,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(
                        Icons.drag_indicator,
                        size: 18,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(child: RoutineItemTile(item: item)),
                ],
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Text('Ошибка: $err'),
    );

    // Телефон горизонтально: сводка и диаграмма слева, чек-лист справа.
    if (isCompactLandscape(context)) {
      return Scaffold(
        body: LandscapeSplit(
          summary: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ...intro,
              const SizedBox(height: 16),
              const RoutineChartCard(),
            ],
          ),
          list: ListView(
            padding: const EdgeInsets.all(16),
            children: [checklist],
          ),
        ),
      );
    }

    return Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: EdgeInsets.all(isMobileLayout(context) ? 12 : 20),
            children: [
              ...intro,
              const SizedBox(height: 16),
              checklist,
              const SizedBox(height: 16),
              const RoutineChartCard(),
            ],
          ),
        ),
      ),
    );
  }
}
