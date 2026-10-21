import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/widgets/responsive.dart';
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
    // Life Score строится по Задачам, Привычкам и Рутине — без них не нужен.
    final showScore =
        WeeklyProgressCard.isVisibleFor(ref.watch(enabledModulesProvider));
    final mobile = isMobileLayout(context);

    final dateStr = DateFormat('EEEE, dd.MM.yyyy').format(now);

    final greeting = Column(
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
    );

    return Container(
      padding: EdgeInsets.all(mobile ? 16 : 20),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outline),
      ),
      // На телефоне Life Score не помещается рядом с приветствием — под ним.
      child: mobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                greeting,
                if (showScore) ...[
                  const SizedBox(height: 12),
                  const LifeScoreCard(),
                ],
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: greeting),
                if (showScore) ...[
                  const SizedBox(width: 8),
                  const LifeScoreCard(),
                ],
              ],
            ),
    );
  }
}
