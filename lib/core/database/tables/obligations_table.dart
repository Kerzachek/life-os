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
}
