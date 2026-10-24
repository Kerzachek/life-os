import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../quick_actions/presentation/providers/system_overlay_provider.dart';
import '../providers/settings_provider.dart';

/// Блок «Системная кнопка быстрых действий»: кнопка поверх всех окон и
/// приложений ОС, вне окна LifeOS. Выключение сразу уничтожает оверлей.
class SystemOverlaySettingsCard extends ConsumerWidget {
  const SystemOverlaySettingsCard({super.key});

  Future<void> _setEnabled(WidgetRef ref, bool enabled) async {
    if (enabled) {
      ref.read(systemOverlayDismissedProvider.notifier).restore();
    }
    await ref.read(settingsControllerProvider).setSystemOverlayEnabled(enabled);
    // Android: без доступа оверлей не появится — сразу ведём в настройки.
    if (enabled && !await ref.read(systemOverlayPermissionProvider.future)) {
      await ref.read(systemOverlayServiceProvider).requestPermission();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final enabled = ref.watch(systemOverlayEnabledProvider);
    final hideWhenAppVisible =
        ref.watch(systemOverlayHideWhenAppVisibleProvider);
    final dismissed = ref.watch(systemOverlayDismissedProvider);
    final permission = ref.watch(systemOverlayPermissionProvider).value;
    final mutedStyle =
        theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant);

    return Card(
      key: const ValueKey('system_overlay_settings_card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.picture_in_picture_alt_rounded,
                    size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Системная кнопка быстрых действий',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                Switch(
                  key: const ValueKey('system_overlay_switch'),
                  value: enabled,
                  activeThumbColor: colorScheme.primary,
                  onChanged: (value) => _setEnabled(ref, value),
                ),
              ],
            ),
            Text(
              'Оверлей поверх всех окон и приложений: полупрозрачная '
              'кнопка, которую можно перетаскивать к краю экрана. Меню — '
              'расход, пополнение, перевод, заметка, чек-ин; выбор действия '
              'открывает LifeOS с нужной формой.',
              style: mutedStyle,
            ),
            if (enabled && Platform.isAndroid && permission != null) ...[
              const SizedBox(height: 12),
              _PermissionStatus(granted: permission),
            ],
            if (enabled && dismissed) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Оверлей скрыт до следующего запуска приложения',
                      style: mutedStyle,
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('system_overlay_restore_button'),
                    onPressed: () => ref
                        .read(systemOverlayDismissedProvider.notifier)
                        .restore(),
                    child: const Text('Показать снова'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 4),
            CheckboxListTile(
              key: const ValueKey('system_overlay_hide_checkbox'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              value: hideWhenAppVisible,
              onChanged: enabled
                  ? (value) => ref
                      .read(settingsControllerProvider)
                      .setSystemOverlayHideWhenAppVisible(value ?? true)
                  : null,
              title: const Text(
                'Скрывать системный оверлей, когда открыто основное окно '
                'LifeOS',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Статус доступа «Поверх других приложений» (Android).
class _PermissionStatus extends ConsumerWidget {
  const _PermissionStatus({required this.granted});

  final bool granted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final color =
        granted ? const Color(0xFF00B894) : theme.colorScheme.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              granted ? Icons.check_circle_rounded : Icons.error_rounded,
              size: 16,
              color: color,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                granted
                    ? 'Разрешение «Поверх других приложений» выдано'
                    : 'Нет разрешения «Поверх других приложений»',
                style: theme.textTheme.bodySmall?.copyWith(color: color),
              ),
            ),
          ],
        ),
        if (!granted) ...[
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            key: const ValueKey('system_overlay_permission_button'),
            onPressed: () =>
                ref.read(systemOverlayServiceProvider).requestPermission(),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Выдать разрешение в настройках системы'),
          ),
        ],
      ],
    );
  }
}
