import '../../../core/database/app_database.dart';
import 'finance_calculations.dart';

/// Период бюджета `год * 100 + месяц` для месяца [month].
int budgetPeriod(DateTime month) => month.year * 100 + month.month;

/// Детерминированный id лимита [categoryId] с месяца [period].
String categoryBudgetId(String categoryId, int period) =>
    'budget_${categoryId}_$period';

/// С какой доли лимита бюджет «жёлтый».
const double budgetWarningRatio = 0.7;

/// С какой доли лимита бюджет почти исчерпан (предупреждение в
/// «Доступно сегодня»).
const double budgetCriticalRatio = 0.9;

/// Состояние бюджета категории.
enum BudgetLevel {
  /// Потрачено меньше [budgetWarningRatio] лимита.
  ok,

  /// Потрачено [budgetWarningRatio]–[budgetCriticalRatio] лимита.
  warning,

  /// Потрачено от [budgetCriticalRatio] до 100% лимита.
  critical,

  /// Лимит превышен.
  exceeded,
}

/// Лимит категории [categoryId] на месяц [month]: запись с наибольшим
/// периодом не позже [month]. `null` — лимит не задан или снят.
double? effectiveBudgetLimit(
  Iterable<CategoryBudgetEntity> budgets,
  String categoryId,
  DateTime month,
) {
  final period = budgetPeriod(month);
  CategoryBudgetEntity? best;
  for (final b in budgets) {
    if (b.deletedAt != null || b.categoryId != categoryId) continue;
    if (b.period > period) continue;
    if (best == null || b.period > best.period) best = b;
  }
  final limit = best?.monthlyLimit;
  return limit == null || limit <= 0 ? null : limit;
}

/// Бюджет категории за месяц: лимит и фактические траты.
class CategoryBudgetStatus {
  const CategoryBudgetStatus({
    required this.category,
    required this.limit,
    required this.spent,
  });

  final FinanceCategoryEntity category;
  final double limit;
  final double spent;

  /// Доля потраченного (не ограничена сверху).
  double get ratio => limit <= 0 ? 0 : spent / limit;

  /// Осталось до лимита (отрицательное — перерасход).
  double get remaining => limit - spent;

  BudgetLevel get level {
    if (ratio > 1) return BudgetLevel.exceeded;
    if (ratio >= budgetCriticalRatio) return BudgetLevel.critical;
    if (ratio >= budgetWarningRatio) return BudgetLevel.warning;
    return BudgetLevel.ok;
  }

  /// Лимит почти исчерпан или превышен.
  bool get needsAttention =>
      level == BudgetLevel.critical || level == BudgetLevel.exceeded;
}

/// Бюджеты категорий с заданным лимитом за [month], от самых
/// «израсходованных» к самым свободным. Траты — все неудалённые расходы
/// категории за месяц (как в диаграмме расходов).
List<CategoryBudgetStatus> buildCategoryBudgets({
  required Iterable<CategoryBudgetEntity> budgets,
  required Iterable<FinanceCategoryEntity> categories,
  required Iterable<FinanceTransactionEntity> transactions,
  required DateTime month,
}) {
  final spent = <String, double>{};
  for (final t in transactions) {
    final id = t.categoryId;
    if (id == null || t.deletedAt != null || !isExpense(t)) continue;
    final d = t.date.toLocal();
    if (d.year != month.year || d.month != month.month) continue;
    spent[id] = (spent[id] ?? 0) + t.amount;
  }
  final result = <CategoryBudgetStatus>[];
  for (final c in categories) {
    if (c.deletedAt != null) continue;
    final limit = effectiveBudgetLimit(budgets, c.id, month);
    if (limit == null) continue;
    result.add(CategoryBudgetStatus(
      category: c,
      limit: limit,
      spent: spent[c.id] ?? 0,
    ));
  }
  result.sort((a, b) {
    final byRatio = b.ratio.compareTo(a.ratio);
    return byRatio != 0 ? byRatio : a.category.name.compareTo(b.category.name);
  });
  return result;
}
