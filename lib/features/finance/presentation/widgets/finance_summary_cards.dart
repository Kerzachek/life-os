import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/finance_calculations.dart';
import '../providers/finance_provider.dart';
import 'finance_format.dart';

/// Четыре карточки сводки: баланс, долги, депозиты, остаток на жизнь.
class FinanceSummaryCards extends ConsumerWidget {
  const FinanceSummaryCards({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(financeSummaryProvider);
    return summary.when(
      data: (s) => _Grid(summary: s),
      loading: () => const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Text('Ошибка: $e'),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.summary});

  final FinanceSummary summary;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _SummaryCard(
        key: const ValueKey('summary_balance'),
        title: 'Общий баланс',
        value: formatMoney(summary.totalBalance),
        icon: Icons.account_balance_wallet_outlined,
        color: AppTheme.primaryAccent,
      ),
      _SummaryCard(
        key: const ValueKey('summary_debt'),
        title: 'Долги / Кредиты',
        value: formatMoney(summary.totalDebt),
        icon: Icons.credit_score_outlined,
        color: AppTheme.fireAccent,
      ),
      _SummaryCard(
        key: const ValueKey('summary_deposits'),
        title: 'Отложено в депозиты',
        value: formatMoney(summary.totalDeposits),
        icon: Icons.savings_outlined,
        color: AppTheme.secondaryAccent,
      ),
      _SummaryCard(
        key: const ValueKey('summary_left'),
        title: 'Осталось на жизнь',
        subtitle: 'после обязательных трат',
        value: formatMoney(summary.leftToLive),
        icon: Icons.local_atm_outlined,
        color: summary.leftToLive < 0
            ? AppTheme.fireAccent
            : AppTheme.successAccent,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Уже 400 в две колонки суммы с валютой ужимаются до нечитаемых.
        final columns = constraints.maxWidth >= 640
            ? 4
            : constraints.maxWidth >= 400
            ? 2
            : 1;
        const gap = 12.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards) SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
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
                  child: Icon(icon, size: 18, color: color),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
