import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/update_service.dart';

String _formatSize(int bytes) {
  if (bytes <= 0) return '—';
  const mb = 1024 * 1024;
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} МБ';
  return '${(bytes / 1024).toStringAsFixed(0)} КБ';
}

/// Диалог «Доступна новая версия». При согласии открывает диалог загрузки.
Future<void> showUpdateAvailableDialog(
  BuildContext context,
  WidgetRef ref,
  Release release,
) async {
  final current = await ref.read(currentAppVersionProvider.future);
  if (!context.mounted) return;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => _UpdateAvailableDialog(
      release: release,
      currentVersion: current,
    ),
  );
  if (confirmed != true || !context.mounted) return;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UpdateDownloadDialog(
      release: release,
      service: ref.read(updateServiceProvider),
    ),
  );
}

class _UpdateAvailableDialog extends StatelessWidget {
  final Release release;
  final String currentVersion;

  const _UpdateAvailableDialog({
    required this.release,
    required this.currentVersion,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final asset = release.installerAsset;
    final changelog = release.body.trim();

    return AlertDialog(
      title: Text('Доступна версия ${release.version ?? release.tagName}'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Установлена: $currentVersion · '
              'Размер: ${_formatSize(asset?.size ?? 0)}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Text('Что нового', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: SingleChildScrollView(
                child: SelectableText(
                  changelog.isEmpty ? 'Описание изменений отсутствует' : changelog,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
            if (asset == null) ...[
              const SizedBox(height: 12),
              Text(
                'В релизе нет файла установщика — автообновление недоступно.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Напомнить позже'),
        ),
        FilledButton(
          key: const ValueKey('update_now'),
          onPressed:
              asset == null ? null : () => Navigator.of(context).pop(true),
          child: const Text('Обновить сейчас'),
        ),
      ],
    );
  }
}

/// Немодально-незакрываемый диалог загрузки: закрыть можно только после ошибки.
class _UpdateDownloadDialog extends StatefulWidget {
  final Release release;
  final UpdateService service;

  const _UpdateDownloadDialog({required this.release, required this.service});

  @override
  State<_UpdateDownloadDialog> createState() => _UpdateDownloadDialogState();
}

class _UpdateDownloadDialogState extends State<_UpdateDownloadDialog> {
  double _progress = 0;
  bool _installing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      await widget.service.downloadAndInstallUpdate(widget.release, (value) {
        if (!mounted) return;
        setState(() {
          _progress = value;
          _installing = value >= 1.0;
        });
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is UpdateException ? e.message : '$e');
    }
  }

  void _retry() {
    setState(() {
      _error = null;
      _progress = 0;
      _installing = false;
    });
    _start();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failed = _error != null;

    return PopScope(
      canPop: failed,
      child: AlertDialog(
        title: Text(failed ? 'Ошибка обновления' : 'Загрузка обновления'),
        content: SizedBox(
          width: 420,
          child: failed
              ? Text(_error!)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(
                      value: _installing ? null : _progress,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _installing
                          ? 'Запуск установщика… Приложение будет закрыто.'
                          : '${(_progress * 100).toStringAsFixed(0)}%',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
        ),
        actions: failed
            ? [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Закрыть'),
                ),
                FilledButton(
                  onPressed: _retry,
                  child: const Text('Повторить'),
                ),
              ]
            : null,
      ),
    );
  }
}
