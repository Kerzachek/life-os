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
  Future<String> createAccount({
    required String name,
    required FinanceAccountKind kind,
    double balance = 0,
    double? targetAmount,
    double? interestRate,
    int? termMonths,
    double? monthlyPayment,
    int? paymentDay,
  }) async {
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
            ),
          );
      await _syncLoanObligation(
        accountId: id,
        kind: kind,
        name: name,
        monthlyPayment: monthlyPayment,
        paymentDay: paymentDay,
      );
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
  }) async {
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
          updatedAt: Value(now),
        ),
      );
      await _syncLoanObligation(
        accountId: id,
        kind: kind,
        name: name,
        monthlyPayment: monthlyPayment,
        paymentDay: paymentDay,
      );
    });
  }

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

  /// Поддерживает обязательный платёж, связанный с кредитом.
  Future<void> _syncLoanObligation({
    required String accountId,
    required FinanceAccountKind kind,
    required String name,
    required double? monthlyPayment,
    required int? paymentDay,
  }) async {
    final now = DateTime.now().toUtc();
    final existing = await (_db.select(_db.obligations)
          ..where(
              (o) => o.loanAccountId.equals(accountId) & o.deletedAt.isNull()))
        .getSingleOrNull();
    final wanted =
        kind == FinanceAccountKind.loan && (monthlyPayment ?? 0) > 0;

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
              amount: monthlyPayment!,
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
        amount: Value(monthlyPayment!),
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
      final target = await _getAccount(targetId);
      final isLoan =
          FinanceAccountKind.fromValue(target.kind) == FinanceAccountKind.loan;
      // Платёж по кредиту уменьшает долг, перевод на счёт/депозит увеличивает.
      await _adjustBalance(targetId, (isLoan ? -sign : sign) * t.amount);
    }
  }

  Future<void> _adjustBalance(String accountId, double delta) async {
    final account = await _getAccount(accountId);
    await (_db.update(_db.financeAccounts)
          ..where((a) => a.id.equals(accountId)))
        .write(FinanceAccountsCompanion(
      balance: Value(roundMoney(account.balance + delta)),
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
  Future<bool> payObligation({
    required String obligationId,
    required String fromAccountId,
    double? amount,
    DateTime? date,
  }) async {
    final when = date ?? DateTime.now();
    final obligation = await (_db.select(_db.obligations)
          ..where((o) => o.id.equals(obligationId)))
        .getSingle();

    final transactions = await getTransactions();
    if (findObligationPayment(obligation, transactions, when) != null) {
      return false;
    }

    final isLoan = obligation.loanAccountId != null;
    await createTransaction(
      type: FinanceTransactionType.expense,
      amount: amount ?? obligation.amount,
      accountId: fromAccountId,
      targetAccountId: obligation.loanAccountId,
      categoryId: isLoan
          ? FinanceCategoryIds.loans
          : (obligation.categoryId ?? FinanceCategoryIds.obligations),
      note: obligation.name,
      date: when,
      obligationId: obligationId,
    );
    return true;
  }

  /// Отменяет оплату обязательного платежа за месяц [date] (по умолчанию —
  /// текущий): удаляет созданную операцию и возвращает баланс. Возвращает
  /// `false`, если оплаты за этот месяц не было.
  Future<bool> undoObligationPayment({
    required String obligationId,
    DateTime? date,
  }) async {
    final obligation = await (_db.select(_db.obligations)
          ..where((o) => o.id.equals(obligationId)))
        .getSingle();
    final payment = findObligationPayment(
      obligation,
      await getTransactions(),
      date ?? DateTime.now(),
    );
    if (payment == null) return false;
    await deleteTransaction(payment.id);
    return true;
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
