import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/database/app_database.dart';
import 'package:home_organizer/core/database/database_provider.dart';
import 'package:home_organizer/core/theme/app_theme.dart';
import 'package:home_organizer/features/finance/data/repositories/finance_repository.dart';
import 'package:home_organizer/features/finance/domain/finance_category_presets.dart';
import 'package:home_organizer/features/finance/domain/finance_enums.dart';
import 'package:home_organizer/features/finance/presentation/providers/finance_provider.dart';
import 'package:home_organizer/features/finance/presentation/widgets/safe_to_spend_card.dart';

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

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> pumpCard(WidgetTester tester, {bool compact = false}) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkLauncherTheme,
          home: Scaffold(body: SafeToSpendCard(compact: compact)),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> closeCard(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('показывает остаток, норму и детализацию; плашка при перерасходе',
      (tester) async {
    await tester.runAsync(() async {
      await repo.createTransaction(
        type: FinanceTransactionType.income,
        amount: 1000,
        accountId: defaultFinanceAccountId,
        categoryId: FinanceCategoryIds.salary,
        date: DateTime.now().subtract(const Duration(days: 40)),
      );
    });
    await pumpCard(tester);

    expect(find.text('Доступно сегодня'), findsOneWidget);
    expect(find.textContaining('из нормы'), findsOneWidget);
    expect(find.textContaining('Свободно до конца месяца'), findsOneWidget);
    expect(find.textContaining('Зарезервировано под обязательные платежи'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('safe_overspent_banner')), findsNothing);

    // Крупная трата сегодня: норма (≤ 1000) заведомо меньше траты 990 при
    // наличии нескольких оставшихся дней, либо ровно равна ей в последний день.
    await tester.runAsync(() async {
      await repo.createTransaction(
        type: FinanceTransactionType.expense,
        amount: 990,
        accountId: defaultFinanceAccountId,
        categoryId: FinanceCategoryIds.food,
      );
    });
    await settle(tester);

    final budget = container.read(dailySafeBudgetProvider).value!;
    expect(budget.spentToday, 990);
    expect(budget.liquidBalance, 10);
    expect(budget.freePoolAtStartOfDay, 1000);

    final lastDay = budget.daysRemaining == 1;
    expect(budget.isOverspent, !lastDay ? isTrue : isFalse);
    expect(
      find.byKey(const ValueKey('safe_overspent_banner')),
      lastDay ? findsNothing : findsOneWidget,
    );

    await closeCard(tester);
  });

  testWidgets('compact скрывает детализацию', (tester) async {
    await pumpCard(tester, compact: true);

    expect(find.byKey(const ValueKey('safe_remaining_today')), findsOneWidget);
    expect(find.textContaining('Свободно до конца месяца'), findsNothing);

    await closeCard(tester);
  });

  test('провайдер: оплата обязательного платежа не меняет норму', () async {
    final subscription = container.listen(dailySafeBudgetProvider, (_, _) {});
    addTearDown(subscription.close);

    await repo.createTransaction(
      type: FinanceTransactionType.income,
      amount: 30000,
      accountId: defaultFinanceAccountId,
      categoryId: FinanceCategoryIds.salary,
      date: DateTime.now().subtract(const Duration(days: 40)),
    );
    final obligationId = await repo.createObligation(
      name: 'Аренда',
      amount: 20000,
      dueDay: 28,
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final before = container.read(dailySafeBudgetProvider).value!;
    expect(before.unpaidObligations, 20000);

    final paid = await repo.payObligation(
      obligationId: obligationId,
      fromAccountId: defaultFinanceAccountId,
    );
    expect(paid, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final after = container.read(dailySafeBudgetProvider).value!;

    expect(after.liquidBalance, before.liquidBalance - 20000);
    expect(after.unpaidObligations, 0);
    expect(after.spentToday, 0);
    expect(after.dailyAllowance, closeTo(before.dailyAllowance, 1e-9));
    expect(after.remainingToday, closeTo(before.remainingToday, 1e-9));
  });
}
