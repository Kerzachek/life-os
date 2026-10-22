import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import 'finance_format.dart';
import 'safe_to_spend_card.dart';

/// Доля использованного лимита, с которой индикатор становится оранжевым.
const double creditLimitWarningRatio = 0.7;

/// Доступный лимит кредитной карты крупным шрифтом, под ним — долг и лимит
/// и полоса заполненности долга.
class CreditLimitIndicator extends StatelessWidget {
  const CreditLimitIndicator({
    super.key,
    required this.limit,
    required this.debt,
  });

  final double limit;
  final double debt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final double available = (limit - debt).clamp(0.0, math.max(0.0, limit));
    final ratio = limit <= 0 ? 0.0 : (debt / limit).clamp(0.0, 1.0);
    final color = ratio >= 1
        ? AppTheme.fireAccent
        : ratio >= creditLimitWarningRatio
        ? safeToSpendWarningColor
        : AppTheme.successAccent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            '${formatMoney(available)} доступно',
            key: const ValueKey('credit_available'),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Долг: ${formatMoney(math.max(0.0, debt))} '
          'из ${formatMoney(limit)} лимита',
          key: const ValueKey('credit_debt'),
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 6,
            color: color,
            backgroundColor: AppTheme.darkBorder,
          ),
        ),
      ],
    );
  }
}
