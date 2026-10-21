import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../settings/presentation/providers/settings_provider.dart';
import 'life_score_card.dart';
import 'weekly_progress_card.dart';

class OverviewHeader extends ConsumerWidget {
  const OverviewHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final now = DateTime.now();
    // Life Score строится по Задачам и Привычкам — без них он не нужен.
    final showScore =
        WeeklyProgressCard.isVisibleFor(ref.watch(enabledModulesProvider));

    final dateStr = DateFormat('EEEE, dd.MM.yyyy').format(now);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outline),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Добро пожаловать в Life OS',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  dateStr.toUpperCase(),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
          ),
          if (showScore) ...[
            const SizedBox(width: 8),
            const LifeScoreCard(),
          ],
        ],
      ),
    );
  }
}
