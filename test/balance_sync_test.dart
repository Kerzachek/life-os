import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/database/app_database.dart';
import 'package:home_organizer/core/sync/sync_engine.dart';
import 'package:home_organizer/core/sync/sync_payload.dart';
import 'package:home_organizer/core/sync/sync_remote_store.dart';
import 'package:home_organizer/features/finance/data/repositories/finance_repository.dart';
import 'package:home_organizer/features/finance/domain/finance_category_presets.dart';
import 'package:home_organizer/features/finance/domain/finance_enums.dart';

import 'helpers/fake_sync_cloud.dart';
import 'helpers/sync_harness.dart';

void main() {
  final h = useSyncHarness();

  late FinanceRepository repoA;
  late FinanceRepository repoB;

  setUp(() {
    repoA = FinanceRepository(h().dbA);
    repoB = FinanceRepository(h().dbB);
  });

  Future<FinanceAccountEntity> account(AppDatabase db, String id) {
    return (db.select(
      db.financeAccounts,
    )..where((a) => a.id.equals(id))).getSingle();
  }

  /// Полный цикл через облако: A → B → A, после чего устройства сошлись.
  Future<void> syncAll(FakeRemoteStore cloud) async {
    await performSync(h().engineA, cloud);
    await performSync(h().engineB, cloud);
    await performSync(h().engineA, cloud);
  }

  test(
    'офлайн-операции на двух устройствах дают верный баланс после слияния',
    () async {
      final cloud = FakeRemoteStore();
      final cardId = await repoA.createAccount(
        name: 'Карта',
        kind: FinanceAccountKind.account,
        balance: 1000,
      );
      await syncAll(cloud);
      expect((await account(h().dbB, cardId)).balance, 1000);

      // Офлайн: каждое устройство пишет свои операции.
      await repoA.createTransaction(
        type: FinanceTransactionType.expense,
        amount: 200,
        accountId: cardId,
        categoryId: FinanceCategoryIds.food,
      );
      await repoB.createTransaction(
        type: FinanceTransactionType.income,
        amount: 500,
        accountId: cardId,
      );
      await repoB.createTransaction(
        type: FinanceTransactionType.expense,
        amount: 100.5,
        accountId: cardId,
      );
      // Правка карточки счёта на B делает его запись «победителем» LWW.
      final onB = await account(h().dbB, cardId);
      await repoB.updateAccount(
        id: cardId,
        name: 'Карта (зарплатная)',
        kind: FinanceAccountKind.account,
        balance: onB.balance,
      );
      // Метки хранятся с точностью до секунды: правка заведомо позже.
      await (h().dbB.update(h().dbB.financeAccounts)
            ..where((a) => a.id.equals(cardId)))
          .write(FinanceAccountsCompanion(
        updatedAt: Value(DateTime.now().toUtc().add(const Duration(minutes: 1))),
      ));
      expect((await account(h().dbA, cardId)).balance, 800);
      expect((await account(h().dbB, cardId)).balance, 1399.5);

      await syncAll(cloud);

      for (final db in [h().dbA, h().dbB]) {
        final merged = await account(db, cardId);
        expect(merged.name, 'Карта (зарплатная)');
        expect(merged.initialBalance, 1000);
        expect(merged.balance, 1199.5);
      }
      // Сошлись: ещё один цикл ничего не выгружает.
      final outcome = await performSync(h().engineA, cloud);
      expect(outcome.uploaded, isFalse);
    },
  );

  test(
    'переводы и платежи по кредиту с разных устройств не теряются',
    () async {
      final cloud = FakeRemoteStore();
      final loanId = await repoA.createAccount(
        name: 'Кредит',
        kind: FinanceAccountKind.loan,
        balance: 10000,
      );
      final depositId = await repoA.createAccount(
        name: 'Копилка',
        kind: FinanceAccountKind.deposit,
      );
      await syncAll(cloud);

      await repoA.recordLoanPayment(
        loanId: loanId,
        fromAccountId: defaultFinanceAccountId,
        amount: 1500,
      );
      await repoB.recordLoanPayment(
        loanId: loanId,
        fromAccountId: defaultFinanceAccountId,
        amount: 2500,
      );
      await repoB.recordDepositTopUp(
        depositId: depositId,
        fromAccountId: defaultFinanceAccountId,
        amount: 300,
      );
      await syncAll(cloud);

      for (final db in [h().dbA, h().dbB]) {
        expect((await account(db, loanId)).balance, 6000);
        expect((await account(db, depositId)).balance, 300);
        expect((await account(db, defaultFinanceAccountId)).balance, -4300);
      }
    },
  );

  test('удаление операции на одном устройстве и новая на другом', () async {
    final cloud = FakeRemoteStore();
    final txId = await repoA.createTransaction(
      type: FinanceTransactionType.income,
      amount: 700,
      accountId: defaultFinanceAccountId,
    );
    await syncAll(cloud);
    expect((await account(h().dbB, defaultFinanceAccountId)).balance, 700);

    await repoA.deleteTransaction(txId);
    await repoB.createTransaction(
      type: FinanceTransactionType.expense,
      amount: 50,
      accountId: defaultFinanceAccountId,
    );
    await syncAll(cloud);

    for (final db in [h().dbA, h().dbB]) {
      expect((await account(db, defaultFinanceAccountId)).balance, -50);
    }
  });

  test(
    'устаревший баланс в победившей записи счёта исправляется пересчётом',
    () async {
      final cardId = await repoA.createAccount(
        name: 'Карта',
        kind: FinanceAccountKind.account,
        balance: 100,
      );
      await h().pushAtoB();
      await repoA.createTransaction(
        type: FinanceTransactionType.expense,
        amount: 40,
        accountId: cardId,
      );
      // Как в прежних версиях: B записал баланс поверх и обновил updatedAt.
      await (h().dbB.update(
        h().dbB.financeAccounts,
      )..where((a) => a.id.equals(cardId))).write(
        FinanceAccountsCompanion(
          balance: const Value(100),
          updatedAt: Value(
            DateTime.now().toUtc().add(const Duration(hours: 1)),
          ),
        ),
      );

      await h().pushBtoA();

      expect((await account(h().dbA, cardId)).balance, 60);
    },
  );

  test(
    'снимок прежней версии без initialBalance сливается без двойного учёта',
    () async {
      final cardId = await repoB.createAccount(
        name: 'Карта',
        kind: FinanceAccountKind.creditCard,
        balance: 0,
        targetAmount: 5000,
      );
      await repoB.createTransaction(
        type: FinanceTransactionType.expense,
        amount: 1200,
        accountId: cardId,
      );
      final payload = await h().cloudOf(h().engineB);
      final legacy = SyncPayload(
        lastSyncTimestamp: payload.lastSyncTimestamp,
        deviceId: payload.deviceId,
        tables: {
          ...payload.tables,
          'finance_accounts': [
            for (final a in payload.tables['finance_accounts']!)
              {...a}..remove('initialBalance'),
          ],
        },
      );

      await h().engineA.mergeFromSyncPayload(
        SyncPayload.decode(legacy.encode()),
      );

      final merged = await account(h().dbA, cardId);
      expect(merged.initialBalance, 0);
      expect(merged.balance, 1200);
    },
  );

  test('withDerivedInitialBalances не трогает снимки новой версии', () {
    final tables = {
      'finance_accounts': [
        {'id': 'a', 'kind': 0, 'balance': 10.0, 'initialBalance': 3.0},
      ],
    };
    expect(identical(withDerivedInitialBalances(tables), tables), isTrue);
  });

  test(
    'удаление продукта не меняет баланс счёта, с которого был перевод',
    () async {
      final depositId = await repoA.createAccount(
        name: 'Копилка',
        kind: FinanceAccountKind.deposit,
      );
      await repoA.recordDepositTopUp(
        depositId: depositId,
        fromAccountId: defaultFinanceAccountId,
        amount: 900,
      );
      await repoA.deleteAccount(depositId);
      await repoA.recalculateBalances();

      expect((await account(h().dbA, defaultFinanceAccountId)).balance, -900);
    },
  );

  test(
    'миграция v10 → v11 выводит initialBalance из баланса и операций',
    () async {
      final dir = Directory.systemTemp.createTempSync('balance_migration');
      final file = File('${dir.path}/test.sqlite');

      final old = AppDatabase.forTesting(NativeDatabase(file));
      final oldRepo = FinanceRepository(old);
      final loanId = await oldRepo.createAccount(
        name: 'Кредит',
        kind: FinanceAccountKind.loan,
        balance: 5000,
      );
      await oldRepo.createTransaction(
        type: FinanceTransactionType.income,
        amount: 1000,
        accountId: defaultFinanceAccountId,
      );
      await oldRepo.recordLoanPayment(
        loanId: loanId,
        fromAccountId: defaultFinanceAccountId,
        amount: 400,
      );
      // Имитируем базу v10: колонки ещё нет.
      await old.customStatement(
        'ALTER TABLE finance_accounts DROP COLUMN initial_balance',
      );
      await old.customStatement('PRAGMA user_version = 10');
      await old.close();

      final db = AppDatabase.forTesting(NativeDatabase(file));
      try {
        final main = await account(db, defaultFinanceAccountId);
        expect(main.balance, 600);
        expect(main.initialBalance, 0);
        final loan = await account(db, loanId);
        expect(loan.balance, 4600);
        expect(loan.initialBalance, 5000);

        // Пересчёт после миграции сохраняет балансы.
        await FinanceRepository(db).recalculateBalances();
        expect((await account(db, defaultFinanceAccountId)).balance, 600);
        expect((await account(db, loanId)).balance, 4600);
      } finally {
        await db.close();
        dir.deleteSync(recursive: true);
      }
    },
  );
}
