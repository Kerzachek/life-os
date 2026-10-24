import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/routine_day.dart';
import '../providers/routine_provider.dart';

/// Диаграмма продуктивности: процент выполнения рутины по дням
/// за последние 7 / 14 / 30 дней.
class RoutineChartCard extends ConsumerStatefulWidget {
  const RoutineChartCard({super.key});

  static const List<int> periods = [7, 14, 30];

  @override
  ConsumerState<RoutineChartCard> createState() => _RoutineChartCardState();
}

class _RoutineChartCardState extends ConsumerState<RoutineChartCard> {
  int _days = RoutineChartCard.periods.first;

  static Color _barColor(double rate) {
    if (rate >= 0.8) return AppTheme.successAccent;
    if (rate >= 0.5) return AppTheme.secondaryAccent;
    if (rate > 0) return Colors.orange;
    return AppTheme.fireAccent;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final logs = ref.watch(routineLogsStreamProvider).value ?? const [];
    final summary = ref.watch(routineTodaySummaryProvider).value ??
        const RoutineTodaySummary(completed: 0, total: 0);

    final history = buildRoutineHistory(
      logs: logs,
      todayCompleted: summary.completed,
      todayTotal: summary.total,
      now: DateTime.now(),
      days: _days,
    );
    final withData = history.where((d) => d.hasData).toList();
    final average = withData.isEmpty
        ? null
        : withData.fold<double>(0, (s, d) => s + d.rate) / withData.length;
    final dateFormat = DateFormat('dd.MM');
    final labelStep = _days <= 7 ? 1 : (_days <= 14 ? 2 : 5);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Wrap: на телефоне переключатель периода уходит под заголовок,
            // а не выдавливает его за край карточки.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bar_chart_rounded,
                        size: 18, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Продуктивность рутины',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: [
                    for (final p in RoutineChartCard.periods)
                      ButtonSegment(value: p, label: Text('$p дн.')),
                  ],
                  selected: {_days},
                  onSelectionChanged: (v) => setState(() => _days = v.first),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              average == null
                  ? 'Пока нет данных: история появится после первого сброса'
                  : 'В среднем ${(average * 100).round()}% '
                      'за дни с рутиной (${withData.length} из $_days)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  minY: 0,
                  maxY: 100,
                  alignment: BarChartAlignment.spaceAround,
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    horizontalInterval: 25,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: colorScheme.outline,
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                        interval: 25,
                        getTitlesWidget: (value, meta) => SideTitleWidget(
                          meta: meta,
                          child: Text(
                            '${value.toInt()}%',
                            style: TextStyle(
                              fontSize: 10,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          final fromEnd = history.length - 1 - i;
                          if (i < 0 ||
                              i >= history.length ||
                              fromEnd % labelStep != 0) {
                            return const SizedBox.shrink();
                          }
                          return SideTitleWidget(
                            meta: meta,
                            child: Text(
                              fromEnd == 0
                                  ? 'Сегодня'
                                  : dateFormat.format(history[i].day),
                              style: TextStyle(
                                fontSize: 10,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => colorScheme.surfaceContainerHighest,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final stat = history[group.x];
                        final label = stat.hasData
                            ? '${stat.completed} из ${stat.total} '
                                '(${(stat.rate * 100).round()}%)'
                            : 'нет данных';
                        return BarTooltipItem(
                          '${DateFormat('dd.MM.yyyy').format(stat.day)}\n'
                          '$label',
                          TextStyle(color: colorScheme.onSurface, fontSize: 11),
                        );
                      },
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < history.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: history[i].rate * 100,
                            width: _days <= 7 ? 22 : (_days <= 14 ? 14 : 7),
                            color: _barColor(history[i].rate),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                            backDrawRodData: BackgroundBarChartRodData(
                              show: true,
                              toY: 100,
                              color: colorScheme.surfaceContainerHighest,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
