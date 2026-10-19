import 'package:flutter/material.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/finance_enums.dart';
import 'finance_format.dart';

/// Выбор счёта-источника для платежа. Если подходящий счёт один — возвращает
/// его без диалога; если счетов нет — `null`.
Future<String?> pickPayerAccount(
  BuildContext context,
  List<FinanceAccountEntity> accounts,
) async {
  final regular = accounts
      .where((a) => a.kind == FinanceAccountKind.account.value)
      .toList();
  if (regular.isEmpty) return null;
  if (regular.length == 1) return regular.first.id;

  return showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Списать со счёта'),
      children: [
        for (final a in regular)
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(a.id),
            child: Row(
              children: [
                Expanded(child: Text(a.name)),
                Text(formatMoney(a.balance)),
              ],
            ),
          ),
      ],
    ),
  );
}
