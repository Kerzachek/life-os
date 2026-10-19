import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/finance_calculations.dart';
import '../../domain/finance_icons.dart';
import '../providers/finance_provider.dart';
import 'finance_format.dart';

/// Donut-диаграмма расходов по категориям за выбранный месяц.
class ExpensePieChart extends ConsumerWidget {
  const ExpensePieChart({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final month = ref.watch(financeSelectedMonthProvider);
    final breakdown = ref.watch(expenseBreakdownProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Расходы по категориям',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  key: const ValueKey('month_prev'),
                  tooltip: 'Предыдущий месяц',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () =>
                      ref.read(financeSelectedMonthProvider.notifier).shift(-1),
                ),
                Text(formatMonth(month), style: theme.textTheme.labelLarge),
                IconButton(
                  key: const ValueKey('month_next'),
                  tooltip: 'Следующий месяц',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () =>
                      ref.read(financeSelectedMonthProvider.notifier).shift(1),
                ),
              ],
            ),
            const SizedBox(height: 8),
            breakdown.when(
              data: (items) => items.isEmpty
                  ? const _EmptyChart()
                  : _ChartBody(items: items),
              loading: () => const SizedBox(
                height: 180,
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

class _EmptyChart extends StatelessWidget {
  const _EmptyChart();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 140,
      child: Center(
        child: Text(
          'Расходов за этот месяц нет',
          key: const ValueKey('chart_empty'),
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _ChartBody extends StatelessWidget {
  const _ChartBody({required this.items});

  final List<CategoryExpense> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = items.fold(0.0, (s, e) => s + e.amount);

    final chart = SizedBox(
      height: 200,
      width: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 62,
              sections: [
                for (final e in items)
                  PieChartSectionData(
                    value: e.amount,
                    color: financeColorFromHex(e.colorHex),
                    radius: 26,
                    showTitle: false,
                  ),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Всего',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              Text(
                formatMoney(total),
                key: const ValueKey('chart_total'),
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );

    final legend = Column(
      children: [
        for (final e in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: financeColorFromHex(e.colorHex),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(e.name, overflow: TextOverflow.ellipsis),
                ),
                Text(
                  '${(e.amount / total * 100).toStringAsFixed(0)}%',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(width: 10),
                Text(
                  formatMoney(e.amount),
                  style: theme.textTheme.labelLarge,
                ),
              ],
            ),
          ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 520) {
          return Row(
            children: [
              chart,
              const SizedBox(width: 24),
              Expanded(child: legend),
            ],
          );
        }
        return Column(children: [chart, const SizedBox(height: 12), legend]);
      },
    );
  }
}
