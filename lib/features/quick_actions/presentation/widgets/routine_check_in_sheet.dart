import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/responsive.dart';
import '../../../routine/domain/routine_day.dart';
import '../../../routine/presentation/providers/routine_provider.dart';
import '../../../routine/presentation/widgets/routine_item_tile.dart';

/// Чек-ин рутины: сегодняшние невыполненные действия, закрываются в один
/// тап. Отмеченные в этом окне пункты остаются в списке (зачёркнутыми),
/// чтобы случайную отметку можно было снять повторным тапом.
class RoutineCheckInSheet extends ConsumerStatefulWidget {
  const RoutineCheckInSheet({super.key});

  @override
  ConsumerState<RoutineCheckInSheet> createState() =>
      _RoutineCheckInSheetState();
}

class _RoutineCheckInSheetState extends ConsumerState<RoutineCheckInSheet> {
  /// Пункты, которые были невыполненными при открытии окна или отмечены
  /// в нём: их и показываем.
  final Set<String> _shownIds = {};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final items = ref.watch(routineItemsStreamProvider).value;
    final now = DateTime.now();

    final Widget body;
    if (items == null) {
      body = const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    } else {
      _shownIds.addAll([
        for (final i in items)
          if (!isRoutineDoneToday(i, now)) i.id,
      ]);
      final shown = items.where((i) => _shownIds.contains(i.id)).toList();
      final done = items.where((i) => isRoutineDoneToday(i, now)).length;

      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            items.isEmpty
                ? 'В рутине пока нет действий'
                : 'Выполнено $done из ${items.length}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          if (items.isNotEmpty && shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.celebration_rounded, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  const Text('Всё на сегодня выполнено'),
                ],
              ),
            ),
          for (final item in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: RoutineItemTile(
                key: ValueKey('check_in_${item.id}'),
                item: item,
                compact: true,
              ),
            ),
        ],
      );
    }

    return AdaptiveFormDialog(
      title: const Text('Чек-ин рутины'),
      content: SizedBox(width: formDialogWidth, child: body),
      actions: [
        FilledButton(
          key: const ValueKey('check_in_done'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Готово'),
        ),
      ],
    );
  }
}
