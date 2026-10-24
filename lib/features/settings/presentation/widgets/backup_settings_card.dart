import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/backup/local_backup_service.dart';
import '../../../../core/backup/local_backup_store.dart';
import '../../../../core/backup/local_file_gateway.dart';
import '../../../../core/sync/sync_payload.dart';
import '../../../finance/presentation/widgets/confirm_dialog.dart';

/// Локальная резервная копия в JSON — работает без Google Drive.
///
/// Копии хранятся в папке приложения (автоматически раз в сутки и при
/// выходе, последние [LocalBackupStore.maxCopies]); ручную копию можно ещё
/// и сохранить наружу.
class BackupSettingsCard extends ConsumerStatefulWidget {
  const BackupSettingsCard({super.key, this.now = DateTime.now});

  /// Источник времени для имени файла (переопределяется в тестах).
  final DateTime Function() now;

  @override
  ConsumerState<BackupSettingsCard> createState() => _BackupSettingsCardState();
}

/// Выбор в диалоге восстановления: локальная копия или внешний файл.
class _RestoreSource {
  const _RestoreSource.local(LocalBackupEntry this.entry);
  const _RestoreSource.external() : entry = null;

  final LocalBackupEntry? entry;
}

class _BackupSettingsCardState extends ConsumerState<BackupSettingsCard> {
  bool _busy = false;
  late Future<List<LocalBackupEntry>> _localCopies;

  @override
  void initState() {
    super.initState();
    _localCopies = _loadLocalCopies();
  }

  Future<List<LocalBackupEntry>> _loadLocalCopies() async {
    try {
      return await ref.read(localBackupStoreProvider).list();
    } catch (_) {
      return const [];
    }
  }

  void _refreshLocalCopies() {
    if (!mounted) return;
    setState(() {
      _localCopies = _loadLocalCopies();
    });
  }

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
    final now = widget.now();
    final bytes = await ref.read(localBackupServiceProvider).createBackup();
    await ref.read(localBackupStoreProvider).save(bytes, now);
    _refreshLocalCopies();
    final path = await ref
        .read(localFileGatewayProvider)
        .saveFile(
          dialogTitle: 'Сохранить резервную копию',
          fileName: backupFileName(now),
          bytes: bytes,
          extension: 'json',
        );
    return path == null
        ? 'Резервная копия сохранена в папке приложения'
        : 'Резервная копия сохранена в папке приложения и в выбранный файл';
  }

  Future<String?> _import() async {
    final bytes = await _pickBackupBytes();
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

  /// Без локальных копий сразу открывается выбор файла, иначе — список копий
  /// из папки приложения и пункт «Выбрать файл…».
  Future<Uint8List?> _pickBackupBytes() async {
    final copies = await _loadLocalCopies();
    _RestoreSource? source = const _RestoreSource.external();
    if (copies.isNotEmpty && mounted) {
      source = await showDialog<_RestoreSource>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Выберите резервную копию'),
          children: [
            for (final entry in copies)
              SimpleDialogOption(
                key: ValueKey('backup_local_${entry.fileName}'),
                onPressed: () =>
                    Navigator.of(context).pop(_RestoreSource.local(entry)),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.history_rounded),
                  title: Text(_formatDate(entry.date)),
                  subtitle: Text(
                    '${entry.fileName} · ${_formatSize(entry.sizeBytes)}',
                  ),
                ),
              ),
            const Divider(),
            SimpleDialogOption(
              key: const ValueKey('backup_pick_external'),
              onPressed: () =>
                  Navigator.of(context).pop(const _RestoreSource.external()),
              child: const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.folder_open_rounded),
                title: Text('Выбрать файл…'),
              ),
            ),
          ],
        ),
      );
    }
    if (source == null) return null;
    final entry = source.entry;
    if (entry != null) {
      return ref.read(localBackupStoreProvider).read(entry);
    }
    return ref
        .read(localFileGatewayProvider)
        .pickFile(dialogTitle: 'Выберите резервную копию', extension: 'json');
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _formatTimestamp(DateTime t) {
    final d = t.toLocal();
    return '${_two(d.day)}.${_two(d.month)}.${d.year} '
        '${_two(d.hour)}:${_two(d.minute)}';
  }

  static String _formatDate(DateTime d) =>
      '${_two(d.day)}.${_two(d.month)}.${d.year}';

  static String _formatSize(int bytes) => bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(1)} КБ'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hintStyle = theme.textTheme.bodySmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );

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
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Локальный файл JSON: задачи, привычки, финансы, заметки, '
              'распорядок. Не требует входа в Google. Копия создаётся '
              'автоматически раз в сутки и при выходе, в папке приложения '
              'хранятся последние ${LocalBackupStore.maxCopies}.',
              style: hintStyle,
            ),
            const SizedBox(height: 6),
            FutureBuilder<List<LocalBackupEntry>>(
              future: _localCopies,
              builder: (context, snapshot) {
                final copies = snapshot.data ?? const <LocalBackupEntry>[];
                return Text(
                  copies.isEmpty
                      ? 'Локальных копий пока нет'
                      : 'Локальных копий: ${copies.length}, последняя — '
                            '${_formatDate(copies.first.date)}',
                  key: const ValueKey('backup_local_status'),
                  style: hintStyle,
                );
              },
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
