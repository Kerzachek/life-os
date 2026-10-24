import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/database/app_database.dart';
import 'package:home_organizer/core/database/database_provider.dart';
import 'package:home_organizer/core/sync/sync_engine.dart';
import 'package:home_organizer/core/theme/app_theme.dart';
import 'package:home_organizer/features/finance/data/repositories/finance_repository.dart';
import 'package:home_organizer/features/finance/domain/category_budgets.dart';
import 'package:home_organizer/features/finance/domain/finance_analytics.dart';
import 'package:home_organizer/features/finance/domain/finance_category_presets.dart';
import 'package:home_organizer/features/finance/domain/finance_enums.dart';
import 'package:home_organizer/features/finance/presentation/providers/finance_provider.dart';
import 'package:home_organizer/features/finance/presentation/screens/finance_screen.dart';

final DateTime stamp = DateTime.utc(2026, 1, 1);

CategoryBudgetEntity budget(
  String categoryId,
  int period,
  double limit, {
  DateTime? deletedAt,
}) {
  return CategoryBudgetEntity(
    id: categoryBudgetId(categoryId, period),
    createdAt: stamp,
    updatedAt: stamp,
    deletedAt: deletedAt,
    categoryId: categoryId,
    monthlyLimit: limit,
    period: period,
  );
}

FinanceCategoryEntity category(String id) => FinanceCategoryEntity(
      id: id,
      createdAt: stamp,
      updatedAt: stamp,
      name: id,
      color: '#FF00B894',
      isIncome: false,
      isSystem: false,
    );

FinanceTransactionEntity tx(
  double amount,
  DateTime date, {
  FinanceTransactionType type = FinanceTransactionType.expense,
  String accountId = 'main',
  String? targetAccountId,
  String? categoryId,
  DateTime? deletedAt,
}) {
  return FinanceTransactionEntity(
    id: 'tx_${amount}_${date.microsecondsSinceEpoch}_${type.value}',
    createdAt: stamp,
    updatedAt: stamp,
    deletedAt: deletedAt,
    date: date,
    amount: amount,
    type: type.value,
    accountId: accountId,
    targetAccountId: targetAccountId,
    categoryId: categoryId,
  );
}

FinanceAccountEntity account(
  String id,
  FinanceAccountKind kind,
  double initialBalance, {
  DateTime? createdAt,
}) {
  return FinanceAccountEntity(
    id: id,
    createdAt: createdAt ?? stamp,
    updatedAt: stamp,
    name: id,
    kind: kind.value,
    balance: initialBalance,
    initialBalance: initialBalance,
    isFlexibleSchedule: false,
  );
}

void main() {
  group('effectiveBudgetLimit', () {
    final budgets = [
      budget('food', 202603, 10000),
      budget('food', 202606, 15000),
      budget('food', 202609, 0),
      budget('fun', 202601, 5000, deletedAt: stamp),
    ];

    test('лимит действует с месяца периода до следующей записи', () {
      expect(effectiveBudgetLimit(budgets, 'food', DateTime(2026, 2)), isNull);
      expect(effectiveBudgetLimit(budgets, 'food', DateTime(2026, 3)), 10000);
      expect(effectiveBudgetLimit(budgets, 'food', DateTime(2026, 5)), 10000);
      expect(effectiveBudgetLimit(budgets, 'food', DateTime(2026, 6)), 15000);
      expect(effectiveBudgetLimit(budgets, 'food', DateTime(2026, 8)), 15000);
    });

    test('нулевой лимит снимает унаследованный, удалённые игнорируются', () {
      expect(effectiveBudgetLimit(budgets, 'food', DateTime(2026, 9)), isNull);
      expect(effectiveBudgetLimit(budgets, 'food', DateTime(2027, 1)), isNull);
      expect(effectiveBudgetLimit(budgets, 'fun', DateTime(2026, 5)), isNull);
    });
  });

  group('CategoryBudgetStatus.level', () {
    BudgetLevel levelFor(double spent) => CategoryBudgetStatus(
          category: category('food'),
          limit: 1000,
          spent: spent,
        ).level;

    test('зелёный < 70%, жёлтый 70–90%, оранжевый 90–100%, красный > 100%',
        () {
      expect(levelFor(0), BudgetLevel.ok);
      expect(levelFor(699), BudgetLevel.ok);
      expect(levelFor(700), BudgetLevel.warning);
      expect(levelFor(899), BudgetLevel.warning);
      expect(levelFor(900), BudgetLevel.critical);
      expect(levelFor(1000), BudgetLevel.critical);
      expect(levelFor(1000.01), BudgetLevel.exceeded);
    });
  });

  test('buildCategoryBudgets: траты месяца по категории, сортировка по доле',
      () {
    final month = DateTime(2026, 10);
    final result = buildCategoryBudgets(
      budgets: [budget('food', 202610, 1000), budget('fun', 202601, 500)],
      categories: [category('food'), category('fun'), category('home')],
      transactions: [
        tx(300, DateTime(2026, 10, 3), categoryId: 'food'),
        tx(200, DateTime(2026, 10, 20), categoryId: 'food'),
        // Другой месяц, доход, удалённая операция — не учитываются.
        tx(900, DateTime(2026, 9, 30), categoryId: 'food'),
        tx(50, DateTime(2026, 10, 5),
            categoryId: 'food', type: FinanceTransactionType.income),
        tx(77, DateTime(2026, 10, 6), categoryId: 'food', deletedAt: stamp),
        tx(450, DateTime(2026, 10, 7), categoryId: 'fun'),
        tx(999, DateTime(2026, 10, 7), categoryId: 'home'),
      ],
      month: month,
    );
    expect([for (final s in result) s.category.id], ['fun', 'food']);
    expect(result[0].spent, 450);
    expect(result[0].needsAttention, isTrue);
    expect(result[1].spent, 500);
    expect(result[1].remaining, 500);
    expect(result[1].needsAttention, isFalse);
  });

  group('buildMonthlyCashflow', () {
    test('6 месяцев до выбранного, переводы и удалённые не учитываются', () {
      final result = buildMonthlyCashflow(
        transactions: [
          tx(1000, DateTime(2026, 10, 1), type: FinanceTransactionType.income),
          tx(400, DateTime(2026, 10, 15)),
          tx(300, DateTime(2026, 5, 31)),
          tx(5000, DateTime(2026, 10, 2),
              type: FinanceTransactionType.transfer),
          tx(10, DateTime(2026, 10, 3), deletedAt: stamp),
          // Раньше окна.
          tx(700, DateTime(2026, 4, 30)),
        ],
        endMonth: DateTime(2026, 10),
      );
      expect([for (final m in result) m.month.month], [5, 6, 7, 8, 9, 10]);
      expect(result.first.expense, 300);
      expect(result.last.income, 1000);
      expect(result.last.expense, 400);
      expect(result.last.net, 600);
      expect(result.sublist(1, 5).every((m) => m.income == 0 && m.expense == 0),
          isTrue);
    });

    test('окно переходит через границу года', () {
      final months = monthsEndingAt(DateTime(2027, 2));
      expect(months.first, DateTime(2026, 9));
      expect(months.last, DateTime(2027, 2));
    });
  });

  group('buildNetWorthHistory', () {
    test('остатки на конец месяца: активы минус долги', () {
      final accounts = [
        account('main', FinanceAccountKind.account, 1000),
        account('card', FinanceAccountKind.creditCard, 0),
        account('loan', FinanceAccountKind.loan, 50000,
            createdAt: DateTime(2026, 9, 10)),
      ];
      final result = buildNetWorthHistory(
        accounts: accounts,
        transactions: [
          tx(5000, DateTime(2026, 8, 5), type: FinanceTransactionType.income),
          tx(2000, DateTime(2026, 9, 5), accountId: 'card'),
          tx(1000, DateTime(2026, 10, 1), targetAccountId: 'loan'),
        ],
        endMonth: DateTime(2026, 10),
      );
      expect(result.length, analyticsMonths);
      // Май–июль: только начальный остаток счёта.
      expect(result[0].netWorth, 1000);
      // Август: + зарплата.
      expect(result[3].assets, 6000);
      expect(result[3].debt, 0);
      // Сентябрь: долг по кредитке и новый кредит.
      expect(result[4].debt, 52000);
      expect(result[4].netWorth, 6000 - 52000);
      // Октябрь: платёж по кредиту уменьшает и счёт, и долг.
      expect(result[5].assets, 5000);
      expect(result[5].debt, 51000);
    });

    test('отрицательный остаток счёта не уменьшает активы', () {
      final result = buildNetWorthHistory(
        accounts: [
          account('a', FinanceAccountKind.account, -300),
          account('b', FinanceAccountKind.deposit, 700),
        ],
        transactions: const [],
        endMonth: DateTime(2026, 10),
      );
      expect(result.last.assets, 700);
      expect(result.last.netWorth, 700);
    });
  });

  group('репозиторий', () {
    late AppDatabase db;
    late FinanceRepository repo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = FinanceRepository(db);
    });

    tearDown(() => db.close());

    Future<double?> limitAt(DateTime month) async => effectiveBudgetLimit(
          await repo.watchBudgets().first,
          FinanceCategoryIds.food,
          month,
        );

    test('лимит задаётся, переопределяется и снимается по месяцам', () async {
      await repo.setCategoryBudget(
        categoryId: FinanceCategoryIds.food,
        month: DateTime(2026, 3),
        limit: 10000,
      );
      await repo.setCategoryBudget(
        categoryId: FinanceCategoryIds.food,
        month: DateTime(2026, 6),
        limit: 12000.555,
      );
      expect(await limitAt(DateTime(2026, 4)), 10000);
      expect(await limitAt(DateTime(2026, 7)), 12000.56);

      // Снятие с июня: остаётся нулевая запись, перекрывающая мартовский.
      await repo.setCategoryBudget(
        categoryId: FinanceCategoryIds.food,
        month: DateTime(2026, 6),
      );
      expect(await limitAt(DateTime(2026, 5)), 10000);
      expect(await limitAt(DateTime(2026, 7)), isNull);

      // Снятие с марта: унаследовать нечего — запись удаляется.
      await repo.setCategoryBudget(
        categoryId: FinanceCategoryIds.food,
        month: DateTime(2026, 3),
      );
      final all = await db.select(db.categoryBudgets).get();
      final march = all.firstWhere((b) => b.period == 202603);
      expect(march.deletedAt, isNotNull);
      expect(await limitAt(DateTime(2026, 4)), isNull);

      // Повторная установка «воскрешает» запись с тем же id.
      await repo.setCategoryBudget(
        categoryId: FinanceCategoryIds.food,
        month: DateTime(2026, 3),
        limit: 8000,
      );
      expect(await limitAt(DateTime(2026, 4)), 8000);
      expect((await db.select(db.categoryBudgets).get()).length, 2);
    });

    test('лимиты синхронизируются между устройствами', () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final other = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(other.close);
      await repo.setCategoryBudget(
        categoryId: FinanceCategoryIds.food,
        month: DateTime(2026, 10),
        limit: 9000,
      );
      final engine = SyncEngine(db);
      expect(engine.tableNames, contains('category_budgets'));
      final payload = await engine.exportToSyncPayload();
      await SyncEngine(other).mergeFromSyncPayload(payload);
      final synced = await FinanceRepository(other).watchBudgets().first;
      expect(
        effectiveBudgetLimit(
            synced, FinanceCategoryIds.food, DateTime(2026, 11)),
        9000,
      );
    });
  });

  test('миграция v11 → v12 создаёт таблицу бюджетов', () async {
    final dir = Directory.systemTemp.createTempSync('budgets_migration');
    final file = File('${dir.path}/test.sqlite');

    final old = AppDatabase.forTesting(NativeDatabase(file));
    await old.customSelect('SELECT 1').get();
    await old.customStatement('DROP TABLE category_budgets');
    await old.customStatement('PRAGMA user_version = 11');
    await old.close();

    final db = AppDatabase.forTesting(NativeDatabase(file));
    try {
      await FinanceRepository(db).setCategoryBudget(
        categoryId: FinanceCategoryIds.food,
        month: DateTime(2026, 10),
        limit: 100,
      );
      expect((await db.select(db.categoryBudgets).get()).single.period,
          202610);
    } finally {
      await db.close();
      dir.deleteSync(recursive: true);
    }
  });

  group('экран', () {
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

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> openScreen(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 4000));
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

    testWidgets('бюджет категории, предупреждение и графики в обзоре',
        (tester) async {
      final now = DateTime.now();
      await tester.runAsync(() async {
        await repo.createTransaction(
          type: FinanceTransactionType.income,
          amount: 50000,
          accountId: defaultFinanceAccountId,
          categoryId: FinanceCategoryIds.salary,
          date: DateTime(now.year, now.month, 1, 9),
        );
        await repo.createTransaction(
          type: FinanceTransactionType.expense,
          amount: 4600,
          accountId: defaultFinanceAccountId,
          categoryId: FinanceCategoryIds.food,
          date: DateTime(now.year, now.month, 1, 10),
        );
        await repo.setCategoryBudget(
          categoryId: FinanceCategoryIds.food,
          month: DateTime(now.year, now.month),
          limit: 5000,
        );
      });
      await openScreen(tester);

      expect(find.text('Бюджеты по категориям'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('budget_spent_${FinanceCategoryIds.food}')),
        findsOneWidget,
      );
      expect(find.textContaining('из 5 000 ₽'), findsWidgets);
      expect(find.text('92%'), findsOneWidget);
      // 92% лимита — предупреждение в «Доступно сегодня».
      expect(find.byKey(const ValueKey('safe_budget_alerts')), findsOneWidget);
      expect(container.read(budgetAlertsProvider).single.category.id,
          FinanceCategoryIds.food);

      expect(find.byKey(const ValueKey('cashflow_chart')), findsOneWidget);
      expect(find.byKey(const ValueKey('net_worth_chart')), findsOneWidget);
      expect(find.byKey(const ValueKey('net_worth_current')), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('лимит создаётся из диалога', (tester) async {
      await openScreen(tester);
      expect(find.byKey(const ValueKey('budgets_empty')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('add_budget')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('budget_category')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Транспорт').last);
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('budget_limit')), '3 000');
      await tester.tap(find.byKey(const ValueKey('budget_submit')));
      await settle(tester);
      await tester.pumpAndSettle();

      final statuses = container.read(categoryBudgetsProvider).value!;
      expect(statuses.single.category.id, FinanceCategoryIds.transport);
      expect(statuses.single.limit, 3000);
      expect(
        find.byKey(
            const ValueKey('budget_${FinanceCategoryIds.transport}')),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}
