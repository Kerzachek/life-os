import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/database/app_database.dart';
import 'package:home_organizer/core/database/database_provider.dart';
import 'package:home_organizer/core/sync/sync_engine.dart';
import 'package:home_organizer/core/theme/app_theme.dart';
import 'package:home_organizer/features/finance/data/repositories/finance_repository.dart';
import 'package:home_organizer/features/finance/domain/finance_calculations.dart';
import 'package:home_organizer/features/finance/domain/finance_category_presets.dart';
import 'package:home_organizer/features/finance/domain/finance_enums.dart';
import 'package:home_organizer/features/finance/presentation/screens/finance_screen.dart';

void main() {
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

  Future<ObligationEntity> obligation(String id) async =>
      (await repo.getObligations()).firstWhere((o) => o.id == id);

  /// Прошлые оплаты платежа [id] на [amounts] — по одной в месяц назад.
  Future<void> seedHistory(String id, List<double> amounts) async {
    final now = DateTime.now();
    for (var i = 0; i < amounts.length; i++) {
      await repo.createTransaction(
        type: FinanceTransactionType.expense,
        amount: amounts[i],
        accountId: defaultFinanceAccountId,
        categoryId: FinanceCategoryIds.obligations,
        date: DateTime(now.year, now.month - 1 - i, 10),
        obligationId: id,
      );
    }
  }

  group('медиана', () {
    test('нечётное и чётное число значений', () {
      expect(median([]), isNull);
      expect(median([300, 100, 200]), 200);
      expect(median([100, 200, 300, 1000]), 250);
    });
  });

  group('оценка плавающего платежа', () {
    test('без истории — базовая сумма, с историей — медиана', () async {
      final id = await repo.createObligation(
        name: 'ЖКХ',
        amount: 5000,
        dueDay: 25,
        isVariableAmount: true,
      );
      var o = await obligation(id);
      expect(o.isVariableAmount, isTrue);
      expect(obligationEstimate(o, await repo.getTransactions()), 5000);

      await seedHistory(id, [4200, 6100, 4800]);
      final txs = await repo.getTransactions();
      expect(obligationPaymentHistory(o, txs), hasLength(3));
      expect(obligationEstimate(o, txs), 4800);

      // Ручной ориентир важнее медианы.
      await repo.updateObligation(
        id: id,
        name: 'ЖКХ',
        amount: 5000,
        dueDay: 25,
        isVariableAmount: true,
        estimatedAmount: 5500,
      );
      o = await obligation(id);
      expect(obligationEstimate(o, txs), 5500);
    });

    test('медиана берётся по последним оплатам', () async {
      final id = await repo.createObligation(
        name: 'Свет',
        amount: 1000,
        dueDay: 5,
        isVariableAmount: true,
      );
      // Новые оплаты (первые в списке) — около 2000, старые — 100.
      await seedHistory(id, [2000, 2100, 1900, 2050, 1950, 2000, 100, 100]);
      final o = await obligation(id);
      expect(obligationMedianPayment(o, await repo.getTransactions()), 2000);
    });

    test('статус и сводка месяца используют оценку', () async {
      final id = await repo.createObligation(
        name: 'ЖКХ',
        amount: 5000,
        dueDay: 28,
        isVariableAmount: true,
      );
      await repo.createObligation(name: 'Интернет', amount: 800, dueDay: 28);
      await seedHistory(id, [4000, 4400]);

      final now = DateTime.now();
      final statuses = buildObligationStatuses(
        await repo.getObligations(),
        await repo.getTransactions(),
        DateTime(now.year, now.month),
        now: now,
      );
      final zhkh = statuses.firstWhere((s) => s.obligation.id == id);
      expect(zhkh.isVariable, isTrue);
      expect(zhkh.amount, 4200);

      final summary = buildSummary(
        accounts: await repo.getAccounts(),
        obligations: statuses,
      );
      expect(summary.obligationsTotal, 5000);
      expect(summary.obligationsRemaining, 5000);
    });
  });

  group('оплата плавающего платежа', () {
    test('списывается фактическая сумма, затем статус по факту', () async {
      final id = await repo.createObligation(
        name: 'ЖКХ',
        amount: 5000,
        dueDay: 28,
        isVariableAmount: true,
      );
      final ok = await repo.payObligation(
        obligationId: id,
        fromAccountId: defaultFinanceAccountId,
        amount: 5321.4,
      );
      expect(ok, isTrue);

      final tx = (await repo.getTransactions()).single;
      expect(tx.amount, 5321.4);
      expect(tx.obligationId, id);
      final account = (await repo.getAccounts()).single;
      expect(account.balance, -5321.4);

      final now = DateTime.now();
      final month = DateTime(now.year, now.month);
      final status = buildObligationStatuses(
        await repo.getObligations(),
        await repo.getTransactions(),
        month,
        now: now,
      ).single;
      expect(status.isPaid, isTrue);
      expect(status.amount, 5321.4);

      // В следующем месяце платёж снова к оплате — с оценкой по истории.
      final next = buildObligationStatuses(
        await repo.getObligations(),
        await repo.getTransactions(),
        DateTime(now.year, now.month + 1),
        now: now,
      ).single;
      expect(next.isPaid, isFalse);
      expect(next.amount, 5321.4);
    });

    test('без суммы списывается оценка', () async {
      final id = await repo.createObligation(
        name: 'Свет',
        amount: 900,
        dueDay: 28,
        isVariableAmount: true,
      );
      await seedHistory(id, [1200]);
      await repo.payObligation(
        obligationId: id,
        fromAccountId: defaultFinanceAccountId,
      );
      final paid = (await repo.getTransactions()).first;
      expect(paid.amount, 1200);
    });
  });

  test('редактирование сохраняет счёт списания и признак плавающей суммы',
      () async {
    final id = await repo.createObligation(
      name: 'Аренда',
      amount: 30000,
      dueDay: 1,
    );
    await repo.updateObligation(
      id: id,
      name: 'Аренда квартиры',
      amount: 32000,
      dueDay: 3,
      categoryId: FinanceCategoryIds.obligations,
      accountId: defaultFinanceAccountId,
      isVariableAmount: true,
      estimatedAmount: 31000,
    );
    var o = await obligation(id);
    expect(o.name, 'Аренда квартиры');
    expect(o.amount, 32000);
    expect(o.dueDay, 3);
    expect(o.accountId, defaultFinanceAccountId);
    expect(o.isVariableAmount, isTrue);
    expect(o.estimatedAmount, 31000);

    // Выключение плавающей суммы сбрасывает ориентир.
    await repo.updateObligation(
      id: id,
      name: 'Аренда квартиры',
      amount: 32000,
      dueDay: 3,
      estimatedAmount: 31000,
    );
    o = await obligation(id);
    expect(o.isVariableAmount, isFalse);
    expect(o.estimatedAmount, isNull);
    expect(o.accountId, isNull);
  });

  test('снимок старой версии без новых полей читается', () {
    final now = DateTime.utc(2026, 1, 1);
    final o = obligationFromSyncJson({
      'id': 'x',
      'createdAt': now.millisecondsSinceEpoch,
      'updatedAt': now.millisecondsSinceEpoch,
      'name': 'ЖКХ',
      'amount': 100.0,
      'dueDay': 1,
    });
    expect(o.isVariableAmount, isFalse);
    expect(o.estimatedAmount, isNull);
    expect(o.accountId, isNull);
  });

  test('миграция v9 → v10 добавляет колонки плавающего платежа', () async {
    final dir = Directory.systemTemp.createTempSync('obligations_v10');
    final file = File('${dir.path}/test.sqlite');

    final old = AppDatabase.forTesting(NativeDatabase(file));
    await old.customSelect('SELECT 1').get();
    await old.customStatement('PRAGMA foreign_keys = OFF');
    await old.customStatement(
      'CREATE TABLE obligations_v9 AS SELECT id, created_at, updated_at, '
      'deleted_at, name, amount, due_day, category_id, loan_account_id, '
      'skipped_month FROM obligations',
    );
    await old.customStatement('DROP TABLE obligations');
    await old.customStatement(
        'ALTER TABLE obligations_v9 RENAME TO obligations');
    await old.customStatement(
      "INSERT INTO obligations (id, created_at, updated_at, name, amount, "
      "due_day) VALUES ('o1', 0, 0, 'ЖКХ', 5000, 10)",
    );
    await old.customStatement('PRAGMA user_version = 9');
    await old.close();

    final migrated = AppDatabase.forTesting(NativeDatabase(file));
    try {
      final o = (await migrated.select(migrated.obligations).get()).single;
      expect(o.name, 'ЖКХ');
      expect(o.isVariableAmount, isFalse);
      expect(o.estimatedAmount, isNull);
      expect(o.accountId, isNull);
    } finally {
      await migrated.close();
      dir.deleteSync(recursive: true);
    }
  });

  group('экран', () {
    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> openScreen(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkLauncherTheme,
            home: const FinanceScreen(),
          ),
        ),
      );
      await settle(tester);
    }

    Future<void> closeScreen(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }

    testWidgets('бейдж итога и оплата с фактической суммой', (tester) async {
      late String id;
      await tester.runAsync(() async {
        id = await repo.createObligation(
          name: 'ЖКХ',
          amount: 5000,
          dueDay: 28,
          isVariableAmount: true,
        );
        await repo.createObligation(name: 'Интернет', amount: 800, dueDay: 28);
      });
      await openScreen(tester);

      final badge = tester.widget<Text>(find.descendant(
        of: find.byKey(const ValueKey('obligations_total_badge')),
        matching: find.byType(Text),
      ));
      expect(badge.data, contains('Всего к оплате: 5 800'));
      expect(badge.data, contains('осталось: 5 800'));
      expect(find.byKey(ValueKey('variable_badge_$id')), findsOneWidget);
      expect(find.textContaining('≈ 5 000'), findsOneWidget);

      await tester.tap(find.byKey(ValueKey('pay_$id')));
      await tester.pumpAndSettle();
      expect(find.text('Фактическая сумма списания'), findsOneWidget);
      final field = tester.widget<TextField>(find.descendant(
        of: find.byKey(const ValueKey('variable_sheet_amount')),
        matching: find.byType(TextField),
      ));
      expect(field.controller!.text, '5000.0');
      expect(find.byKey(const ValueKey('variable_sheet_next')), findsOneWidget);

      await tester.enterText(
          find.byKey(const ValueKey('variable_sheet_amount')), '5432,10');
      await tester.tap(find.byKey(const ValueKey('variable_sheet_submit')));
      await settle(tester);
      await tester.pumpAndSettle();

      final txs = (await tester.runAsync(repo.getTransactions))!;
      expect(txs.single.amount, 5432.1);
      expect(txs.single.obligationId, id);
      expect(
        tester.widget<CheckboxListTile>(find.byKey(ValueKey('pay_$id'))).value,
        isTrue,
      );
      final after = tester.widget<Text>(find.descendant(
        of: find.byKey(const ValueKey('obligations_total_badge')),
        matching: find.byType(Text),
      ));
      expect(after.data, contains('осталось: 800'));

      await closeScreen(tester);
    });

    testWidgets('отмена шторки не создаёт операцию', (tester) async {
      late String id;
      await tester.runAsync(() async {
        id = await repo.createObligation(
          name: 'Свет',
          amount: 1500,
          dueDay: 28,
          isVariableAmount: true,
        );
      });
      await openScreen(tester);

      await tester.tap(find.byKey(ValueKey('pay_$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Отмена'));
      await settle(tester);
      await tester.pumpAndSettle();

      expect((await tester.runAsync(repo.getTransactions))!, isEmpty);
      await closeScreen(tester);
    });

    testWidgets('платёж редактируется прямо из списка', (tester) async {
      late String id;
      await tester.runAsync(() async {
        id = await repo.createObligation(name: 'ЖКХ', amount: 5000, dueDay: 28);
      });
      await openScreen(tester);

      await tester.tap(find.byKey(ValueKey('edit_obligation_$id')));
      await tester.pumpAndSettle();
      expect(find.text('Редактировать платёж'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('obligation_variable')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('obligation_submit')));
      await settle(tester);
      await tester.pumpAndSettle();

      final o = (await tester.runAsync(() => obligation(id)))!;
      expect(o.isVariableAmount, isTrue);
      expect(o.estimatedAmount, isNull);
      expect(find.byKey(ValueKey('variable_badge_$id')), findsOneWidget);

      await closeScreen(tester);
    });
  });
}
