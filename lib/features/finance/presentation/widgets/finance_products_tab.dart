import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/finance_enums.dart';
import '../providers/finance_provider.dart';
import 'account_dialog.dart';
import 'product_card.dart';

/// Вкладка «Продукты»: счета, кредиты и депозиты.
class FinanceProductsTab extends ConsumerWidget {
  const FinanceProductsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final accounts = ref.watch(financeAccountsProvider);

    return accounts.when(
      data: (items) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                key: const ValueKey('add_product'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const AccountDialog(),
                ),
                icon: const Icon(Icons.add),
                label: const Text('Новый продукт'),
              ),
            ),
            for (final kind in FinanceAccountKind.values)
              ..._section(theme, kind, items.where((a) => a.kind == kind.value)),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 48),
                child: Center(
                  child: Text(
                    'Продуктов пока нет',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ),
              ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Ошибка: $e')),
    );
  }

  List<Widget> _section(
    ThemeData theme,
    FinanceAccountKind kind,
    Iterable<FinanceAccountEntity> products,
  ) {
    final list = products.toList();
    if (list.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 16, 0, 8),
        child: Text(
          kind.pluralLabel.toUpperCase(),
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 1.2,
          ),
        ),
      ),
      for (final p in list) ProductCard(product: p),
    ];
  }
}
