import 'package:drift/drift.dart';
import 'finance_accounts_table.dart';
import 'finance_categories_table.dart';
import 'obligations_table.dart';
import 'syncable_table.dart';

/// Операции: расход (0), доход (1), перевод (2).
///
/// [amount] всегда положительная. [accountId] — счёт-источник (для дохода —
/// счёт зачисления), [targetAccountId] — кредит (погашение) или депозит /
/// другой счёт (перевод).
@DataClassName('FinanceTransactionEntity')
class FinanceTransactions extends Table with SyncableTable {
  DateTimeColumn get date => dateTime()();
  RealColumn get amount => real()();
  IntColumn get type => integer().withDefault(const Constant(0))();
  TextColumn get accountId => text().references(FinanceAccounts, #id)();
  @ReferenceName('incomingTransactions')
  TextColumn get targetAccountId =>
      text().nullable().references(FinanceAccounts, #id)();
  TextColumn get categoryId =>
      text().nullable().references(FinanceCategories, #id)();
  TextColumn get note => text().nullable()();
  TextColumn get obligationId =>
      text().nullable().references(Obligations, #id)();
}
