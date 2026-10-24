import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/backup/local_backup_service.dart';
import '../../../../core/backup/local_file_gateway.dart';
import '../../../../core/sync/sync_payload.dart';
import '../../../finance/presentation/widgets/confirm_dialog.dart';

/// Локальная резервная копия в JSON — работает без Google Drive.
class BackupSettingsCard extends ConsumerStatefulWidget {
  const BackupSettingsCard({super.key, this.now = DateTime.now});

  /// Источник времени для имени файла (переопределяется в тестах).
  final DateTime Function() now;

  @override
  ConsumerState<BackupSettingsCard> createState() => _BackupSettingsCardState();
}

class _BackupSettingsCardState extends ConsumerState<BackupSettingsCard> {
  bool _busy = false;

  Future<void> _run(Future<String?> Function() action) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    String? message;
    try {
      message = await action();
    } on SyncFormatException catch (e) {
      message = e.message;
    } catch (e) {
      message = 'Ошибка: $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<String?> _export() async {
    final bytes = await ref.read(localBackupServiceProvider).createBackup();
    final path = await ref
        .read(localFileGatewayProvider)
        .saveFile(
          dialogTitle: 'Сохранить резервную копию',
          fileName: backupFileName(widget.now()),
          bytes: bytes,
          extension: 'json',
        );
    return path == null ? null : 'Резервная копия сохранена';
  }

  Future<String?> _import() async {
    final bytes = await ref
        .read(localFileGatewayProvider)
        .pickFile(dialogTitle: 'Выберите резервную копию', extension: 'json');
    if (bytes == null) return null;
    final service = ref.read(localBackupServiceProvider);
    final payload = service.parseBackup(bytes);
    if (!mounted) return null;
    final confirmed = await confirmAction(
      context,
      title: 'Восстановить из копии?',
      message:
          'Копия от ${_formatTimestamp(payload.lastSyncTimestamp)}, '
          'записей: ${LocalBackupService.countRecords(payload)}.\n\n'
          'Данные будут объединены с текущими: запись из копии заменит '
          'локальную, только если она изменялась позже. Новые записи '
          'добавятся, локальные записи, которых нет в копии, останутся.',
      confirmLabel: 'Восстановить',
    );
    if (!confirmed) return null;
    final result = await service.restore(payload);
    return 'Восстановлено: добавлено ${result.inserted}, '
        'обновлено ${result.updated}, без изменений ${result.skipped}';
  }

  static String _formatTimestamp(DateTime t) {
    final d = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year} '
        '${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      key: const ValueKey('backup_settings_card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.save_alt_rounded,
                  size: 18,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Резервное копирование',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Локальный файл JSON: задачи, привычки, финансы, заметки, '
              'распорядок. Не требует входа в Google.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const ValueKey('backup_export'),
                  onPressed: _busy ? null : () => _run(_export),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Создать резервную копию (JSON)'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('backup_import'),
                  onPressed: _busy ? null : () => _run(_import),
                  icon: const Icon(Icons.upload_file_rounded, size: 18),
                  label: const Text('Восстановить из копии (JSON)'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
