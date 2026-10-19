import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/repositories/finance_repository.dart';
import '../../domain/finance_enums.dart';
import '../../domain/finance_icons.dart';
import '../providers/finance_provider.dart';
import 'confirm_dialog.dart';
import 'finance_format.dart';
import 'transaction_dialog.dart';

/// Строка ленты операций.
class TransactionTile extends ConsumerWidget {
  const TransactionTile({super.key, required this.transaction});

  final FinanceTransactionEntity transaction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = transaction;
    final type = FinanceTransactionType.fromValue(t.type);
    final categories = ref.watch(financeCategoryMapProvider);
    final accounts = ref.watch(financeAccountMapProvider);
    final category = categories[t.categoryId];

    final amountColor = switch (type) {
      FinanceTransactionType.expense => AppTheme.fireAccent,
      FinanceTransactionType.income => AppTheme.successAccent,
      FinanceTransactionType.transfer => AppTheme.secondaryAccent,
    };
    final sign = switch (type) {
      FinanceTransactionType.expense => '−',
      FinanceTransactionType.income => '+',
      FinanceTransactionType.transfer => '',
    };
    final accountName = accounts[t.accountId]?.name ?? '—';
    final target = accounts[t.targetAccountId]?.name;
    final title = type == FinanceTransactionType.transfer
        ? 'Перевод: ${target ?? '—'}'
        : (category?.name ?? 'Без категории');
    final color = category == null
        ? amountColor
        : financeColorFromHex(category.color);
    final subtitle = [
      formatDate(t.date),
      if (target != null && type != FinanceTransactionType.transfer)
        '$accountName → $target'
      else
        accountName,
      if (t.note != null) t.note!,
    ].join(' · ');

    return ListTile(
      key: ValueKey('tx_${t.id}'),
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.18),
        child: Icon(
          category == null ? type.icon : financeIconByKey(category.icon),
          color: color,
          size: 20,
        ),
      ),
      title: Text(title),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$sign${formatMoney(t.amount)}',
            style: theme.textTheme.titleSmall
                ?.copyWith(color: amountColor, fontWeight: FontWeight.bold),
          ),
          PopupMenuButton<String>(
            tooltip: 'Действия',
            onSelected: (v) async {
              if (v == 'edit') {
                showDialog<void>(
                  context: context,
                  builder: (_) => TransactionDialog(transaction: t),
                );
                return;
              }
              final repo = ref.read(financeRepositoryProvider);
              final ok = await confirmAction(
                context,
                title: 'Удалить операцию?',
                message: 'Баланс продуктов будет пересчитан.',
              );
              if (ok) await repo.deleteTransaction(t.id);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Изменить')),
              PopupMenuItem(value: 'delete', child: Text('Удалить')),
            ],
          ),
        ],
      ),
    );
  }
}
