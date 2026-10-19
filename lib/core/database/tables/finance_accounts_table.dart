import 'package:drift/drift.dart';
import 'syncable_table.dart';

/// Финансовые продукты: счета, кредиты и депозиты.
///
/// Смысл полей зависит от [kind] (0 — счёт, 1 — кредит, 2 — депозит):
/// * счёт: [balance] — деньги на счёте;
/// * кредит: [balance] — текущий остаток долга, [targetAmount] — исходная
///   сумма задолженности, [monthlyPayment] и [paymentDay] — регулярный платёж;
/// * депозит: [balance] — накопленная сумма, [targetAmount] — цель копилки,
///   [interestRate] / [termMonths] — процент и срок.
@DataClassName('FinanceAccountEntity')
class FinanceAccounts extends Table with SyncableTable {
  TextColumn get name => text()();
  IntColumn get kind => integer().withDefault(const Constant(0))();
  RealColumn get balance => real().withDefault(const Constant(0))();
  RealColumn get targetAmount => real().nullable()();
  RealColumn get interestRate => real().nullable()();
  IntColumn get termMonths => integer().nullable()();
  RealColumn get monthlyPayment => real().nullable()();
  IntColumn get paymentDay => integer().nullable()();
}
