import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/finance_analytics.dart';
import '../providers/finance_provider.dart';
import 'finance_format.dart';

const Color _incomeColor = AppTheme.successAccent;
const Color _expenseColor = AppTheme.fireAccent;
const Color _netWorthColor = AppTheme.secondaryAccent;

/// Шаг сетки по оси Y: «круглое» число, дающее около четырёх делений.
double _gridInterval(double span) {
  if (span <= 0) return 1;
  final raw = span / 4;
  final magnitude =
      math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  for (final step in const [1, 2, 2.5, 5, 10]) {
    if (raw <= step * magnitude) return step * magnitude;
  }
  return 10 * magnitude;
}

FlTitlesData _titles({
  required List<DateTime> months,
  required double interval,
  required TextStyle? style,
}) {
  return FlTitlesData(
    topTitles: const AxisTitles(),
    rightTitles: const AxisTitles(),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 52,
        interval: interval,
        getTitlesWidget: (value, meta) => SideTitleWidget(
          meta: meta,
          child: Text(formatMoneyCompact(value), style: style),
        ),
      ),
    ),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 26,
        interval: 1,
        getTitlesWidget: (value, meta) {
          final i = value.round();
          if (i < 0 || i >= months.length || value != i) {
            return const SizedBox.shrink();
          }
          return SideTitleWidget(
            meta: meta,
            child: Text(formatMonthShort(months[i]), style: style),
          );
        },
      ),
    ),
  );
}

FlGridData _grid(double interval, Color lineColor) => FlGridData(
      drawVerticalLine: false,
      horizontalInterval: interval,
      getDrawingHorizontalLine: (_) =>
          FlLine(color: lineColor, strokeWidth: 1),
    );

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              subtitle,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

String _periodLabel(List<DateTime> months) =>
    '${formatMonth(months.first)} — ${formatMonth(months.last)}';

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

/// Столбчатая диаграмма доходов и расходов за [analyticsMonths] месяцев до
/// выбранного.
class MonthlyCashflowChart extends ConsumerWidget {
  const MonthlyCashflowChart({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(monthlyCashflowProvider);
    return data.when(
      data: (items) => _ChartCard(
        key: const ValueKey('cashflow_chart'),
        title: 'Доходы и расходы',
        subtitle: _periodLabel([for (final i in items) i.month]),
        child: items.every((i) => i.income == 0 && i.expense == 0)
            ? const _EmptyAnalytics('Операций за этот период нет')
            : _CashflowBody(items: items),
      ),
      loading: () => const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Text('Ошибка: $e'),
    );
  }
}

class _CashflowBody extends StatelessWidget {
  const _CashflowBody({required this.items});

  final List<MonthlyCashflow> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final axisStyle = theme.textTheme.labelSmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final maxY = items.fold(
      0.0,
      (m, i) => math.max(m, math.max(i.income, i.expense)),
    );
    final interval = _gridInterval(maxY);
    final last = items.last;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 200,
          child: BarChart(
            BarChartData(
              maxY: (maxY / interval).ceil() * interval,
              alignment: BarChartAlignment.spaceAround,
              borderData: FlBorderData(show: false),
              gridData: _grid(interval, Theme.of(context).colorScheme.outline),
              titlesData: _titles(
                months: [for (final i in items) i.month],
                interval: interval,
                style: axisStyle,
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => Theme.of(context).colorScheme.surface,
                  getTooltipItem: (group, _, rod, rodIndex) => BarTooltipItem(
                    '${rodIndex == 0 ? 'Доходы' : 'Расходы'}\n'
                    '${formatMoney(rod.toY)}',
                    TextStyle(color: rod.color, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < items.length; i++)
                  BarChartGroupData(
                    x: i,
                    barsSpace: 4,
                    barRods: [
                      BarChartRodData(
                        toY: items[i].income,
                        color: _incomeColor,
                        width: 10,
                        borderRadius:
                            const BorderRadius.vertical(top: Radius.circular(3)),
                      ),
                      BarChartRodData(
                        toY: items[i].expense,
                        color: _expenseColor,
                        width: 10,
                        borderRadius:
                            const BorderRadius.vertical(top: Radius.circular(3)),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const _LegendDot(color: _incomeColor, label: 'Доходы'),
            const _LegendDot(color: _expenseColor, label: 'Расходы'),
            Text(
              'Итог за ${formatMonth(last.month).toLowerCase()}: '
              '${formatMoney(last.net, withSign: true)}',
              key: const ValueKey('cashflow_net'),
              style: theme.textTheme.labelMedium?.copyWith(
                color: last.net < 0 ? _expenseColor : _incomeColor,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Линейный график чистых активов (счета и депозиты минус долги) на конец
/// каждого из [analyticsMonths] месяцев до выбранного.
class NetWorthChart extends ConsumerWidget {
  const NetWorthChart({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(netWorthHistoryProvider);
    return data.when(
      data: (points) => _ChartCard(
        key: const ValueKey('net_worth_chart'),
        title: 'Чистые активы',
        subtitle: 'Счета и депозиты минус кредиты и кредитки',
        child: _NetWorthBody(points: points),
      ),
      loading: () => const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Text('Ошибка: $e'),
    );
  }
}

class _NetWorthBody extends StatelessWidget {
  const _NetWorthBody({required this.points});

  final List<NetWorthPoint> points;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final axisStyle = theme.textTheme.labelSmall?.copyWith(color: muted);
    final values = [for (final p in points) p.netWorth];
    final minValue = math.min(0.0, values.reduce(math.min));
    final maxValue = math.max(0.0, values.reduce(math.max));
    final interval = _gridInterval(maxValue - minValue);
    final current = points.last;
    final change = current.netWorth - points.first.netWorth;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            Text(
              formatMoney(current.netWorth),
              key: const ValueKey('net_worth_current'),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: current.netWorth < 0 ? _expenseColor : _netWorthColor,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                '${formatMoney(change, withSign: true)} '
                'с ${formatMonth(points.first.month).toLowerCase()}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: change < 0 ? _expenseColor : _incomeColor,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Активы ${formatMoney(current.assets)} · '
          'долги ${formatMoney(current.debt)}',
          style: theme.textTheme.labelSmall?.copyWith(color: muted),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 180,
          child: LineChart(
            LineChartData(
              minY: (minValue / interval).floor() * interval,
              maxY: math.max(interval, (maxValue / interval).ceil() * interval),
              minX: 0,
              maxX: points.length - 1.0,
              borderData: FlBorderData(show: false),
              gridData: _grid(interval, Theme.of(context).colorScheme.outline),
              titlesData: _titles(
                months: [for (final p in points) p.month],
                interval: interval,
                style: axisStyle,
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => Theme.of(context).colorScheme.surface,
                  getTooltipItems: (spots) => [
                    for (final s in spots)
                      LineTooltipItem(
                        '${formatMonth(points[s.x.round()].month)}\n'
                        '${formatMoney(s.y)}',
                        const TextStyle(
                          color: _netWorthColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: [
                    for (var i = 0; i < points.length; i++)
                      FlSpot(i.toDouble(), points[i].netWorth),
                  ],
                  isCurved: true,
                  preventCurveOverShooting: true,
                  color: _netWorthColor,
                  barWidth: 3,
                  dotData: const FlDotData(show: true),
                  belowBarData: BarAreaData(
                    show: true,
                    color: _netWorthColor.withValues(alpha: 0.12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyAnalytics extends StatelessWidget {
  const _EmptyAnalytics(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 120,
      child: Center(
        child: Text(
          text,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
