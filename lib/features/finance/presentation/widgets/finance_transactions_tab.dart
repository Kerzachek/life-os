import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/responsive.dart';
import '../../domain/finance_enums.dart';
import '../providers/finance_provider.dart';
import 'export_csv_button.dart';
import 'transaction_dialog.dart';
import 'transaction_tile.dart';

/// Вкладка «Операции»: поиск, фильтры и лента.
class FinanceTransactionsTab extends ConsumerWidget {
  const FinanceTransactionsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final filter = ref.watch(transactionFilterProvider);
    final notifier = ref.read(transactionFilterProvider.notifier);
    final categories = ref.watch(financeCategoriesProvider).value ?? const [];
    final transactions = ref.watch(filteredTransactionsProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('tx_search'),
                  onChanged: notifier.setQuery,
                  decoration: const InputDecoration(
                    hintText: 'Поиск по заметке',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const ExportCsvButton(),
              const SizedBox(width: 8),
              FilledButton.icon(
                key: const ValueKey('add_transaction'),
                onPressed: () => showFormSheet<void>(
                  context: context,
                  builder: (_) => const TransactionDialog(),
                ),
                icon: const Icon(Icons.add),
                label: const Text('Операция'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final p in FinancePeriod.values)
                ChoiceChip(
                  key: ValueKey('period_${p.name}'),
                  label: Text(p.label),
                  selected: filter.period == p,
                  onSelected: (_) => notifier.setPeriod(p),
                ),
              const SizedBox(width: 8),
              ChoiceChip(
                key: const ValueKey('type_all'),
                label: const Text('Все типы'),
                selected: filter.type == null,
                onSelected: (_) => notifier.setType(null),
              ),
              for (final t in FinanceTransactionType.values)
                ChoiceChip(
                  key: ValueKey('type_${t.name}'),
                  label: Text(t.label),
                  selected: filter.type == t,
                  onSelected: (_) => notifier.setType(t),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 260,
              child: DropdownButtonFormField<String?>(
                key: const ValueKey('filter_category'),
                initialValue: categories.any((c) => c.id == filter.categoryId)
                    ? filter.categoryId
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Категория',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Все категории'),
                  ),
                  for (final c in categories)
                    DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
                ],
                onChanged: notifier.setCategory,
              ),
            ),
          ),
        ),
        Expanded(
          child: transactions.when(
            data: (items) {
              if (items.isEmpty) {
                return Center(
                  child: Text(
                    'Операций не найдено',
                    key: const ValueKey('tx_empty'),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 96),
                itemCount: items.length,
                itemBuilder: (context, i) => TransactionTile(
                  key: ValueKey(items[i].id),
                  transaction: items[i],
                ),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Ошибка: $e')),
          ),
        ),
      ],
    );
  }
}
