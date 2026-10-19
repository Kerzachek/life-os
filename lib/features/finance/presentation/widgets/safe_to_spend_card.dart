import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/finance_calculations.dart';
import '../providers/finance_provider.dart';
import 'finance_format.dart';

/// Оранжевый цвет предупреждения: потрачено 70–100% дневной нормы.
const Color safeToSpendWarningColor = Color(0xFFFF9F43);

/// Порог, с которого прогресс-бар становится оранжевым.
const double safeToSpendWarningRatio = 0.7;

/// Цвет прогресс-бара по состоянию бюджета.
Color safeToSpendColor(DailySafeBudgetState state) {
  if (state.isOverspent) return AppTheme.fireAccent;
  if (state.spentRatio >= safeToSpendWarningRatio) {
    return safeToSpendWarningColor;
  }
  return AppTheme.successAccent;
}

/// Карточка «Свободный дневной бюджет»: сколько можно безопасно потратить
/// сегодня. В режиме [compact] (Дашборд) скрывает детализацию.
class SafeToSpendCard extends ConsumerWidget {
  const SafeToSpendCard({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budget = ref.watch(dailySafeBudgetProvider);
    return budget.when(
      data: (s) => SafeToSpendContent(state: s, compact: compact),
      loading: () => const Card(
        child: SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Ошибка: $e'),
        ),
      ),
    );
  }
}

/// Представление карточки для готового [DailySafeBudgetState].
class SafeToSpendContent extends StatelessWidget {
  const SafeToSpendContent({
    super.key,
    required this.state,
    this.compact = false,
  });

  final DailySafeBudgetState state;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final color = safeToSpendColor(state);

    return Card(
      key: const ValueKey('safe_to_spend_card'),
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.shield_outlined, size: 18, color: color),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Доступно сегодня',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                formatMoney(state.remainingToday),
                key: const ValueKey('safe_remaining_today'),
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'из нормы ${formatMoney(state.dailyAllowance)} / день',
              key: const ValueKey('safe_daily_allowance'),
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                key: const ValueKey('safe_progress'),
                value: state.spentRatio.clamp(0.0, 1.0),
                minHeight: 8,
                color: color,
                backgroundColor: AppTheme.darkBorder,
              ),
            ),
            if (state.isOverspent) ...[
              const SizedBox(height: 10),
              Container(
                key: const ValueKey('safe_overspent_banner'),
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.fireAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppTheme.fireAccent.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  'Перерасход за сегодня: '
                  '${formatMoney(-state.remainingToday)} '
                  '(завтра лимит пересчитается автоматически)',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppTheme.fireAccent),
                ),
              ),
            ],
            if (!compact) ...[
              const SizedBox(height: 12),
              Text(
                'Свободно до конца месяца: '
                '${formatMoney(state.freePoolTotal)}',
                key: const ValueKey('safe_free_pool'),
                style: theme.textTheme.labelSmall?.copyWith(color: muted),
              ),
              const SizedBox(height: 2),
              Text(
                'Зарезервировано под обязательные платежи: '
                '${formatMoney(state.unpaidObligations)}',
                key: const ValueKey('safe_reserved'),
                style: theme.textTheme.labelSmall?.copyWith(color: muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
