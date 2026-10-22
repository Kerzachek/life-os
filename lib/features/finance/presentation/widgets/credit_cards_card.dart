import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/finance_calculations.dart';
import '../../domain/finance_enums.dart';
import '../providers/finance_provider.dart';
import 'credit_limit_indicator.dart';

/// Карточка обзора с доступным лимитом по каждой кредитной карте (с отступом
/// снизу). Скрыта, если кредиток нет.
class CreditCardsCard extends ConsumerWidget {
  const CreditCardsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = (ref.watch(financeAccountsProvider).value ?? const [])
        .where((a) => a.isCreditCard)
        .toList();
    if (cards.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Card(
      key: const ValueKey('credit_cards_card'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  FinanceAccountKind.creditCard.icon,
                  size: 18,
                  color: AppTheme.fireAccent,
                ),
                const SizedBox(width: 8),
                Text(
                  FinanceAccountKind.creditCard.pluralLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            for (final c in cards) ...[
              const SizedBox(height: 12),
              Text(
                c.name,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              CreditLimitIndicator(limit: c.creditLimit, debt: c.currentDebt),
            ],
          ],
        ),
      ),
    );
  }
}
