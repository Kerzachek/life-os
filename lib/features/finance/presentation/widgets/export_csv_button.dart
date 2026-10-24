import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/backup/local_file_gateway.dart';
import '../../data/repositories/finance_repository.dart';
import '../../domain/transactions_csv.dart';

/// Кнопка «Экспорт операций в CSV» с выбором диапазона дат.
class ExportCsvButton extends ConsumerWidget {
  const ExportCsvButton({super.key, this.now = DateTime.now});

  /// Источник времени (переопределяется в тестах).
  final DateTime Function() now;

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final range = await showDialog<CsvExportRange>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Экспорт операций в CSV'),
        children: [
          for (final r in CsvExportRange.values)
            SimpleDialogOption(
              key: ValueKey('csv_range_${r.name}'),
              onPressed: () => Navigator.of(context).pop(r),
              child: Text(r.label),
            ),
        ],
      ),
    );
    if (range == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = ref.read(financeRepositoryProvider);
      final moment = now();
      final csv = buildTransactionsCsv(
        transactions: await repo.getTransactions(),
        accounts: {for (final a in await repo.getAllAccounts()) a.id: a},
        categories: {for (final c in await repo.getAllCategories()) c.id: c},
        range: range,
        now: moment,
      );
      final path = await ref
          .read(localFileGatewayProvider)
          .saveFile(
            dialogTitle: 'Сохранить операции',
            fileName: transactionsCsvFileName(range, moment),
            bytes: Uint8List.fromList(utf8.encode(csv)),
            extension: 'csv',
          );
      if (path != null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Операции выгружены в CSV')),
        );
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Ошибка экспорта: $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton.outlined(
      key: const ValueKey('export_csv'),
      tooltip: 'Экспорт операций в CSV',
      onPressed: () => _export(context, ref),
      icon: const Icon(Icons.file_download_outlined),
    );
  }
}
