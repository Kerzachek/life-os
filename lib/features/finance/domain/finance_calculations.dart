import 'dart:math' as math;

import '../../../core/database/app_database.dart';
import 'finance_category_presets.dart';
import 'finance_enums.dart';

/// Кредитная карта / Сплит-лимит: долг хранится в `balance`, лимит — в
/// `targetAmount` (см. `FinanceAccounts`).
extension FinanceCreditLine on FinanceAccountEntity {
  bool get isCreditCard => kind == FinanceAccountKind.creditCard.value;

  /// Общий лимит кредитной линии.
  double get creditLimit => targetAmount ?? 0;

  /// Использованная часть лимита (долг). Отрицательная — переплата.
  double get currentDebt => balance;

  /// Сколько ещё можно потратить.
  double get availableLimit =>
      (creditLimit - currentDebt).clamp(0.0, math.max(0.0, creditLimit));

  /// Доля использованного лимита (0..1).
  double get debtRatio =>
      creditLimit <= 0 ? 0 : (currentDebt / creditLimit).clamp(0.0, 1.0);
}

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

  /// Суммарный остаток долга по кредитам и кредитным картам.
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

  /// Пропущен за месяц в режиме администратора (без списания).
  skipped,
}

/// Обязательный платёж со статусом оплаты за месяц.
class ObligationStatus {
  const ObligationStatus({
    required this.obligation,
    required this.isPaid,
    this.paidAmount,
    this.urgency = ObligationUrgency.scheduled,
    this.daysUntilDue = 0,
    this.dueDate,
    this.dueAmount,
    this.isFlexible = false,
    this.isSkipped = false,
  });

  final ObligationEntity obligation;
  final bool isPaid;

  /// Период пропущен в режиме администратора: платить в этом месяце не
  /// нужно, но и оплаченным платёж не считается.
  final bool isSkipped;

  /// Фактически уплаченная сумма (если оплачен).
  final double? paidAmount;

  final ObligationUrgency urgency;

  /// Дней до срока оплаты (отрицательное — просрочка).
  final int daysUntilDue;

  /// Дата срока оплаты (локальная полночь).
  final DateTime? dueDate;

  /// Сумма к оплате, если она отличается от шаблона платежа.
  final double? dueAmount;

  /// Платёж по рассрочке с плавающим графиком (Сплит, Долями): срок и сумма
  /// берутся из ближайшего списания кредита.
  final bool isFlexible;

  /// Сумма к оплате. Для плавающего платежа до оплаты — оценка
  /// ([obligationEstimate]), после — фактически уплаченная сумма.
  double get amount => dueAmount ?? obligation.amount;

  /// Платёж с плавающей суммой (ЖКХ, свет): фактическая сумма вводится
  /// при оплате.
  bool get isVariable => obligation.isVariableAmount && !isFlexible;

  /// Платёж ещё предстоит оплатить в этом месяце.
  bool get isOutstanding => !isPaid && !isSkipped;

  /// Платёж требует внимания: срок близко, наступил или прошёл.
  bool get needsAttention =>
      urgency == ObligationUrgency.upcoming ||
      urgency == ObligationUrgency.dueToday ||
      urgency == ObligationUrgency.overdue;
}

/// Дней от [now] до срока платежа в месяце [month]. Если в месяце нет
/// указанного числа (например, 31-го), срок — последний день месяца.
int daysUntilObligationDue(int dueDay, DateTime month, DateTime now) {
  return daysBetween(now, obligationDueDate(dueDay, month));
}

/// Срок платежа с днём [dueDay] в месяце [month] (не позже последнего дня).
DateTime obligationDueDate(int dueDay, DateTime month) {
  final lastDay = DateTime.utc(month.year, month.month + 1, 0).day;
  return DateTime(month.year, month.month, dueDay.clamp(1, lastDay));
}

/// Дата без времени в локальной зоне.
DateTime dateOnly(DateTime date) {
  final d = date.toLocal();
  return DateTime(d.year, d.month, d.day);
}

/// Целых календарных дней от [from] до [to] (без влияния перевода часов).
int daysBetween(DateTime from, DateTime to) {
  final a = from.toLocal();
  final b = to.toLocal();
  return DateTime.utc(b.year, b.month, b.day)
      .difference(DateTime.utc(a.year, a.month, a.day))
      .inDays;
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

/// Сколько последних оплат учитывается в медиане плавающего платежа.
const int variableEstimateWindow = 6;

/// Прошлые оплаты [obligation] (расходы с её `obligation_id`), от новых к
/// старым.
List<FinanceTransactionEntity> obligationPaymentHistory(
  ObligationEntity obligation,
  Iterable<FinanceTransactionEntity> transactions,
) {
  return transactions
      .where((t) =>
          t.deletedAt == null &&
          isExpense(t) &&
          t.obligationId == obligation.id)
      .toList()
    ..sort((a, b) => b.date.compareTo(a.date));
}

/// Медиана [values]; `null` для пустого списка.
double? median(Iterable<double> values) {
  final sorted = values.toList()..sort();
  if (sorted.isEmpty) return null;
  final mid = sorted.length ~/ 2;
  final value = sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
  return (value * 100).round() / 100;
}

/// Медиана последних [variableEstimateWindow] оплат [obligation]; `null`,
/// если оплат ещё не было.
double? obligationMedianPayment(
  ObligationEntity obligation,
  Iterable<FinanceTransactionEntity> transactions,
) {
  return median(obligationPaymentHistory(obligation, transactions)
      .take(variableEstimateWindow)
      .map((t) => t.amount));
}

/// Оценка суммы плавающего платежа для планирования: ручной ориентир
/// (`estimatedAmount`), иначе медиана прошлых оплат, иначе сумма шаблона.
double obligationEstimate(
  ObligationEntity obligation,
  Iterable<FinanceTransactionEntity> transactions,
) {
  return obligation.estimatedAmount ??
      obligationMedianPayment(obligation, transactions) ??
      obligation.amount;
}

/// Пропущен ли платёж [obligation] за [month] в режиме администратора.
bool isObligationSkipped(ObligationEntity obligation, DateTime month) {
  final skipped = obligation.skippedMonth;
  return skipped != null && _sameMonth(skipped, month);
}

/// Статусы обязательных платежей за [month], упорядоченные: сначала
/// неоплаченные по сроку, затем оплаченные. [now] — «сегодня» (для тестов).
///
/// [accounts] нужны для кредитов с плавающим графиком: их платёж строится
/// по `nextPaymentDate` / `nextPaymentAmount` (см. [flexibleObligationStatus]).
List<ObligationStatus> buildObligationStatuses(
  Iterable<ObligationEntity> obligations,
  Iterable<FinanceTransactionEntity> transactions,
  DateTime month, {
  DateTime? now,
  Iterable<FinanceAccountEntity> accounts = const [],
}) {
  final txs = transactions.toList();
  final today = now ?? DateTime.now();
  final loans = {for (final a in accounts) a.id: a};
  final result = <ObligationStatus>[];
  for (final o in obligations) {
    if (o.deletedAt != null) continue;
    final payment = findObligationPayment(o, txs, month);
    final loan = loans[o.loanAccountId];
    if (loan != null && loan.isFlexibleSchedule) {
      final status =
          flexibleObligationStatus(o, loan, payment, month, today);
      if (status != null) result.add(status);
      continue;
    }
    final days = daysUntilObligationDue(o.dueDay, month, today);
    final skipped = payment == null && isObligationSkipped(o, month);
    // Плавающий платёж: до оплаты — оценка, после — фактическая сумма.
    final dueAmount = !o.isVariableAmount
        ? null
        : payment?.amount ?? obligationEstimate(o, txs);
    if (skipped) {
      result.add(ObligationStatus(
        obligation: o,
        isPaid: false,
        isSkipped: true,
        daysUntilDue: days,
        dueDate: obligationDueDate(o.dueDay, month),
        dueAmount: dueAmount,
        urgency: ObligationUrgency.skipped,
      ));
      continue;
    }
    result.add(ObligationStatus(
      obligation: o,
      isPaid: payment != null,
      paidAmount: payment?.amount,
      dueAmount: dueAmount,
      daysUntilDue: days,
      dueDate: obligationDueDate(o.dueDay, month),
      urgency: obligationUrgency(
        isPaid: payment != null,
        daysUntilDue: days,
      ),
    ));
  }
  result.sort((a, b) {
    if (a.isOutstanding != b.isOutstanding) return a.isOutstanding ? -1 : 1;
    final byDate = a.dueDate != null && b.dueDate != null
        ? a.dueDate!.compareTo(b.dueDate!)
        : a.obligation.dueDay.compareTo(b.obligation.dueDay);
    return byDate != 0
        ? byDate
        : a.obligation.name.compareTo(b.obligation.name);
  });
  return result;
}

/// Статус платежа по рассрочке с плавающим графиком за [month].
///
/// * Ближайшее списание в этом месяце (или раньше — просрочка, или в пределах
///   [obligationUpcomingDays] дней в начале следующего) — платёж к оплате,
///   даже если в месяце уже была оплата предыдущей доли.
/// * Иначе платёж показывается оплаченным, если в месяце была оплата.
/// * `null` — в этом месяце по рассрочке платить нечего (или долг закрыт).
ObligationStatus? flexibleObligationStatus(
  ObligationEntity obligation,
  FinanceAccountEntity loan,
  FinanceTransactionEntity? payment,
  DateTime month,
  DateTime now,
) {
  final next = loan.nextPaymentDate;
  if (next != null) {
    final due = dateOnly(next);
    final days = daysBetween(now, due);
    final monthEnd = DateTime(month.year, month.month + 1, 0);
    if (!due.isAfter(monthEnd) || days <= obligationUpcomingDays) {
      return ObligationStatus(
        obligation: obligation,
        isPaid: false,
        daysUntilDue: days,
        dueDate: due,
        dueAmount: loan.nextPaymentAmount,
        isFlexible: true,
        urgency: obligationUrgency(isPaid: false, daysUntilDue: days),
      );
    }
  }
  if (payment == null) return null;
  return ObligationStatus(
    obligation: obligation,
    isPaid: true,
    paidAmount: payment.amount,
    dueDate: dateOnly(payment.date),
    dueAmount: payment.amount,
    isFlexible: true,
    urgency: ObligationUrgency.paid,
  );
}

/// Шаг графика рассрочек по умолчанию (Сплит, Долями — раз в две недели).
const int flexiblePaymentStepDays = 14;

/// Ближайшее списание по рассрочке.
class FlexiblePaymentStep {
  const FlexiblePaymentStep({required this.date, required this.amount});

  final DateTime date;
  final double amount;
}

/// Остаток долга [loan] после оплаты [paidAmount] (не меньше нуля).
double loanBalanceAfter(FinanceAccountEntity loan, double paidAmount) =>
    math.max(0.0, ((loan.balance - paidAmount) * 100).round() / 100);

/// Предлагает следующее списание рассрочки [loan] после оплаты [paidAmount]:
/// через [flexiblePaymentStepDays] дней после оплаченного срока (но не
/// раньше чем через столько же дней от [now]), сумма — прежняя доля, но не
/// больше остатка долга. `null` — долг закрыт.
FlexiblePaymentStep? suggestNextFlexiblePayment({
  required FinanceAccountEntity loan,
  required double paidAmount,
  required DateTime now,
}) {
  final remaining = loanBalanceAfter(loan, paidAmount);
  if (remaining <= 0) return null;
  final today = dateOnly(now);
  final base = loan.nextPaymentDate == null
      ? today
      : dateOnly(loan.nextPaymentDate!);
  var date = DateTime(base.year, base.month, base.day + flexiblePaymentStepDays);
  if (!date.isAfter(today)) {
    date = DateTime(today.year, today.month, today.day + flexiblePaymentStepDays);
  }
  final share = loan.nextPaymentAmount ?? paidAmount;
  return FlexiblePaymentStep(date: date, amount: math.min(share, remaining));
}

FinanceSummary buildSummary({
  required Iterable<FinanceAccountEntity> accounts,
  required List<ObligationStatus> obligations,
}) {
  double sumOf(FinanceAccountKind kind) => accounts
      .where((a) => a.deletedAt == null && a.kind == kind.value)
      .fold(0.0, (sum, a) => sum + a.balance);

  // Пропущенные платежи в этом месяце не нужны — их нет ни в сумме, ни в долге.
  final total = obligations
      .where((o) => !o.isSkipped)
      .fold(0.0, (s, o) => s + o.amount);
  final paid = obligations
      .where((o) => o.isPaid)
      .fold(0.0, (s, o) => s + (o.paidAmount ?? o.amount));
  final unpaid = obligations
      .where((o) => o.isOutstanding)
      .fold(0.0, (s, o) => s + o.amount);
  final balance = sumOf(FinanceAccountKind.account);
  // Переплата по кредитке (отрицательный долг) не уменьшает другие долги.
  final cardDebt = accounts
      .where((a) => a.deletedAt == null && a.isCreditCard)
      .fold(0.0, (sum, a) => sum + math.max(0.0, a.currentDebt));

  return FinanceSummary(
    totalBalance: balance,
    totalDebt: sumOf(FinanceAccountKind.loan) + cardDebt,
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
    this.creditCardDebt = 0,
  });

  /// Деньги на обычных счетах (без депозитов/копилок и тел кредитов) за
  /// вычетом [creditCardDebt].
  final double liquidBalance;

  /// Долг по кредитным картам, учтённый в [liquidBalance] (0, если кредитки
  /// в расчёте не участвуют).
  final double creditCardDebt;

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
///
/// [includeCreditCards] — учитывать кредитные карты: траты с них входят в
/// сегодняшние расходы, а долг по ним вычитается из свободных денег (его
/// придётся гасить со счёта). Так покупка по кредитке уменьшает «Доступно»
/// так же, как покупка с дебетовой карты, а её погашение бюджет не меняет.
/// Если выключено, кредитки в расчёте не участвуют вовсе.
DailySafeBudgetState buildDailySafeBudget({
  required Iterable<FinanceAccountEntity> accounts,
  required Iterable<ObligationStatus> obligations,
  required Iterable<FinanceTransactionEntity> transactions,
  required DateTime now,
  bool includeCreditCards = true,
}) {
  final active = accounts.where((a) => a.deletedAt == null);
  final cash = active
      .where((a) => a.kind == FinanceAccountKind.account.value)
      .fold(0.0, (sum, a) => sum + a.balance);
  final cards = active.where((a) => a.isCreditCard).toList();
  final cardIds = {for (final a in cards) a.id};
  final cardDebt = includeCreditCards
      ? cards.fold(0.0, (sum, a) => sum + a.currentDebt)
      : 0.0;

  final unpaid = obligations
      .where((o) => o.isOutstanding)
      .fold(0.0, (sum, o) => sum + o.amount);

  final spentToday = transactions.where((t) {
    if (!isDailyExpense(t)) return false;
    if (!includeCreditCards && cardIds.contains(t.accountId)) return false;
    final d = t.date.toLocal();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }).fold(0.0, (sum, t) => sum + t.amount);

  return DailySafeBudgetState(
    liquidBalance: cash - cardDebt,
    unpaidObligations: unpaid,
    spentToday: spentToday,
    daysRemaining: daysRemainingInMonth(now),
    creditCardDebt: cardDebt,
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
