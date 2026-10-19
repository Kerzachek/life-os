import 'package:flutter/material.dart';

import 'expense_pie_chart.dart';
import 'finance_summary_cards.dart';
import 'obligations_card.dart';
import 'safe_to_spend_card.dart';

/// Вкладка «Обзор»: дневной бюджет, сводка, прогресс обязательных платежей
/// и диаграмма.
class FinanceOverviewTab extends StatelessWidget {
  const FinanceOverviewTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: const [
        SafeToSpendCard(),
        SizedBox(height: 12),
        FinanceSummaryCards(),
        SizedBox(height: 12),
        ObligationsCard(),
        SizedBox(height: 12),
        ExpensePieChart(),
      ],
    );
  }
}
