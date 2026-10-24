import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/update_service.dart';
import 'update_dialogs.dart';

/// Блок «О приложении»: текущая версия и проверка обновлений.
class UpdateSettingsCard extends ConsumerStatefulWidget {
  const UpdateSettingsCard({super.key});

  @override
  ConsumerState<UpdateSettingsCard> createState() => _UpdateSettingsCardState();
}

class _UpdateSettingsCardState extends ConsumerState<UpdateSettingsCard> {
  bool _checking = false;
  String? _status;

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _status = null;
    });

    String? status;
    Release? release;
    try {
      release = await ref.read(updateServiceProvider).checkForUpdates();
      if (release == null) status = 'У вас установлена последняя версия';
    } on UpdateException catch (e) {
      status = e.message;
    } catch (e) {
      status = 'Не удалось проверить обновления: $e';
    }

    if (!mounted) return;
    setState(() {
      _checking = false;
      _status = status;
    });

    if (release != null) {
      await showUpdateAvailableDialog(context, ref, release);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final version = ref.watch(currentAppVersionProvider);

    return Card(
      key: const ValueKey('update_settings_card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.system_update_rounded,
                    size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Обновления',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Текущая версия: ${version.value ?? '…'}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            if (_status != null) ...[
              const SizedBox(height: 8),
              Text(
                _status!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('update_check'),
              onPressed: _checking ? null : _check,
              icon: _checking
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Проверить обновления'),
            ),
          ],
        ),
      ),
    );
  }
}
