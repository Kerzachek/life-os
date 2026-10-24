import 'dart:math' as math;

import '../../../core/database/app_database.dart';
import 'finance_calculations.dart';
import 'finance_enums.dart';

/// Сколько месяцев показывают графики динамики.
const int analyticsMonths = 6;

/// [count] месяцев, заканчивая [endMonth] (первые числа, от старых к новым).
List<DateTime> monthsEndingAt(DateTime endMonth, [int count = analyticsMonths]) {
  return [
    for (var i = count - 1; i >= 0; i--)
      DateTime(endMonth.year, endMonth.month - i),
  ];
}

/// Доходы и расходы за месяц.
class MonthlyCashflow {
  const MonthlyCashflow({
    required this.month,
    required this.income,
    required this.expense,
  });

  /// Первое число месяца.
  final DateTime month;
  final double income;
  final double expense;

  double get net => income - expense;
}

/// Доходы и расходы по месяцам за [count] месяцев до [endMonth] включительно.
/// Переводы между своими продуктами не учитываются.
List<MonthlyCashflow> buildMonthlyCashflow({
  required Iterable<FinanceTransactionEntity> transactions,
  required DateTime endMonth,
  int count = analyticsMonths,
}) {
  final months = monthsEndingAt(endMonth, count);
  final income = List.filled(count, 0.0);
  final expense = List.filled(count, 0.0);
  final first = months.first;
  for (final t in transactions) {
    if (t.deletedAt != null) continue;
    final d = t.date.toLocal();
    final index = (d.year - first.year) * 12 + d.month - first.month;
    if (index < 0 || index >= count) continue;
    switch (FinanceTransactionType.fromValue(t.type)) {
      case FinanceTransactionType.income:
        income[index] += t.amount;
      case FinanceTransactionType.expense:
        expense[index] += t.amount;
      case FinanceTransactionType.transfer:
        break;
    }
  }
  return [
    for (var i = 0; i < count; i++)
      MonthlyCashflow(month: months[i], income: income[i], expense: expense[i]),
  ];
}

/// Чистые активы на конец месяца.
class NetWorthPoint {
  const NetWorthPoint({
    required this.month,
    required this.assets,
    required this.debt,
  });

  /// Первое число месяца.
  final DateTime month;

  /// Сумма положительных остатков счетов и депозитов.
  final double assets;

  /// Долг по кредитам и кредитным картам.
  final double debt;

  double get netWorth => assets - debt;
}

/// Чистые активы на конец каждого из [count] месяцев до [endMonth].
///
/// Остаток продукта на дату восстанавливается из начального остатка и
/// операций до этой даты (как при пересчёте балансов). Продукт, созданный
/// позже и без более ранних операций, в прошлых месяцах не учитывается.
List<NetWorthPoint> buildNetWorthHistory({
  required Iterable<FinanceAccountEntity> accounts,
  required Iterable<FinanceTransactionEntity> transactions,
  required DateTime endMonth,
  int count = analyticsMonths,
}) {
  final txs = transactions.where((t) => t.deletedAt == null).toList();
  final active = accounts.where((a) => a.deletedAt == null).toList();
  return [
    for (final month in monthsEndingAt(endMonth, count))
      _netWorthAt(active, txs, month),
  ];
}

NetWorthPoint _netWorthAt(
  List<FinanceAccountEntity> accounts,
  List<FinanceTransactionEntity> transactions,
  DateTime month,
) {
  final cutoff = DateTime(month.year, month.month + 1);
  final before =
      transactions.where((t) => t.date.toLocal().isBefore(cutoff)).toList();
  var assets = 0.0;
  var debt = 0.0;
  for (final a in accounts) {
    final touched = before.any(
      (t) => t.accountId == a.id || t.targetAccountId == a.id,
    );
    if (!touched && !a.createdAt.toLocal().isBefore(cutoff)) continue;
    final balance = balanceFromFlow(
      kind: a.kind,
      initialBalance: a.initialBalance,
      flow: accountMoneyFlow(a.id, before),
    );
    if (FinanceAccountKind.fromValue(a.kind).isLiability) {
      debt += math.max(0.0, balance);
    } else {
      assets += math.max(0.0, balance);
    }
  }
  return NetWorthPoint(month: month, assets: assets, debt: debt);
}
