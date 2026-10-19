import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/life_score.dart';
import '../providers/life_score_provider.dart';

/// Неоновый индикатор Life Score (0–100) для шапки дашборда.
class LifeScoreCard extends ConsumerWidget {
  const LifeScoreCard({super.key});

  /// Цвет акцента в зависимости от балла (палитра [AppTheme]).
  static Color colorForScore(int score) {
    if (score >= 80) return AppTheme.successAccent;
    if (score >= 60) return AppTheme.secondaryAccent;
    if (score >= 40) return Colors.orange;
    return AppTheme.fireAccent;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scoreAsync = ref.watch(lifeScoreProvider);

    return scoreAsync.when(
      data: (life) => _LifeScoreBody(life: life),
      loading: () => const _LifeScoreBody(life: null),
      error: (_, _) => const _LifeScoreBody(life: null),
    );
  }
}

class _LifeScoreBody extends StatelessWidget {
  /// `null` — данные ещё не готовы / недоступны.
  final LifeScore? life;

  const _LifeScoreBody({required this.life});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasValue = life != null && life!.hasData;
    final targetScore = hasValue ? life!.score : 0;
    final accent = hasValue
        ? LifeScoreCard.colorForScore(targetScore)
        : colorScheme.onSurfaceVariant;

    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: accent),
      duration: const Duration(milliseconds: 400),
      builder: (context, animatedAccent, _) {
        final color = animatedAccent ?? accent;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.6)),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.25),
                blurRadius: 14,
                spreadRadius: -2,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bolt, size: 22, color: color),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'LIFE SCORE',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.4,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  hasValue
                      ? _AnimatedScoreText(score: targetScore, color: color)
                      : Text(
                          '— / 100',
                          style: TextStyle(
                            fontSize: 20,
                            height: 1.0,
                            fontWeight: FontWeight.w900,
                            color: color,
                          ),
                        ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Плавный счётчик: при изменении балла число «докручивается» до нового.
class _AnimatedScoreText extends StatelessWidget {
  final int score;
  final Color color;

  const _AnimatedScoreText({required this.score, required this.color});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: score.toDouble()),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: value.round().toString(),
                style: TextStyle(
                  fontSize: 22,
                  height: 1.0,
                  fontWeight: FontWeight.w900,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              TextSpan(
                text: ' / 100',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
