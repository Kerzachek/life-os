import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/database/app_database.dart';
import 'package:home_organizer/core/database/database_provider.dart';
import 'package:home_organizer/core/services/notification_scheduler.dart';
import 'package:home_organizer/core/sync/sync_engine.dart';
import 'package:home_organizer/core/sync/sync_payload.dart';
import 'package:home_organizer/features/finance/data/repositories/finance_repository.dart';
import 'package:home_organizer/features/finance/domain/finance_calculations.dart';
import 'package:home_organizer/features/finance/domain/finance_category_presets.dart';
import 'package:home_organizer/features/finance/domain/finance_enums.dart';

final _stamp = DateTime.utc(2026, 1, 1);

FinanceAccountEntity _loan({
  double balance = 3000,
  DateTime? nextDate,
  double? nextAmount,
  bool flexible = true,
}) {
  return FinanceAccountEntity(
    id: 'loan',
    createdAt: _stamp,
    updatedAt: _stamp,
    name: 'Сплит',
    kind: FinanceAccountKind.loan.value,
    balance: balance,
    initialBalance: balance,
    isFlexibleSchedule: flexible,
    nextPaymentDate: nextDate,
    nextPaymentAmount: nextAmount,
  );
}

final _obligation = ObligationEntity(
  id: 'obl',
  createdAt: _stamp,
  updatedAt: _stamp,
  name: 'Кредит: Сплит',
  amount: 1000,
  dueDay: 1,
  isVariableAmount: false,
  loanAccountId: 'loan',
);

FinanceTransactionEntity _payment(DateTime date, double amount) {
  return FinanceTransactionEntity(
    id: 'tx_${date.microsecondsSinceEpoch}',
    createdAt: _stamp,
    updatedAt: _stamp,
    date: date,
    amount: amount,
    type: FinanceTransactionType.expense.value,
    accountId: defaultFinanceAccountId,
    targetAccountId: 'loan',
    obligationId: 'obl',
  );
}

void main() {
  group('статус платежа по рассрочке', () {
    final month = DateTime(2026, 10);
    final now = DateTime(2026, 10, 22);

    List<ObligationStatus> statuses(
      FinanceAccountEntity loan, [
      List<FinanceTransactionEntity> txs = const [],
      DateTime? today,
    ]) =>
        buildObligationStatuses([_obligation], txs, month,
            now: today ?? now, accounts: [loan]);

    test('срок и сумма берутся из ближайшего списания', () {
      final s = statuses(
        _loan(nextDate: DateTime(2026, 10, 24), nextAmount: 750),
      ).single;
      expect(s.isFlexible, isTrue);
      expect(s.isPaid, isFalse);
      expect(s.amount, 750);
      expect(s.dueDate, DateTime(2026, 10, 24));
      expect(s.daysUntilDue, 2);
      expect(s.urgency, ObligationUrgency.upcoming);
    });

    test('вторая доля в том же месяце снова к оплате', () {
      final s = statuses(
        _loan(nextDate: DateTime(2026, 10, 29), nextAmount: 1000),
        [_payment(DateTime(2026, 10, 15), 1000)],
      ).single;
      expect(s.isPaid, isFalse);
      expect(s.urgency, ObligationUrgency.scheduled);
    });

    test('просроченная доля прошлого месяца — просрочка', () {
      final s = statuses(
        _loan(nextDate: DateTime(2026, 9, 30), nextAmount: 1000),
      ).single;
      expect(s.urgency, ObligationUrgency.overdue);
      expect(s.daysUntilDue, -22);
    });

    test('после оплаты, если следующая доля в следующем месяце — оплачено',
        () {
      final s = statuses(
        _loan(nextDate: DateTime(2026, 11, 5), nextAmount: 1000),
        [_payment(DateTime(2026, 10, 22), 1000)],
      ).single;
      expect(s.isPaid, isTrue);
      expect(s.paidAmount, 1000);
      expect(s.urgency, ObligationUrgency.paid);
    });

    test('доля в следующем месяце без оплаты в этом — не показывается', () {
      expect(
        statuses(_loan(nextDate: DateTime(2026, 11, 5), nextAmount: 1000)),
        isEmpty,
      );
    });

    test('доля 1-го числа следующего месяца попадает в предстоящие', () {
      final s = statuses(
        _loan(nextDate: DateTime(2026, 11, 1), nextAmount: 1000),
        const [],
        DateTime(2026, 10, 30),
      ).single;
      expect(s.urgency, ObligationUrgency.upcoming);
      expect(s.daysUntilDue, 2);
      // Напоминание о платежах подхватывает дату из nextPaymentDate.
      final reminder = buildPaymentsReminder([s]);
      expect(reminder, isNotNull);
      expect(reminder!.body, contains('Кредит: Сплит'));
    });

    test('долг закрыт: оплачено, если была оплата, иначе скрыт', () {
      expect(statuses(_loan(balance: 0)), isEmpty);
      final s = statuses(
        _loan(balance: 0),
        [_payment(DateTime(2026, 10, 10), 1000)],
      ).single;
      expect(s.isPaid, isTrue);
    });

    test('обычный кредит по-прежнему считается по дню месяца', () {
      final s = statuses(
        _loan(flexible: false, nextDate: DateTime(2026, 10, 30)),
      ).single;
      expect(s.isFlexible, isFalse);
      expect(s.dueDate, DateTime(2026, 10, 1));
      expect(s.urgency, ObligationUrgency.overdue);
    });
  });

  group('подсказка следующей доли', () {
    final now = DateTime(2026, 10, 22);

    test('+14 дней к оплаченному сроку, сумма — прежняя доля', () {
      final step = suggestNextFlexiblePayment(
        loan: _loan(nextDate: DateTime(2026, 10, 20), nextAmount: 1000),
        paidAmount: 1000,
        now: now,
      )!;
      expect(step.date, DateTime(2026, 11, 3));
      expect(step.amount, 1000);
    });

    test('давно просроченный срок — +14 дней от сегодня', () {
      final step = suggestNextFlexiblePayment(
        loan: _loan(nextDate: DateTime(2026, 9, 1), nextAmount: 1000),
        paidAmount: 1000,
        now: now,
      )!;
      expect(step.date, DateTime(2026, 11, 5));
    });

    test('доля не больше остатка долга; полное погашение — null', () {
      final step = suggestNextFlexiblePayment(
        loan: _loan(balance: 1500, nextAmount: 1000),
        paidAmount: 1000,
        now: now,
      )!;
      expect(step.amount, 500);
      expect(
        suggestNextFlexiblePayment(
          loan: _loan(balance: 1000, nextAmount: 1000),
          paidAmount: 1000,
          now: now,
        ),
        isNull,
      );
    });
  });

  group('репозиторий', () {
    late AppDatabase db;
    late ProviderContainer container;
    late FinanceRepository repo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      repo = container.read(financeRepositoryProvider);
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    Future<FinanceAccountEntity> account(String id) async =>
        (await repo.getAccounts()).firstWhere((a) => a.id == id);

    final today = dateOnly(DateTime.now());

    Future<String> createSplit() => repo.createAccount(
          name: 'Сплит',
          kind: FinanceAccountKind.loan,
          balance: 3000,
          monthlyPayment: 999,
          paymentDay: 15,
          isFlexibleSchedule: true,
          nextPaymentDate: today,
          nextPaymentAmount: 1000,
        );

    test('рассрочка создаёт платёж по ближайшему списанию', () async {
      final id = await createSplit();
      final loan = await account(id);
      expect(loan.isFlexibleSchedule, isTrue);
      expect(dateOnly(loan.nextPaymentDate!), today);
      final obligation = (await repo.getObligations()).single;
      expect(obligation.amount, 1000);
      expect(obligation.dueDay, today.day);
    });

    test('флаг игнорируется для не-кредитов', () async {
      final id = await repo.createAccount(
        name: 'Карта',
        kind: FinanceAccountKind.account,
        isFlexibleSchedule: true,
        nextPaymentDate: today,
        nextPaymentAmount: 100,
      );
      final a = await account(id);
      expect(a.isFlexibleSchedule, isFalse);
      expect(a.nextPaymentDate, isNull);
      expect(await repo.getObligations(), isEmpty);
    });

    test('оплаты сдвигают график, последняя закрывает долг; отмена', () async {
      final id = await createSplit();
      final obligationId = (await repo.getObligations()).single.id;

      expect(
        await repo.payObligation(
          obligationId: obligationId,
          fromAccountId: defaultFinanceAccountId,
        ),
        isTrue,
      );
      var loan = await account(id);
      expect(loan.balance, 2000);
      expect(dateOnly(loan.nextPaymentDate!),
          DateTime(today.year, today.month, today.day + 14));
      expect(loan.nextPaymentAmount, 1000);

      // Следующую долю можно оплатить в том же месяце, указав свой шаг.
      final custom = DateTime(today.year, today.month, today.day + 10);
      expect(
        await repo.payObligation(
          obligationId: obligationId,
          fromAccountId: defaultFinanceAccountId,
          nextPaymentDate: custom,
          nextPaymentAmount: 5000,
        ),
        isTrue,
      );
      loan = await account(id);
      expect(loan.balance, 1000);
      expect(dateOnly(loan.nextPaymentDate!), custom);
      expect(loan.nextPaymentAmount, 1000, reason: 'не больше остатка долга');
      expect((await repo.getObligations()).single.amount, 1000);

      await repo.payObligation(
        obligationId: obligationId,
        fromAccountId: defaultFinanceAccountId,
      );
      loan = await account(id);
      expect(loan.balance, 0);
      expect(loan.nextPaymentDate, isNull);
      expect(loan.nextPaymentAmount, isNull);
      final status = buildObligationStatuses(
        await repo.getObligations(),
        await repo.getTransactions(),
        DateTime(today.year, today.month),
        accounts: await repo.getAccounts(),
      ).single;
      expect(status.isPaid, isTrue);

      await repo.undoObligationPayment(obligationId: obligationId);
      loan = await account(id);
      expect(loan.balance, 1000);
      expect(dateOnly(loan.nextPaymentDate!), today);
      expect(loan.nextPaymentAmount, 1000);
    });

    test('быстрая правка ближайшего списания', () async {
      final id = await createSplit();
      final date = DateTime(today.year, today.month, today.day + 3);
      await repo.updateNextPayment(loanId: id, date: date, amount: 1250);
      final loan = await account(id);
      expect(dateOnly(loan.nextPaymentDate!), date);
      expect(loan.nextPaymentAmount, 1250);
      final obligation = (await repo.getObligations()).single;
      expect(obligation.amount, 1250);
      expect(obligation.dueDay, date.day);
    });

    test('выключение плавающего графика возвращает ежемесячный платёж',
        () async {
      final id = await createSplit();
      await repo.updateAccount(
        id: id,
        name: 'Сплит',
        kind: FinanceAccountKind.loan,
        balance: 3000,
        monthlyPayment: 1500,
        paymentDay: 10,
      );
      final loan = await account(id);
      expect(loan.isFlexibleSchedule, isFalse);
      expect(loan.nextPaymentDate, isNull);
      final obligation = (await repo.getObligations()).single;
      expect(obligation.amount, 1500);
      expect(obligation.dueDay, 10);
    });

    test('облачный снимок старой версии без полей рассрочки', () async {
      final legacy = _loan()
          .toJson(serializer: syncValueSerializer)
        ..remove('isFlexibleSchedule')
        ..remove('nextPaymentDate')
        ..remove('nextPaymentAmount');
      await SyncEngine(db).mergeFromSyncPayload(SyncPayload(
        lastSyncTimestamp: _stamp,
        deviceId: 'old-device',
        tables: {
          'finance_accounts': [legacy],
        },
      ));
      final loan = await account('loan');
      expect(loan.isFlexibleSchedule, isFalse);
      expect(loan.nextPaymentDate, isNull);
      expect(loan.nextPaymentAmount, isNull);
    });
  });

  test('миграция v6 → v7 добавляет колонки, старые счета читаются', () async {
    final dir = Directory.systemTemp.createTempSync('flexible_migration');
    final file = File('${dir.path}/test.sqlite');

    final old = AppDatabase.forTesting(NativeDatabase(file));
    await old.customSelect('SELECT 1').get();
    for (final column in [
      'is_flexible_schedule',
      'next_payment_date',
      'next_payment_amount',
    ]) {
      await old.customStatement(
          'ALTER TABLE finance_accounts DROP COLUMN $column');
    }
    await old.customStatement('PRAGMA user_version = 6');
    await old.close();

    final db = AppDatabase.forTesting(NativeDatabase(file));
    try {
      final account = (await db.select(db.financeAccounts).get()).single;
      expect(account.id, defaultFinanceAccountId);
      expect(account.isFlexibleSchedule, isFalse);
      expect(account.nextPaymentDate, isNull);
    } finally {
      await db.close();
      dir.deleteSync(recursive: true);
    }
  });
}
