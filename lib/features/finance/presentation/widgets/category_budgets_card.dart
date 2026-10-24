import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/responsive.dart';
import '../../domain/category_budgets.dart';
import '../../domain/finance_icons.dart';
import '../providers/finance_provider.dart';
import 'category_budget_dialog.dart';
import 'finance_format.dart';
import 'safe_to_spend_card.dart';

/// Жёлтый цвет бюджета: потрачено 70–90% лимита.
const Color budgetWarningColor = Color(0xFFFDCB6E);

/// Цвет прогресс-бара бюджета: зелёный → жёлтый → оранжевый → красный.
Color budgetLevelColor(BudgetLevel level) {
  switch (level) {
    case BudgetLevel.ok:
      return AppTheme.successAccent;
    case BudgetLevel.warning:
      return budgetWarningColor;
    case BudgetLevel.critical:
      return safeToSpendWarningColor;
    case BudgetLevel.exceeded:
      return AppTheme.fireAccent;
  }
}

/// Блок «Бюджеты по категориям» за месяц, выбранный в обзоре.
class CategoryBudgetsCard extends ConsumerWidget {
  const CategoryBudgetsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final month = ref.watch(financeSelectedMonthProvider);
    final budgets = ref.watch(categoryBudgetsProvider);

    void openDialog([CategoryBudgetStatus? budget]) {
      showFormSheet<void>(
        context: context,
        builder: (_) => CategoryBudgetDialog(month: month, budget: budget),
      );
    }

    return Card(
      key: const ValueKey('category_budgets_card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Бюджеты по категориям',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        formatMonth(month),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: const ValueKey('add_budget'),
                  tooltip: 'Добавить лимит',
                  icon: const Icon(Icons.add),
                  onPressed: openDialog,
                ),
              ],
            ),
            const SizedBox(height: 8),
            budgets.when(
              data: (items) => items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Лимиты не заданы. Нажмите «+», чтобы ограничить '
                        'траты по категории на месяц.',
                        key: const ValueKey('budgets_empty'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        for (final s in items)
                          _BudgetTile(status: s, onTap: () => openDialog(s)),
                      ],
                    ),
              loading: () => const SizedBox(
                height: 60,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text('Ошибка: $e'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BudgetTile extends StatelessWidget {
  const _BudgetTile({required this.status, required this.onTap});

  final CategoryBudgetStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final color = budgetLevelColor(status.level);
    final category = status.category;
    final categoryColor = financeColorFromHex(category.color);

    return InkWell(
      key: ValueKey('budget_${category.id}'),
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: categoryColor.withValues(alpha: 0.15),
                  child: Icon(
                    financeIconByKey(category.icon),
                    size: 16,
                    color: categoryColor,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    category.name,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
                Text(
                  '${(status.ratio * 100).toStringAsFixed(0)}%',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: status.ratio.clamp(0.0, 1.0),
                minHeight: 8,
                color: color,
                backgroundColor: AppTheme.darkBorder,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Потрачено ${formatMoney(status.spent)} '
                    'из ${formatMoney(status.limit)}',
                    key: ValueKey('budget_spent_${category.id}'),
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ),
                Text(
                  status.level == BudgetLevel.exceeded
                      ? 'Перерасход ${formatMoney(-status.remaining)}'
                      : 'Осталось ${formatMoney(status.remaining)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: status.level == BudgetLevel.exceeded ? color : muted,
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
