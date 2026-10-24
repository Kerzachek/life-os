import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../data/repositories/finance_repository.dart';
import '../../domain/category_budgets.dart';
import '../../domain/finance_analytics.dart';
import '../../domain/finance_calculations.dart';
import '../../domain/finance_enums.dart';

/// Ключ настройки «Учитывать кредитные карты в „Доступно сегодня“».
const String financeIncludeCreditCardsKey = 'finance_include_credit_cards';

/// Учитывать ли кредитки в дневном бюджете (по умолчанию — да).
final financeIncludeCreditCardsProvider = Provider<bool>((ref) {
  final settings = ref.watch(rawSettingsStreamProvider).value;
  return settings?[financeIncludeCreditCardsKey] != 'false';
});

// ------------------------------------------------------------ Стримы Drift

final financeAccountsProvider = StreamProvider<List<FinanceAccountEntity>>((ref) {
  return ref.watch(financeRepositoryProvider).watchAccounts();
});

final financeCategoriesProvider =
    StreamProvider<List<FinanceCategoryEntity>>((ref) {
  return ref.watch(financeRepositoryProvider).watchCategories();
});

final financeTransactionsProvider =
    StreamProvider<List<FinanceTransactionEntity>>((ref) {
  return ref.watch(financeRepositoryProvider).watchTransactions();
});

final financeObligationsProvider = StreamProvider<List<ObligationEntity>>((ref) {
  return ref.watch(financeRepositoryProvider).watchObligations();
});

// ----------------------------------------------------------- Состояние UI

/// Временный режим администратора: открывает ручной пропуск обязательных
/// платежей. Не сохраняется и сбрасывается при уходе с экрана «Финансы».
class FinanceAdminModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;

  void disable() => state = false;
}

final financeAdminModeProvider =
    NotifierProvider<FinanceAdminModeNotifier, bool>(
  FinanceAdminModeNotifier.new,
);

/// Месяц, выбранный для обзора (всегда первое число месяца).
class SelectedMonthNotifier extends Notifier<DateTime> {
  @override
  DateTime build() {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }

  void shift(int months) {
    state = DateTime(state.year, state.month + months);
  }

  void reset() {
    final now = DateTime.now();
    state = DateTime(now.year, now.month);
  }
}

final financeSelectedMonthProvider =
    NotifierProvider<SelectedMonthNotifier, DateTime>(
  SelectedMonthNotifier.new,
);

class TransactionFilterNotifier extends Notifier<TransactionFilter> {
  @override
  TransactionFilter build() => const TransactionFilter();

  void setPeriod(FinancePeriod period) {
    state = TransactionFilter(
      period: period,
      type: state.type,
      categoryId: state.categoryId,
      query: state.query,
    );
  }

  /// `null` — любой тип.
  void setType(FinanceTransactionType? type) {
    state = TransactionFilter(
      period: state.period,
      type: type,
      categoryId: state.categoryId,
      query: state.query,
    );
  }

  /// `null` — все категории.
  void setCategory(String? categoryId) {
    state = TransactionFilter(
      period: state.period,
      type: state.type,
      categoryId: categoryId,
      query: state.query,
    );
  }

  void setQuery(String query) {
    state = TransactionFilter(
      period: state.period,
      type: state.type,
      categoryId: state.categoryId,
      query: query,
    );
  }
}

final transactionFilterProvider =
    NotifierProvider<TransactionFilterNotifier, TransactionFilter>(
  TransactionFilterNotifier.new,
);

// ------------------------------------------------------ Производные данные

final filteredTransactionsProvider =
    Provider<AsyncValue<List<FinanceTransactionEntity>>>((ref) {
  final filter = ref.watch(transactionFilterProvider);
  final now = DateTime.now();
  return ref
      .watch(financeTransactionsProvider)
      .whenData((all) => all.where((t) => filter.matches(t, now)).toList());
});

/// Обязательные платежи со статусом оплаты за ТЕКУЩИЙ расчётный месяц
/// (не зависит от месяца, выбранного для диаграммы).
final obligationStatusesProvider =
    Provider<AsyncValue<List<ObligationStatus>>>((ref) {
  final nowDate = DateTime.now();
  final month = DateTime(nowDate.year, nowDate.month);
  final obligations = ref.watch(financeObligationsProvider);
  final transactions = ref.watch(financeTransactionsProvider);
  // Счета нужны для рассрочек: срок берётся из ближайшего списания кредита.
  final accounts = ref.watch(financeAccountsProvider);
  if (obligations.hasError) {
    return AsyncValue.error(obligations.error!, obligations.stackTrace!);
  }
  if (transactions.hasError) {
    return AsyncValue.error(transactions.error!, transactions.stackTrace!);
  }
  if (accounts.hasError) {
    return AsyncValue.error(accounts.error!, accounts.stackTrace!);
  }
  final o = obligations.value;
  final t = transactions.value;
  final a = accounts.value;
  if (o == null || t == null || a == null) return const AsyncValue.loading();
  return AsyncValue.data(buildObligationStatuses(o, t, month, accounts: a));
});

final financeSummaryProvider = Provider<AsyncValue<FinanceSummary>>((ref) {
  final accounts = ref.watch(financeAccountsProvider);
  final statuses = ref.watch(obligationStatusesProvider);
  if (accounts.hasError) {
    return AsyncValue.error(accounts.error!, accounts.stackTrace!);
  }
  if (statuses.hasError) {
    return AsyncValue.error(statuses.error!, statuses.stackTrace!);
  }
  final a = accounts.value;
  final s = statuses.value;
  if (a == null || s == null) return const AsyncValue.loading();
  return AsyncValue.data(buildSummary(accounts: a, obligations: s));
});

/// «Свободный дневной бюджет» (Safe-to-Spend) на сегодня. Пересчитывается
/// при любом изменении счетов, операций и обязательных платежей.
final dailySafeBudgetProvider =
    Provider<AsyncValue<DailySafeBudgetState>>((ref) {
  final accounts = ref.watch(financeAccountsProvider);
  final transactions = ref.watch(financeTransactionsProvider);
  final statuses = ref.watch(obligationStatusesProvider);
  if (accounts.hasError) {
    return AsyncValue.error(accounts.error!, accounts.stackTrace!);
  }
  if (transactions.hasError) {
    return AsyncValue.error(transactions.error!, transactions.stackTrace!);
  }
  if (statuses.hasError) {
    return AsyncValue.error(statuses.error!, statuses.stackTrace!);
  }
  final a = accounts.value;
  final t = transactions.value;
  final s = statuses.value;
  if (a == null || t == null || s == null) return const AsyncValue.loading();
  return AsyncValue.data(
    buildDailySafeBudget(
      accounts: a,
      obligations: s,
      transactions: t,
      now: DateTime.now(),
      includeCreditCards: ref.watch(financeIncludeCreditCardsProvider),
    ),
  );
});

final expenseBreakdownProvider =
    Provider<AsyncValue<List<CategoryExpense>>>((ref) {
  final month = ref.watch(financeSelectedMonthProvider);
  final transactions = ref.watch(financeTransactionsProvider);
  final categories = ref.watch(financeCategoriesProvider);
  if (transactions.hasError) {
    return AsyncValue.error(transactions.error!, transactions.stackTrace!);
  }
  if (categories.hasError) {
    return AsyncValue.error(categories.error!, categories.stackTrace!);
  }
  final t = transactions.value;
  final c = categories.value;
  if (t == null || c == null) return const AsyncValue.loading();
  return AsyncValue.data(
    buildExpenseBreakdown(transactions: t, categories: c, month: month),
  );
});

/// Словарь категорий по id для быстрого доступа из виджетов.
final financeCategoryMapProvider =
    Provider<Map<String, FinanceCategoryEntity>>((ref) {
  final list = ref.watch(financeCategoriesProvider).value ?? const [];
  return {for (final c in list) c.id: c};
});

/// Словарь продуктов по id.
final financeAccountMapProvider =
    Provider<Map<String, FinanceAccountEntity>>((ref) {
  final list = ref.watch(financeAccountsProvider).value ?? const [];
  return {for (final a in list) a.id: a};
});

// ------------------------------------------------- Бюджеты и аналитика

final financeBudgetsProvider =
    StreamProvider<List<CategoryBudgetEntity>>((ref) {
  return ref.watch(financeRepositoryProvider).watchBudgets();
});

AsyncValue<List<CategoryBudgetStatus>> _budgetsFor(Ref ref, DateTime month) {
  final budgets = ref.watch(financeBudgetsProvider);
  final categories = ref.watch(financeCategoriesProvider);
  final transactions = ref.watch(financeTransactionsProvider);
  if (budgets.hasError) {
    return AsyncValue.error(budgets.error!, budgets.stackTrace!);
  }
  if (categories.hasError) {
    return AsyncValue.error(categories.error!, categories.stackTrace!);
  }
  if (transactions.hasError) {
    return AsyncValue.error(transactions.error!, transactions.stackTrace!);
  }
  final b = budgets.value;
  final c = categories.value;
  final t = transactions.value;
  if (b == null || c == null || t == null) return const AsyncValue.loading();
  return AsyncValue.data(buildCategoryBudgets(
    budgets: b,
    categories: c,
    transactions: t,
    month: month,
  ));
}

/// Бюджеты категорий за месяц, выбранный в обзоре.
final categoryBudgetsProvider =
    Provider<AsyncValue<List<CategoryBudgetStatus>>>((ref) {
  return _budgetsFor(ref, ref.watch(financeSelectedMonthProvider));
});

/// Почти исчерпанные и превышенные лимиты ТЕКУЩЕГО месяца — предупреждения
/// в карточке «Доступно сегодня».
final budgetAlertsProvider = Provider<List<CategoryBudgetStatus>>((ref) {
  final now = DateTime.now();
  final statuses = _budgetsFor(ref, DateTime(now.year, now.month)).value;
  return [
    for (final s in statuses ?? const <CategoryBudgetStatus>[])
      if (s.needsAttention) s,
  ];
});

/// Доходы и расходы за [analyticsMonths] месяцев до выбранного.
final monthlyCashflowProvider =
    Provider<AsyncValue<List<MonthlyCashflow>>>((ref) {
  final month = ref.watch(financeSelectedMonthProvider);
  return ref.watch(financeTransactionsProvider).whenData(
        (t) => buildMonthlyCashflow(transactions: t, endMonth: month),
      );
});

/// Чистые активы на конец каждого из [analyticsMonths] месяцев до выбранного.
final netWorthHistoryProvider =
    Provider<AsyncValue<List<NetWorthPoint>>>((ref) {
  final month = ref.watch(financeSelectedMonthProvider);
  final accounts = ref.watch(financeAccountsProvider);
  final transactions = ref.watch(financeTransactionsProvider);
  if (accounts.hasError) {
    return AsyncValue.error(accounts.error!, accounts.stackTrace!);
  }
  if (transactions.hasError) {
    return AsyncValue.error(transactions.error!, transactions.stackTrace!);
  }
  final a = accounts.value;
  final t = transactions.value;
  if (a == null || t == null) return const AsyncValue.loading();
  return AsyncValue.data(
    buildNetWorthHistory(accounts: a, transactions: t, endMonth: month),
  );
});
