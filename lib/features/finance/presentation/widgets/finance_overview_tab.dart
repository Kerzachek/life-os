import 'package:flutter/material.dart';

import 'expense_pie_chart.dart';
import 'finance_summary_cards.dart';
import 'obligations_card.dart';

/// Вкладка «Обзор»: сводка, прогресс обязательных платежей и диаграмма.
class FinanceOverviewTab extends StatelessWidget {
  const FinanceOverviewTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: const [
        FinanceSummaryCards(),
        SizedBox(height: 12),
        ObligationsCard(),
        SizedBox(height: 12),
        ExpensePieChart(),
      ],
    );
  }
}
