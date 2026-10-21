import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_provider.dart';

/// Блок «Уведомления»: глобальный переключатель системных уведомлений Windows.
class NotificationSettingsCard extends ConsumerWidget {
  const NotificationSettingsCard({super.key});

  static const List<String> triggers = [
    'Задачи: невыполненные задачи со сроком на сегодня и просроченные',
    'Привычки: вечернее напоминание о невыполненных привычках',
    'Финансы: обязательные платежи, срок которых близко или прошёл',
    'Доступность новой версии приложения',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final enabled = ref.watch(notificationsEnabledProvider);

    return Card(
      key: const ValueKey('notification_settings_card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.notifications_active_rounded,
                    size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Уведомления',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                Switch(
                  key: const ValueKey('notifications_switch'),
                  value: enabled,
                  activeThumbColor: colorScheme.primary,
                  onChanged: (value) => ref
                      .read(settingsControllerProvider)
                      .setNotificationsEnabled(value),
                ),
              ],
            ),
            Text(
              'Системные уведомления Windows. Напоминания приходят только '
              'от включённых разделов, не чаще раза в день по каждому типу.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            for (final trigger in triggers)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: enabled
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        trigger,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
