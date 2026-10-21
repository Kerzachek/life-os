import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/autostart_service.dart';
import '../../../../core/services/tray_service.dart';
import '../providers/settings_provider.dart';

/// Блок «Система и фоновый режим»: сворачивание в трей и автозапуск.
class SystemSettingsCard extends ConsumerWidget {
  const SystemSettingsCard({super.key});

  Future<void> _setLaunchAtStartup(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) async {
    try {
      await ref.read(settingsControllerProvider).setLaunchAtStartup(enabled);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось изменить автозапуск: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final backgroundMode = ref.watch(backgroundModeEnabledProvider);
    final launchAtStartup =
        ref.watch(launchAtStartupEnabledProvider).value ?? false;

    return Card(
      key: const ValueKey('system_settings_card'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Row(
                children: [
                  Icon(
                    Icons.desktop_windows_rounded,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Система и фоновый режим',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Поведение приложения в ${Platform.isMacOS ? 'macOS' : 'Windows'}. '
                'Изменения применяются сразу.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const Divider(height: 1),
            _SystemToggleTile(
              key: const ValueKey('background_mode_switch'),
              icon: Icons.move_to_inbox_rounded,
              title: 'Работа в фоне',
              description: 'Сворачивать приложение в системный трей при '
                  'закрытии окна, чтобы получать уведомления и '
                  'синхронизировать данные',
              value: backgroundMode,
              onChanged: TrayService.isAvailable
                  ? (value) => ref
                      .read(settingsControllerProvider)
                      .setBackgroundModeEnabled(value)
                  : null,
            ),
            const Divider(height: 1),
            _SystemToggleTile(
              key: const ValueKey('launch_at_startup_switch'),
              icon: Icons.power_settings_new_rounded,
              title: Platform.isMacOS
                  ? 'Автозапуск с macOS'
                  : 'Автозапуск с Windows',
              description:
                  'Автоматически запускать LifeOS при входе в систему',
              value: launchAtStartup,
              onChanged: AutostartService.isAvailable
                  ? (value) => _setLaunchAtStartup(context, ref, value)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _SystemToggleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool value;

  /// `null` — переключатель недоступен на этой платформе.
  final ValueChanged<bool>? onChanged;

  const _SystemToggleTile({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = value ? colorScheme.primary : colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accent.withValues(alpha: 0.4)),
            ),
            child: Icon(icon, size: 20, color: accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: value,
            activeThumbColor: colorScheme.primary,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
