import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/platform_info.dart';
import '../providers/settings_provider.dart';

/// Блок «Плавающая кнопка быстрых действий»: показ/скрытие виджета поверх
/// всех разделов. Изменение применяется сразу, без перезапуска.
class QuickActionsSettingsCard extends ConsumerWidget {
  const QuickActionsSettingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final enabled = ref.watch(showQuickActionsWidgetProvider);
    final hotkey = isMacOSPlatform ? 'Cmd+Shift+Q' : 'Ctrl+Shift+Q';

    return Card(
      key: const ValueKey('quick_actions_settings_card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bubble_chart_rounded,
                    size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Плавающая кнопка быстрых действий',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                Switch(
                  key: const ValueKey('quick_actions_widget_switch'),
                  value: enabled,
                  activeThumbColor: colorScheme.primary,
                  onChanged: (value) => ref
                      .read(settingsControllerProvider)
                      .setShowQuickActionsWidget(value),
                ),
              ],
            ),
            Text(
              'Показывать полупрозрачный перемещаемый виджет быстрого доступа '
              '(расход, пополнение, перевод, заметка) поверх всех экранов',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            if (isDesktopPlatform) ...[
              const SizedBox(height: 4),
              Text(
                'Открыть меню с клавиатуры: $hotkey',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
