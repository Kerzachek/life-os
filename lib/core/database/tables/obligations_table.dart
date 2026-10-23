import 'package:drift/drift.dart';
import 'finance_accounts_table.dart';
import 'finance_categories_table.dart';
import 'syncable_table.dart';

/// Обязательные ежемесячные платежи (аренда, ЖКХ, подписки, кредиты).
///
/// Статус оплаты за месяц не хранится: платёж считается оплаченным, если в
/// месяце есть транзакция с `obligation_id` этого платежа.
@DataClassName('ObligationEntity')
class Obligations extends Table with SyncableTable {
  TextColumn get name => text()();
  RealColumn get amount => real()();

  /// День месяца, до которого нужно заплатить (1–31).
  IntColumn get dueDay => integer().withDefault(const Constant(1))();
  TextColumn get categoryId =>
      text().nullable().references(FinanceCategories, #id)();

  /// Кредит, остаток долга которого уменьшается при оплате.
  @ReferenceName('obligations')
  TextColumn get loanAccountId =>
      text().nullable().references(FinanceAccounts, #id)();

  /// Месяц (первое число), за который платёж пропущен в режиме
  /// администратора: без операции и без списания со счёта.
  DateTimeColumn get skippedMonth => dateTime().nullable()();

  /// Плавающая сумма (ЖКХ, свет, счётчики): сумма к оплате — оценка, а
  /// фактическая вводится при оплате. История оплат — расходы с
  /// `obligation_id` этого платежа.
  BoolColumn get isVariableAmount =>
      boolean().withDefault(const Constant(false))();

  /// Ручной ориентир для плавающего платежа. `null` — оценка считается
  /// медианой прошлых оплат (а без истории берётся [amount]).
  RealColumn get estimatedAmount => real().nullable()();

  /// Счёт списания по умолчанию.
  @ReferenceName('payerObligations')
  TextColumn get accountId =>
      text().nullable().references(FinanceAccounts, #id)();
}
