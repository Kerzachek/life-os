import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/finance_provider.dart';
import '../widgets/finance_overview_tab.dart';
import '../widgets/finance_products_tab.dart';
import '../widgets/finance_settings_tab.dart';
import '../widgets/finance_transactions_tab.dart';
import '../widgets/transaction_dialog.dart';

/// Финансовый борд: Обзор / Продукты / Операции / Настройки.
class FinanceScreen extends ConsumerStatefulWidget {
  const FinanceScreen({super.key});

  @override
  ConsumerState<FinanceScreen> createState() => _FinanceScreenState();
}

enum _FinanceTab {
  overview('Обзор', Icons.dashboard_outlined),
  products('Продукты', Icons.account_balance_outlined),
  transactions('Операции', Icons.receipt_long_outlined),
  settings('Настройки', Icons.tune_outlined);

  const _FinanceTab(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _FinanceScreenState extends ConsumerState<FinanceScreen> {
  _FinanceTab _tab = _FinanceTab.overview;

  Widget _body() {
    switch (_tab) {
      case _FinanceTab.overview:
        return const FinanceOverviewTab();
      case _FinanceTab.products:
        return const FinanceProductsTab();
      case _FinanceTab.transactions:
        return const FinanceTransactionsTab();
      case _FinanceTab.settings:
        return const FinanceSettingsTab();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Держим стримы живыми, пока открыт экран.
    ref.watch(financeAccountsProvider);
    ref.watch(financeTransactionsProvider);

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<_FinanceTab>(
                    key: const ValueKey('finance_tabs'),
                    showSelectedIcon: false,
                    segments: [
                      for (final t in _FinanceTab.values)
                        ButtonSegment(
                          value: t,
                          label: Text(t.label),
                          icon: Icon(t.icon, size: 18),
                        ),
                    ],
                    selected: {_tab},
                    onSelectionChanged: (s) => setState(() => _tab = s.first),
                  ),
                ),
              ),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
      floatingActionButton: _tab == _FinanceTab.overview
          ? FloatingActionButton.extended(
              key: const ValueKey('finance_fab'),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const TransactionDialog(),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Операция'),
            )
          : null,
    );
  }
}
