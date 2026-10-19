import 'dart:math' as math;

import '../../../core/database/app_database.dart';
import 'finance_category_presets.dart';
import 'finance_enums.dart';

/// Сводка для карточек обзора.
class FinanceSummary {
  const FinanceSummary({
    required this.totalBalance,
    required this.totalDebt,
    required this.totalDeposits,
    required this.obligationsTotal,
    required this.obligationsPaid,
    required this.leftToLive,
  });

  /// Деньги на обычных счетах.
  final double totalBalance;

  /// Суммарный остаток долга по кредитам.
  final double totalDebt;

  /// Отложено в депозитах и копилках.
  final double totalDeposits;

  /// Сумма всех обязательных платежей месяца (необходимая в начале периода).
  final double obligationsTotal;

  /// Уже оплачено из обязательных платежей.
  final double obligationsPaid;

  /// Остаток на счетах после ещё не оплаченных обязательных платежей.
  final double leftToLive;

  double get obligationsRemaining => obligationsTotal - obligationsPaid;

  /// Доля оплаченных обязательных платежей (0..1).
  double get obligationsProgress =>
      obligationsTotal <= 0 ? 0 : (obligationsPaid / obligationsTotal).clamp(0, 1);
}

/// За сколько дней до срока платёж считается «предстоящим».
const int obligationUpcomingDays = 2;

/// Срочность обязательного платежа в расчётном месяце.
enum ObligationUrgency {
  /// Срок ещё далеко.
  scheduled,

  /// До срока осталось не более [obligationUpcomingDays] дней.
  upcoming,

  /// Срок наступил сегодня.
  dueToday,

  /// Срок прошёл, а платёж не оплачен.
  overdue,

  /// Оплачен за месяц.
  paid,
}

/// Обязательный платёж со статусом оплаты за месяц.
class ObligationStatus {
  const ObligationStatus({
    required this.obligation,
    required this.isPaid,
    this.paidAmount,
    this.urgency = ObligationUrgency.scheduled,
    this.daysUntilDue = 0,
  });

  final ObligationEntity obligation;
  final bool isPaid;

  /// Фактически уплаченная сумма (если оплачен).
  final double? paidAmount;

  final ObligationUrgency urgency;

  /// Дней до срока оплаты (отрицательное — просрочка).
  final int daysUntilDue;

  /// Платёж требует внимания: срок близко, наступил или прошёл.
  bool get needsAttention =>
      urgency == ObligationUrgency.upcoming ||
      urgency == ObligationUrgency.dueToday ||
      urgency == ObligationUrgency.overdue;
}

/// Дней от [now] до срока платежа в месяце [month]. Если в месяце нет
/// указанного числа (например, 31-го), срок — последний день месяца.
int daysUntilObligationDue(int dueDay, DateTime month, DateTime now) {
  final lastDay = DateTime.utc(month.year, month.month + 1, 0).day;
  final due = DateTime.utc(month.year, month.month, dueDay.clamp(1, lastDay));
  final today = DateTime.utc(now.year, now.month, now.day);
  return due.difference(today).inDays;
}

ObligationUrgency obligationUrgency({
  required bool isPaid,
  required int daysUntilDue,
}) {
  if (isPaid) return ObligationUrgency.paid;
  if (daysUntilDue < 0) return ObligationUrgency.overdue;
  if (daysUntilDue == 0) return ObligationUrgency.dueToday;
  if (daysUntilDue <= obligationUpcomingDays) return ObligationUrgency.upcoming;
  return ObligationUrgency.scheduled;
}

/// Один сегмент диаграммы расходов.
class CategoryExpense {
  const CategoryExpense({
    required this.categoryId,
    required this.name,
    required this.colorHex,
    required this.amount,
  });

  /// `null` — расходы без категории.
  final String? categoryId;
  final String name;
  final String colorHex;
  final double amount;
}

bool _sameMonth(DateTime date, DateTime month) {
  final d = date.toLocal();
  return d.year == month.year && d.month == month.month;
}

bool isExpense(FinanceTransactionEntity t) =>
    FinanceTransactionType.fromValue(t.type) == FinanceTransactionType.expense;

/// Платёж считается оплаченным за [month], если есть расход, привязанный к
/// нему напрямую (`obligation_id`) либо — для кредитных платежей — расход,
/// погашающий связанный кредит.
FinanceTransactionEntity? findObligationPayment(
  ObligationEntity obligation,
  Iterable<FinanceTransactionEntity> transactions,
  DateTime month,
) {
  for (final t in transactions) {
    if (t.deletedAt != null || !_sameMonth(t.date, month)) continue;
    if (t.obligationId == obligation.id) return t;
    if (obligation.loanAccountId != null &&
        isExpense(t) &&
        t.targetAccountId == obligation.loanAccountId) {
      return t;
    }
  }
  return null;
}

/// Статусы обязательных платежей за [month], упорядоченные: сначала
/// неоплаченные по сроку, затем оплаченные. [now] — «сегодня» (для тестов).
List<ObligationStatus> buildObligationStatuses(
  Iterable<ObligationEntity> obligations,
  Iterable<FinanceTransactionEntity> transactions,
  DateTime month, {
  DateTime? now,
}) {
  final txs = transactions.toList();
  final today = now ?? DateTime.now();
  final result = [
    for (final o in obligations)
      if (o.deletedAt == null)
        () {
          final payment = findObligationPayment(o, txs, month);
          final days = daysUntilObligationDue(o.dueDay, month, today);
          return ObligationStatus(
            obligation: o,
            isPaid: payment != null,
            paidAmount: payment?.amount,
            daysUntilDue: days,
            urgency: obligationUrgency(
              isPaid: payment != null,
              daysUntilDue: days,
            ),
          );
        }(),
  ];
  result.sort((a, b) {
    if (a.isPaid != b.isPaid) return a.isPaid ? 1 : -1;
    final byDay = a.obligation.dueDay.compareTo(b.obligation.dueDay);
    return byDay != 0 ? byDay : a.obligation.name.compareTo(b.obligation.name);
  });
  return result;
}

FinanceSummary buildSummary({
  required Iterable<FinanceAccountEntity> accounts,
  required List<ObligationStatus> obligations,
}) {
  double sumOf(FinanceAccountKind kind) => accounts
      .where((a) => a.deletedAt == null && a.kind == kind.value)
      .fold(0.0, (sum, a) => sum + a.balance);

  final total = obligations.fold(0.0, (s, o) => s + o.obligation.amount);
  final paid = obligations
      .where((o) => o.isPaid)
      .fold(0.0, (s, o) => s + (o.paidAmount ?? o.obligation.amount));
  final unpaid = obligations
      .where((o) => !o.isPaid)
      .fold(0.0, (s, o) => s + o.obligation.amount);
  final balance = sumOf(FinanceAccountKind.account);

  return FinanceSummary(
    totalBalance: balance,
    totalDebt: sumOf(FinanceAccountKind.loan),
    totalDeposits: sumOf(FinanceAccountKind.deposit),
    obligationsTotal: total,
    obligationsPaid: paid,
    leftToLive: balance - unpaid,
  );
}

/// Результат расчёта «Свободного дневного бюджета» (Safe-to-Spend).
class DailySafeBudgetState {
  const DailySafeBudgetState({
    required this.liquidBalance,
    required this.unpaidObligations,
    required this.spentToday,
    required this.daysRemaining,
  });

  /// Деньги на обычных счетах (без депозитов/копилок и тел кредитов).
  final double liquidBalance;

  /// Ещё не оплаченные обязательные платежи и взносы по кредитам месяца.
  final double unpaidObligations;

  /// Повседневные траты за сегодня (без обязательных платежей, кредитов
  /// и переводов на депозиты).
  final double spentToday;

  /// Дней до конца месяца, включая сегодняшний (минимум 1).
  final int daysRemaining;

  /// Свободный пул на начало сегодняшнего дня: сегодняшние траты возвращаются
  /// в пул, чтобы вычитаться ровно из сегодняшней нормы.
  double get freePoolAtStartOfDay =>
      (liquidBalance + spentToday) - unpaidObligations;

  /// Норма на день (не меньше нуля).
  double get dailyAllowance =>
      math.max(0.0, freePoolAtStartOfDay / daysRemaining);

  /// Осталось на сегодня (отрицательное — перерасход).
  double get remainingToday => dailyAllowance - spentToday;

  /// Текущий свободный остаток до конца месяца.
  double get freePoolTotal => liquidBalance - unpaidObligations;

  /// Перерасход за сегодня.
  bool get isOverspent => remainingToday < 0;

  /// Доля потраченного от дневной нормы (не ограничена сверху).
  /// При нулевой норме: 0, если трат нет, иначе 1.
  double get spentRatio {
    if (dailyAllowance <= 0) return spentToday > 0 ? 1.0 : 0.0;
    return math.max(0.0, spentToday / dailyAllowance);
  }
}

/// Повседневный ли это расход: не оплата обязательного платежа, не платёж
/// по кредиту и не перевод (переводы на депозиты — не расходы).
bool isDailyExpense(FinanceTransactionEntity t) {
  if (t.deletedAt != null || !isExpense(t)) return false;
  if (t.obligationId != null || t.targetAccountId != null) return false;
  return t.categoryId != FinanceCategoryIds.loans &&
      t.categoryId != FinanceCategoryIds.obligations;
}

/// Количество дней до конца месяца [now], включая сегодняшний (минимум 1).
int daysRemainingInMonth(DateTime now) {
  final lastDay = DateTime.utc(now.year, now.month + 1, 0).day;
  return math.max(1, lastDay - now.day + 1);
}

/// Считает «Свободный дневной бюджет» на момент [now].
///
/// [obligations] — статусы обязательных платежей текущего месяца.
DailySafeBudgetState buildDailySafeBudget({
  required Iterable<FinanceAccountEntity> accounts,
  required Iterable<ObligationStatus> obligations,
  required Iterable<FinanceTransactionEntity> transactions,
  required DateTime now,
}) {
  final liquid = accounts
      .where((a) =>
          a.deletedAt == null && a.kind == FinanceAccountKind.account.value)
      .fold(0.0, (sum, a) => sum + a.balance);

  final unpaid = obligations
      .where((o) => !o.isPaid)
      .fold(0.0, (sum, o) => sum + o.obligation.amount);

  final spentToday = transactions.where((t) {
    if (!isDailyExpense(t)) return false;
    final d = t.date.toLocal();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }).fold(0.0, (sum, t) => sum + t.amount);

  return DailySafeBudgetState(
    liquidBalance: liquid,
    unpaidObligations: unpaid,
    spentToday: spentToday,
    daysRemaining: daysRemainingInMonth(now),
  );
}

/// Расходы за месяц, сгруппированные по категориям (по убыванию суммы).
/// Переводы и доходы не учитываются.
List<CategoryExpense> buildExpenseBreakdown({
  required Iterable<FinanceTransactionEntity> transactions,
  required Iterable<FinanceCategoryEntity> categories,
  required DateTime month,
}) {
  final byId = {for (final c in categories) c.id: c};
  final sums = <String?, double>{};
  for (final t in transactions) {
    if (t.deletedAt != null || !isExpense(t) || !_sameMonth(t.date, month)) {
      continue;
    }
    final key = byId.containsKey(t.categoryId) ? t.categoryId : null;
    sums[key] = (sums[key] ?? 0) + t.amount;
  }
  final result = [
    for (final e in sums.entries)
      CategoryExpense(
        categoryId: e.key,
        name: byId[e.key]?.name ?? 'Без категории',
        colorHex: byId[e.key]?.color ?? '#FF8B949E',
        amount: e.value,
      ),
  ]..sort((a, b) => b.amount.compareTo(a.amount));
  return result;
}

/// Параметры фильтра ленты операций.
class TransactionFilter {
  const TransactionFilter({
    this.period = FinancePeriod.month,
    this.type,
    this.categoryId,
    this.query = '',
  });

  final FinancePeriod period;
  final FinanceTransactionType? type;
  final String? categoryId;
  final String query;

  bool matches(FinanceTransactionEntity t, DateTime now) {
    if (!period.contains(t.date, now)) return false;
    if (type != null && t.type != type!.value) return false;
    if (categoryId != null && t.categoryId != categoryId) return false;
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty && !(t.note?.toLowerCase().contains(q) ?? false)) {
      return false;
    }
    return true;
  }
}
