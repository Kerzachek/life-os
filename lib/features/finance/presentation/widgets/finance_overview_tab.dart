import 'package:flutter/material.dart';

import 'category_budgets_card.dart';
import 'credit_cards_card.dart';
import 'expense_pie_chart.dart';
import 'finance_analytics_charts.dart';
import 'finance_summary_cards.dart';
import 'obligations_card.dart';
import 'safe_to_spend_card.dart';

/// Вкладка «Обзор»: дневной бюджет, сводка, прогресс обязательных платежей,
/// бюджеты категорий и аналитика за выбранный месяц.
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
        CreditCardsCard(),
        ObligationsCard(),
        SizedBox(height: 12),
        ExpensePieChart(),
        SizedBox(height: 12),
        CategoryBudgetsCard(),
        SizedBox(height: 12),
        MonthlyCashflowChart(),
        SizedBox(height: 12),
        NetWorthChart(),
      ],
    );
  }
}
