import 'package:flutter/material.dart';

/// Пустое состояние Дашборда: все разделы отключены в Настройках.
class DashboardEmptyState extends StatelessWidget {
  const DashboardEmptyState({super.key, this.onOpenSettings});

  final VoidCallback? onOpenSettings;

  static const String title = 'Все разделы отключены';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outline),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.4),
              ),
            ),
            child: Icon(
              Icons.dashboard_customize_rounded,
              size: 36,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              'Включите Задачи, Привычки или Финансы в Настройках, '
              'чтобы на Дашборде появились карточки и быстрые действия.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (onOpenSettings != null) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onOpenSettings,
              icon: const Icon(Icons.settings_rounded, size: 18),
              label: const Text('Открыть Настройки'),
            ),
          ],
        ],
      ),
    );
  }
}
