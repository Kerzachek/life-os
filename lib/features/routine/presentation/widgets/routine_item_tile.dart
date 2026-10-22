import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/widgets/responsive.dart';
import '../../../finance/presentation/widgets/confirm_dialog.dart';
import '../../domain/routine_category.dart';
import '../../domain/routine_day.dart';
import '../providers/routine_provider.dart';
import 'routine_item_dialog.dart';

/// Строка чек-листа рутины. В [compact]-режиме (дашборд) нет кнопок
/// редактирования и удаления.
class RoutineItemTile extends ConsumerWidget {
  final RoutineItemEntity item;
  final bool compact;

  const RoutineItemTile({super.key, required this.item, this.compact = false});

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await confirmAction(
      context,
      title: 'Удалить действие?',
      message: '«${item.title}» исчезнет из ежедневного чек-листа. '
          'История выполнения сохранится.',
    );
    if (confirmed) await ref.read(routineControllerProvider).deleteItem(item.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final category = RoutineCategory.fromValue(item.category);
    final done = isRoutineDoneToday(item, DateTime.now());

    final tile = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => ref.read(routineControllerProvider).toggle(item),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: 10,
            vertical: compact ? 4 : 6,
          ),
          decoration: BoxDecoration(
            color: done
                ? colorScheme.primary.withValues(alpha: 0.08)
                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: done
                  ? colorScheme.primary.withValues(alpha: 0.35)
                  : colorScheme.outline,
            ),
          ),
          child: Row(
            children: [
              Checkbox(
                value: done,
                onChanged: (_) =>
                    ref.read(routineControllerProvider).toggle(item),
              ),
              Icon(category.icon, size: 16, color: category.color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: done ? colorScheme.onSurfaceVariant : Colors.white,
                    decoration: done ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              if (!compact) ...[
                IconButton(
                  tooltip: 'Редактировать',
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: () => showFormSheet(
                    context: context,
                    builder: (_) => RoutineItemDialog(item: item),
                  ),
                ),
                IconButton(
                  tooltip: 'Удалить',
                  icon: Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: colorScheme.error,
                  ),
                  onPressed: () => _delete(context, ref),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (compact) return tile;

    return Dismissible(
      key: ValueKey('dismiss_${item.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: colorScheme.error.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.delete_outline, color: colorScheme.error),
      ),
      confirmDismiss: (_) async {
        await _delete(context, ref);
        // Строка исчезнет сама после обновления потока из БД.
        return false;
      },
      child: tile,
    );
  }
}
