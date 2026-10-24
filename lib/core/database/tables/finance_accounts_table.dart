import 'package:drift/drift.dart';

import 'syncable_table.dart';

/// Финансовые продукты: счета, кредиты и депозиты.
///
/// Смысл полей зависит от [kind] (0 — счёт, 1 — кредит, 2 — депозит,
/// 3 — кредитная карта / Сплит-лимит):
/// * счёт: [balance] — деньги на счёте;
/// * кредит: [balance] — текущий остаток долга, [targetAmount] — исходная
///   сумма задолженности, [monthlyPayment] и [paymentDay] — регулярный платёж
///   либо, при [isFlexibleSchedule] (Сплит, Долями, BNPL), ближайшее списание
///   [nextPaymentDate] / [nextPaymentAmount];
/// * депозит: [balance] — накопленная сумма, [targetAmount] — цель копилки,
///   [interestRate] / [termMonths] — процент и срок;
/// * кредитная карта: [balance] — текущий долг (использованный лимит),
///   [targetAmount] — кредитный лимит. Отдельных колонок нет, поэтому старые
///   записи и снимки синхронизации читаются без миграции.
///
/// [balance] — производное значение: [initialBalance] плюс влияние всех
/// неудалённых операций (см. `FinanceRepository.recalculateBalances`).
/// Поэтому операции, добавленные на двух устройствах, не теряются при
/// слиянии, хотя сама запись счёта сливается по Last-Write-Wins.
@DataClassName('FinanceAccountEntity')
class FinanceAccounts extends Table with SyncableTable {
  TextColumn get name => text()();
  IntColumn get kind => integer().withDefault(const Constant(0))();
  RealColumn get balance => real().withDefault(const Constant(0))();

  /// Начальный остаток на момент создания продукта (в тех же единицах, что
  /// и [balance]: для кредита и кредитки — долг).
  RealColumn get initialBalance => real().withDefault(const Constant(0))();
  RealColumn get targetAmount => real().nullable()();
  RealColumn get interestRate => real().nullable()();
  IntColumn get termMonths => integer().nullable()();
  RealColumn get monthlyPayment => real().nullable()();
  IntColumn get paymentDay => integer().nullable()();

  /// Плавающий график (рассрочка): вместо дня месяца — конкретная дата и
  /// сумма ближайшего списания, которые сдвигаются после каждой оплаты.
  BoolColumn get isFlexibleSchedule =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get nextPaymentDate => dateTime().nullable()();
  RealColumn get nextPaymentAmount => real().nullable()();
}
