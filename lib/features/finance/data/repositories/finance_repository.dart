import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../domain/finance_calculations.dart';
import '../../domain/finance_category_presets.dart';
import '../../domain/finance_enums.dart';

final financeRepositoryProvider = Provider<FinanceRepository>((ref) {
  return FinanceRepository(ref.watch(appDatabaseProvider));
});

/// Округление денежных сумм до копеек (защита от накопления ошибок double).
double roundMoney(double value) => (value * 100).round() / 100;

class FinanceRepository {
  final AppDatabase _db;
  final _uuid = const Uuid();

  FinanceRepository(this._db);

  // ---------------------------------------------------------------- Потоки

  Stream<List<FinanceAccountEntity>> watchAccounts() {
    return (_db.select(_db.financeAccounts)
          ..where((a) => a.deletedAt.isNull())
          ..orderBy([(a) => OrderingTerm.asc(a.createdAt)]))
        .watch();
  }

  Stream<List<FinanceCategoryEntity>> watchCategories() {
    return (_db.select(_db.financeCategories)
          ..where((c) => c.deletedAt.isNull())
          ..orderBy([(c) => OrderingTerm.asc(c.createdAt)]))
        .watch();
  }

  Stream<List<FinanceTransactionEntity>> watchTransactions() {
    return (_db.select(_db.financeTransactions)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm.desc(t.date),
            (t) => OrderingTerm.desc(t.createdAt),
          ]))
        .watch();
  }

  Stream<List<ObligationEntity>> watchObligations() {
    return (_db.select(_db.obligations)
          ..where((o) => o.deletedAt.isNull())
          ..orderBy([
            (o) => OrderingTerm.asc(o.dueDay),
            (o) => OrderingTerm.asc(o.createdAt),
          ]))
        .watch();
  }

  Future<List<FinanceAccountEntity>> getAccounts() {
    return (_db.select(_db.financeAccounts)
          ..where((a) => a.deletedAt.isNull())
          ..orderBy([(a) => OrderingTerm.asc(a.createdAt)]))
        .get();
  }

  Future<List<FinanceTransactionEntity>> getTransactions() {
    return (_db.select(_db.financeTransactions)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.date)]))
        .get();
  }

  Future<List<ObligationEntity>> getObligations() {
    return (_db.select(_db.obligations)..where((o) => o.deletedAt.isNull()))
        .get();
  }

  Future<List<FinanceCategoryEntity>> getCategories() {
    return (_db.select(_db.financeCategories)
          ..where((c) => c.deletedAt.isNull()))
        .get();
  }

  // --------------------------------------------------------------- Продукты

  /// Создаёт счёт / кредит / депозит.
  ///
  /// Для кредита [balance] — текущий остаток долга, [targetAmount] — исходная
  /// сумма задолженности. Если у кредита задан [monthlyPayment], автоматически
  /// создаётся связанный обязательный платёж.
  ///
  /// [isFlexibleSchedule] — рассрочка с плавающим графиком (Сплит, Долями):
  /// вместо [monthlyPayment] / [paymentDay] платёж строится по ближайшему
  /// списанию [nextPaymentDate] / [nextPaymentAmount].
  Future<String> createAccount({
    required String name,
    required FinanceAccountKind kind,
    double balance = 0,
    double? targetAmount,
    double? interestRate,
    int? termMonths,
    double? monthlyPayment,
    int? paymentDay,
    bool isFlexibleSchedule = false,
    DateTime? nextPaymentDate,
    double? nextPaymentAmount,
  }) async {
    final flexible = isFlexibleSchedule && kind == FinanceAccountKind.loan;
    final id = _uuid.v4();
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      await _db.into(_db.financeAccounts).insert(
            FinanceAccountsCompanion.insert(
              id: id,
              createdAt: now,
              updatedAt: now,
              name: name,
              kind: Value(kind.value),
              balance: Value(roundMoney(balance)),
              targetAmount: Value(targetAmount),
              interestRate: Value(interestRate),
              termMonths: Value(termMonths),
              monthlyPayment: Value(monthlyPayment),
              paymentDay: Value(paymentDay),
              isFlexibleSchedule: Value(flexible),
              nextPaymentDate: Value(flexible ? _day(nextPaymentDate) : null),
              nextPaymentAmount: Value(
                  flexible ? _roundOrNull(nextPaymentAmount) : null),
            ),
          );
      await _syncLoanObligation(id);
    });
    return id;
  }

  Future<void> updateAccount({
    required String id,
    required String name,
    required FinanceAccountKind kind,
    required double balance,
    double? targetAmount,
    double? interestRate,
    int? termMonths,
    double? monthlyPayment,
    int? paymentDay,
    bool isFlexibleSchedule = false,
    DateTime? nextPaymentDate,
    double? nextPaymentAmount,
  }) async {
    final flexible = isFlexibleSchedule && kind == FinanceAccountKind.loan;
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      await (_db.update(_db.financeAccounts)..where((a) => a.id.equals(id)))
          .write(
        FinanceAccountsCompanion(
          name: Value(name),
          kind: Value(kind.value),
          balance: Value(roundMoney(balance)),
          targetAmount: Value(targetAmount),
          interestRate: Value(interestRate),
          termMonths: Value(termMonths),
          monthlyPayment: Value(monthlyPayment),
          paymentDay: Value(paymentDay),
          isFlexibleSchedule: Value(flexible),
          nextPaymentDate: Value(flexible ? _day(nextPaymentDate) : null),
          nextPaymentAmount:
              Value(flexible ? _roundOrNull(nextPaymentAmount) : null),
          updatedAt: Value(now),
        ),
      );
      await _syncLoanObligation(id);
    });
  }

  /// Быстрая правка ближайшего списания рассрочки (дата и сумма).
  Future<void> updateNextPayment({
    required String loanId,
    required DateTime date,
    required double amount,
  }) async {
    _validateAmount(amount);
    await _db.transaction(() async {
      await _writeNextPayment(loanId, date, amount);
      await _syncLoanObligation(loanId);
    });
  }

  Future<void> _writeNextPayment(
    String loanId,
    DateTime? date,
    double? amount,
  ) {
    return (_db.update(_db.financeAccounts)..where((a) => a.id.equals(loanId)))
        .write(FinanceAccountsCompanion(
      nextPaymentDate: Value(_day(date)),
      nextPaymentAmount: Value(_roundOrNull(amount)),
      updatedAt: Value(DateTime.now().toUtc()),
    ));
  }

  /// Дата списания без времени (локальная полночь).
  static DateTime? _day(DateTime? date) =>
      date == null ? null : dateOnly(date);

  static double? _roundOrNull(double? value) =>
      value == null ? null : roundMoney(value);

  /// Мягко удаляет продукт вместе с его операциями и связанными платежами.
  ///
  /// Балансы других продуктов, затронутых переводами, не пересчитываются.
  Future<void> deleteAccount(String id) async {
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      await (_db.update(_db.financeAccounts)..where((a) => a.id.equals(id)))
          .write(FinanceAccountsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
      ));
      await (_db.update(_db.financeTransactions)
            ..where((t) =>
                (t.accountId.equals(id) | t.targetAccountId.equals(id)) &
                t.deletedAt.isNull()))
          .write(FinanceTransactionsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
      ));
      await (_db.update(_db.obligations)
            ..where((o) => o.loanAccountId.equals(id) & o.deletedAt.isNull()))
          .write(ObligationsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
      ));
    });
  }

  /// Поддерживает обязательный платёж, связанный с кредитом [accountId]:
  /// по регулярному платежу либо, для рассрочки, по ближайшему списанию.
  Future<void> _syncLoanObligation(String accountId) async {
    final now = DateTime.now().toUtc();
    final account = await _getAccount(accountId);
    final name = account.name;
    final flexible = account.isFlexibleSchedule;
    final amount =
        flexible ? account.nextPaymentAmount : account.monthlyPayment;
    final paymentDay =
        flexible ? account.nextPaymentDate?.toLocal().day : account.paymentDay;
    final existing = await (_db.select(_db.obligations)
          ..where(
              (o) => o.loanAccountId.equals(accountId) & o.deletedAt.isNull()))
        .getSingleOrNull();
    final wanted = account.kind == FinanceAccountKind.loan.value &&
        (amount ?? 0) > 0 &&
        (!flexible || account.nextPaymentDate != null);

    if (!wanted) {
      if (existing != null) {
        await (_db.update(_db.obligations)
              ..where((o) => o.id.equals(existing.id)))
            .write(ObligationsCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
        ));
      }
      return;
    }

    final day = (paymentDay ?? 1).clamp(1, 31);
    if (existing == null) {
      await _db.into(_db.obligations).insert(
            ObligationsCompanion.insert(
              id: _uuid.v4(),
              createdAt: now,
              updatedAt: now,
              name: 'Кредит: $name',
              amount: amount!,
              dueDay: Value(day),
              categoryId: const Value(FinanceCategoryIds.loans),
              loanAccountId: Value(accountId),
            ),
          );
    } else {
      await (_db.update(_db.obligations)
            ..where((o) => o.id.equals(existing.id)))
          .write(ObligationsCompanion(
        name: Value('Кредит: $name'),
        amount: Value(amount!),
        dueDay: Value(day),
        updatedAt: Value(now),
      ));
    }
  }

  // --------------------------------------------------------------- Операции

  /// Создаёт операцию и сразу обновляет балансы затронутых продуктов.
  ///
  /// * расход: списывает с [accountId]; если указан [targetAccountId]-кредит,
  ///   уменьшает остаток долга (платёж по кредиту);
  /// * доход: зачисляет на [accountId];
  /// * перевод: списывает с [accountId] и зачисляет на [targetAccountId]
  ///   (для кредита — уменьшает долг).
  ///
  /// Для кредитных карт знак обратный: трата с карты увеличивает долг, а
  /// перевод на неё (погашение) — уменьшает и восстанавливает лимит.
  Future<String> createTransaction({
    required FinanceTransactionType type,
    required double amount,
    required String accountId,
    String? targetAccountId,
    String? categoryId,
    String? note,
    DateTime? date,
    String? obligationId,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().toUtc();
    final target = _normalizeTarget(type, accountId, targetAccountId);
    _validateAmount(amount);

    await _db.transaction(() async {
      await _db.into(_db.financeTransactions).insert(
            FinanceTransactionsCompanion.insert(
              id: id,
              createdAt: now,
              updatedAt: now,
              date: (date ?? DateTime.now()).toUtc(),
              amount: roundMoney(amount),
              type: Value(type.value),
              accountId: accountId,
              targetAccountId: Value(target),
              categoryId: Value(categoryId),
              note: Value(_cleanNote(note)),
              obligationId: Value(obligationId),
            ),
          );
      await _applyEffect(await _getTransaction(id), revert: false);
    });
    return id;
  }

  /// Редактирует операцию: старое влияние на балансы откатывается,
  /// новое применяется.
  Future<void> updateTransaction({
    required String id,
    required FinanceTransactionType type,
    required double amount,
    required String accountId,
    String? targetAccountId,
    String? categoryId,
    String? note,
    required DateTime date,
  }) async {
    final target = _normalizeTarget(type, accountId, targetAccountId);
    _validateAmount(amount);
    final now = DateTime.now().toUtc();

    await _db.transaction(() async {
      final old = await _getTransaction(id);
      await _applyEffect(old, revert: true);
      await (_db.update(_db.financeTransactions)..where((t) => t.id.equals(id)))
          .write(
        FinanceTransactionsCompanion(
          date: Value(date.toUtc()),
          amount: Value(roundMoney(amount)),
          type: Value(type.value),
          accountId: Value(accountId),
          targetAccountId: Value(target),
          categoryId: Value(categoryId),
          note: Value(_cleanNote(note)),
          updatedAt: Value(now),
        ),
      );
      await _applyEffect(await _getTransaction(id), revert: false);
    });
  }

  /// Мягко удаляет операцию и откатывает её влияние на балансы.
  Future<void> deleteTransaction(String id) async {
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      final old = await _getTransaction(id);
      if (old.deletedAt != null) return;
      await _applyEffect(old, revert: true);
      await (_db.update(_db.financeTransactions)..where((t) => t.id.equals(id)))
          .write(FinanceTransactionsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
      ));
    });
  }

  /// Фиксирует платёж по кредиту: расход со счёта [fromAccountId] и
  /// уменьшение остатка долга [loanId].
  Future<String> recordLoanPayment({
    required String loanId,
    required String fromAccountId,
    required double amount,
    DateTime? date,
    String? note,
  }) async {
    final loan = await _getAccount(loanId);
    if (FinanceAccountKind.fromValue(loan.kind) != FinanceAccountKind.loan) {
      throw ArgumentError('Продукт ${loan.name} не является кредитом');
    }
    return createTransaction(
      type: FinanceTransactionType.expense,
      amount: amount,
      accountId: fromAccountId,
      targetAccountId: loanId,
      categoryId: FinanceCategoryIds.loans,
      note: note ?? 'Платёж по кредиту «${loan.name}»',
      date: date,
    );
  }

  /// Фиксирует пополнение депозита: перевод со счёта [fromAccountId] на
  /// депозит [depositId].
  Future<String> recordDepositTopUp({
    required String depositId,
    required String fromAccountId,
    required double amount,
    DateTime? date,
    String? note,
  }) async {
    final deposit = await _getAccount(depositId);
    if (FinanceAccountKind.fromValue(deposit.kind) !=
        FinanceAccountKind.deposit) {
      throw ArgumentError('Продукт ${deposit.name} не является депозитом');
    }
    return createTransaction(
      type: FinanceTransactionType.transfer,
      amount: amount,
      accountId: fromAccountId,
      targetAccountId: depositId,
      note: note ?? 'Пополнение «${deposit.name}»',
      date: date,
    );
  }

  /// Погашение кредитной карты: перевод со счёта [fromAccountId] на карту
  /// [cardId] уменьшает долг и восстанавливает доступный лимит.
  Future<String> recordCreditCardRepayment({
    required String cardId,
    required String fromAccountId,
    required double amount,
    DateTime? date,
    String? note,
  }) async {
    final card = await _getAccount(cardId);
    if (FinanceAccountKind.fromValue(card.kind) !=
        FinanceAccountKind.creditCard) {
      throw ArgumentError('Продукт ${card.name} не является кредитной картой');
    }
    return createTransaction(
      type: FinanceTransactionType.transfer,
      amount: amount,
      accountId: fromAccountId,
      targetAccountId: cardId,
      note: note ?? 'Погашение «${card.name}»',
      date: date,
    );
  }

  String? _normalizeTarget(
    FinanceTransactionType type,
    String accountId,
    String? targetAccountId,
  ) {
    if (type == FinanceTransactionType.income) return null;
    if (type == FinanceTransactionType.transfer) {
      if (targetAccountId == null) {
        throw ArgumentError('Для перевода нужно указать счёт получателя');
      }
      if (targetAccountId == accountId) {
        throw ArgumentError('Счета перевода должны различаться');
      }
    }
    return targetAccountId;
  }

  void _validateAmount(double amount) {
    if (amount.isNaN || amount.isInfinite || roundMoney(amount) <= 0) {
      throw ArgumentError('Сумма должна быть больше нуля');
    }
  }

  String? _cleanNote(String? note) {
    final trimmed = note?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  Future<FinanceTransactionEntity> _getTransaction(String id) {
    return (_db.select(_db.financeTransactions)..where((t) => t.id.equals(id)))
        .getSingle();
  }

  Future<FinanceAccountEntity> _getAccount(String id) {
    return (_db.select(_db.financeAccounts)..where((a) => a.id.equals(id)))
        .getSingle();
  }

  /// Применяет (или откатывает при [revert]) влияние операции на балансы.
  Future<void> _applyEffect(
    FinanceTransactionEntity t, {
    required bool revert,
  }) async {
    final sign = revert ? -1.0 : 1.0;
    final type = FinanceTransactionType.fromValue(t.type);

    if (type == FinanceTransactionType.income) {
      await _adjustBalance(t.accountId, sign * t.amount);
      return;
    }

    await _adjustBalance(t.accountId, -sign * t.amount);
    final targetId = t.targetAccountId;
    if (targetId != null) {
      await _adjustBalance(targetId, sign * t.amount);
    }
  }

  /// Изменяет деньги на продукте на [delta]. У кредита и кредитки `balance` —
  /// долг, поэтому поступление (платёж, погашение) его уменьшает, а списание
  /// (трата с кредитки) — увеличивает.
  Future<void> _adjustBalance(String accountId, double delta) async {
    final account = await _getAccount(accountId);
    final isLiability = FinanceAccountKind.fromValue(account.kind).isLiability;
    await (_db.update(_db.financeAccounts)
          ..where((a) => a.id.equals(accountId)))
        .write(FinanceAccountsCompanion(
      balance: Value(
          roundMoney(account.balance + (isLiability ? -delta : delta))),
      updatedAt: Value(DateTime.now().toUtc()),
    ));
  }

  // ----------------------------------------------- Обязательные платежи

  Future<String> createObligation({
    required String name,
    required double amount,
    required int dueDay,
    String? categoryId,
    String? loanAccountId,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().toUtc();
    await _db.into(_db.obligations).insert(
          ObligationsCompanion.insert(
            id: id,
            createdAt: now,
            updatedAt: now,
            name: name,
            amount: amount,
            dueDay: Value(dueDay.clamp(1, 31)),
            categoryId: Value(categoryId),
            loanAccountId: Value(loanAccountId),
          ),
        );
    return id;
  }

  Future<void> updateObligation({
    required String id,
    required String name,
    required double amount,
    required int dueDay,
    String? categoryId,
    String? loanAccountId,
  }) async {
    await (_db.update(_db.obligations)..where((o) => o.id.equals(id))).write(
      ObligationsCompanion(
        name: Value(name),
        amount: Value(amount),
        dueDay: Value(dueDay.clamp(1, 31)),
        categoryId: Value(categoryId),
        loanAccountId: Value(loanAccountId),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Future<void> deleteObligation(String id) async {
    final now = DateTime.now().toUtc();
    await (_db.update(_db.obligations)..where((o) => o.id.equals(id))).write(
      ObligationsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }

  /// Оплачивает обязательный платёж за месяц даты [date] (по умолчанию —
  /// текущий). Возвращает `false`, если платёж за этот месяц уже оплачен.
  ///
  /// Если платёж связан с кредитом, уменьшается остаток долга.
  ///
  /// Для рассрочки с плавающим графиком доли можно оплачивать несколько раз
  /// в месяц. После оплаты ближайшее списание сдвигается на
  /// [nextPaymentDate] / [nextPaymentAmount] (по умолчанию — подсказка
  /// [suggestNextFlexiblePayment]); если долг закрыт, оно сбрасывается.
  Future<bool> payObligation({
    required String obligationId,
    required String fromAccountId,
    double? amount,
    DateTime? date,
    DateTime? nextPaymentDate,
    double? nextPaymentAmount,
  }) async {
    final when = date ?? DateTime.now();
    final obligation = await (_db.select(_db.obligations)
          ..where((o) => o.id.equals(obligationId)))
        .getSingle();
    final loanId = obligation.loanAccountId;
    final loan = loanId == null ? null : await _getAccount(loanId);
    final flexible = loan?.isFlexibleSchedule ?? false;

    final transactions = await getTransactions();
    if (!flexible &&
        findObligationPayment(obligation, transactions, when) != null) {
      return false;
    }

    final paid = amount ??
        (flexible ? loan!.nextPaymentAmount : null) ??
        obligation.amount;
    await _db.transaction(() async {
      await createTransaction(
        type: FinanceTransactionType.expense,
        amount: paid,
        accountId: fromAccountId,
        targetAccountId: loanId,
        categoryId: loanId != null
            ? FinanceCategoryIds.loans
            : (obligation.categoryId ?? FinanceCategoryIds.obligations),
        note: obligation.name,
        date: when,
        obligationId: obligationId,
      );
      if (!flexible) return;

      final suggested = suggestNextFlexiblePayment(
        loan: loan!,
        paidAmount: paid,
        now: when,
      );
      if (suggested == null) {
        // Долг закрыт: платёж остаётся оплаченным в этом месяце, новых нет.
        await _writeNextPayment(loan.id, null, null);
        return;
      }
      final remaining = loanBalanceAfter(loan, paid);
      final nextAmount = nextPaymentAmount ?? suggested.amount;
      await _writeNextPayment(
        loan.id,
        nextPaymentDate ?? suggested.date,
        nextAmount > remaining ? remaining : nextAmount,
      );
      await _syncLoanObligation(loan.id);
    });
    return true;
  }

  /// Отменяет оплату обязательного платежа за месяц [date] (по умолчанию —
  /// текущий): удаляет созданную операцию и возвращает баланс. Возвращает
  /// `false`, если оплаты за этот месяц не было.
  ///
  /// Для рассрочки отменяется последняя оплата, а ближайшим списанием снова
  /// становится она сама (её дата и сумма).
  Future<bool> undoObligationPayment({
    required String obligationId,
    DateTime? date,
  }) async {
    final obligation = await (_db.select(_db.obligations)
          ..where((o) => o.id.equals(obligationId)))
        .getSingle();
    // Операции упорядочены по убыванию даты: найдётся последняя оплата.
    final payment = findObligationPayment(
      obligation,
      await getTransactions(),
      date ?? DateTime.now(),
    );
    if (payment == null) return false;
    final loanId = obligation.loanAccountId;
    final loan = loanId == null ? null : await _getAccount(loanId);
    await _db.transaction(() async {
      await deleteTransaction(payment.id);
      if (loan == null || !loan.isFlexibleSchedule) return;
      await _writeNextPayment(loan.id, payment.date, payment.amount);
      await _syncLoanObligation(loan.id);
    });
    return true;
  }

  /// Пропускает обязательный платёж за месяц [date] (по умолчанию —
  /// текущий) в режиме администратора: операция не создаётся, балансы
  /// не меняются. Возвращает `false`, если пропускать нечего.
  ///
  /// Ежемесячный платёж помечается пропущенным за этот месяц — следующий
  /// срок наступит в следующем месяце. У рассрочки ближайшее списание
  /// сдвигается на следующий шаг графика с прежней суммой.
  Future<bool> skipObligation({
    required String obligationId,
    DateTime? date,
  }) async {
    final when = date ?? DateTime.now();
    final obligation = await (_db.select(_db.obligations)
          ..where((o) => o.id.equals(obligationId)))
        .getSingle();
    final loanId = obligation.loanAccountId;
    final loan = loanId == null ? null : await _getAccount(loanId);

    if (loan != null && loan.isFlexibleSchedule) {
      final next = suggestNextFlexiblePayment(
        loan: loan,
        paidAmount: 0,
        now: when,
      );
      if (next == null || loan.nextPaymentDate == null) return false;
      await _db.transaction(() async {
        await _writeNextPayment(loan.id, next.date, next.amount);
        await _syncLoanObligation(loan.id);
      });
      return true;
    }

    if (findObligationPayment(obligation, await getTransactions(), when) !=
            null ||
        isObligationSkipped(obligation, when)) {
      return false;
    }
    await (_db.update(_db.obligations)..where((o) => o.id.equals(obligationId)))
        .write(ObligationsCompanion(
      skippedMonth: Value(DateTime(when.year, when.month)),
      updatedAt: Value(DateTime.now().toUtc()),
    ));
    return true;
  }

  /// Снимает отметку о пропуске ежемесячного платежа: он снова к оплате.
  Future<void> undoSkipObligation(String obligationId) async {
    await (_db.update(_db.obligations)..where((o) => o.id.equals(obligationId)))
        .write(ObligationsCompanion(
      skippedMonth: const Value(null),
      updatedAt: Value(DateTime.now().toUtc()),
    ));
  }

  // -------------------------------------------------------------- Категории

  Future<String> createCategory({
    required String name,
    required String iconKey,
    required String colorHex,
    bool isIncome = false,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().toUtc();
    await _db.into(_db.financeCategories).insert(
          FinanceCategoriesCompanion.insert(
            id: id,
            createdAt: now,
            updatedAt: now,
            name: name,
            color: colorHex,
            icon: Value(iconKey),
            isIncome: Value(isIncome),
          ),
        );
    return id;
  }

  Future<void> updateCategory({
    required String id,
    required String name,
    required String iconKey,
    required String colorHex,
  }) async {
    await (_db.update(_db.financeCategories)..where((c) => c.id.equals(id)))
        .write(
      FinanceCategoriesCompanion(
        name: Value(name),
        icon: Value(iconKey),
        color: Value(colorHex),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  /// Удаляет пользовательскую категорию; операции и платежи с ней остаются
  /// без категории. Предустановленные категории удалить нельзя (`false`).
  Future<bool> deleteCategory(String id) async {
    final category = await (_db.select(_db.financeCategories)
          ..where((c) => c.id.equals(id)))
        .getSingleOrNull();
    if (category == null || category.isSystem) return false;

    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      await (_db.update(_db.financeTransactions)
            ..where((t) => t.categoryId.equals(id)))
          .write(const FinanceTransactionsCompanion(categoryId: Value(null)));
      await (_db.update(_db.obligations)..where((o) => o.categoryId.equals(id)))
          .write(const ObligationsCompanion(categoryId: Value(null)));
      await (_db.update(_db.financeCategories)..where((c) => c.id.equals(id)))
          .write(FinanceCategoriesCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
      ));
    });
    return true;
  }
}
