import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/database/app_database.dart';
import 'package:home_organizer/core/database/database_provider.dart';
import 'package:home_organizer/features/finance/data/repositories/finance_repository.dart';
import 'package:home_organizer/features/finance/domain/finance_calculations.dart';
import 'package:home_organizer/features/finance/domain/finance_category_presets.dart';
import 'package:home_organizer/features/finance/domain/finance_enums.dart';

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

  Future<FinanceAccountEntity> account(String id) async =>
      (await repo.getAccounts()).firstWhere((a) => a.id == id);

  group('сидирование', () {
    test('предустановленные категории и счёт по умолчанию', () async {
      final categories = await repo.getCategories();
      expect(categories.length, financeCategoryPresets.length);
      expect(categories.every((c) => c.isSystem), isTrue);
      final names = categories.map((c) => c.name);
      expect(
          names, containsAll(['Кредиты', 'Обязательные платежи', 'Транспорт']));
      expect(categories.where((c) => c.isIncome), isNotEmpty);

      final accounts = await repo.getAccounts();
      expect(accounts.single.id, defaultFinanceAccountId);
    });
  });

  group('операции и балансы', () {
    test('доход увеличивает, расход уменьшает баланс; откат при удалении',
        () async {
      await repo.createTransaction(
        type: FinanceTransactionType.income,
        amount: 1000,
        accountId: defaultFinanceAccountId,
        categoryId: FinanceCategoryIds.salary,
      );
      final expenseId = await repo.createTransaction(
        type: FinanceTransactionType.expense,
        amount: 250.5,
        accountId: defaultFinanceAccountId,
        categoryId: FinanceCategoryIds.food,
      );
      expect((await account(defaultFinanceAccountId)).balance, 749.5);

      await repo.deleteTransaction(expenseId);
      expect((await account(defaultFinanceAccountId)).balance, 1000);
      expect((await repo.getTransactions()).length, 1);
    });

    test('редактирование пересчитывает баланс', () async {
      final id = await repo.createTransaction(
        type: FinanceTransactionType.expense,
        amount: 100,
        accountId: defaultFinanceAccountId,
      );
      await repo.updateTransaction(
        id: id,
        type: FinanceTransactionType.income,
        amount: 40,
        accountId: defaultFinanceAccountId,
        date: DateTime.now(),
        note: '  возврат ',
      );
      expect((await account(defaultFinanceAccountId)).balance, 40);
      final tx = (await repo.getTransactions()).single;
      expect(tx.note, 'возврат');
      expect(tx.type, FinanceTransactionType.income.value);
    });

    test('некорректные данные отклоняются', () async {
      expect(
        () => repo.createTransaction(
          type: FinanceTransactionType.expense,
          amount: 0,
          accountId: defaultFinanceAccountId,
        ),
        throwsArgumentError,
      );
      expect(
        () => repo.createTransaction(
          type: FinanceTransactionType.transfer,
          amount: 10,
          accountId: defaultFinanceAccountId,
        ),
        throwsArgumentError,
      );
      expect(
        () => repo.createTransaction(
          type: FinanceTransactionType.transfer,
          amount: 10,
          accountId: defaultFinanceAccountId,
          targetAccountId: defaultFinanceAccountId,
        ),
        throwsArgumentError,
      );
      expect(await repo.getTransactions(), isEmpty);
    });
  });

  group('кредиты', () {
    test('платёж уменьшает долг и попадает в расходы', () async {
      final loanId = await repo.createAccount(
        name: 'Авто',
        kind: FinanceAccountKind.loan,
        balance: 100000,
        targetAmount: 120000,
        interestRate: 12.5,
        monthlyPayment: 5000,
        paymentDay: 15,
      );
      await repo.recordLoanPayment(
        loanId: loanId,
        fromAccountId: defaultFinanceAccountId,
        amount: 5000,
      );

      expect((await account(loanId)).balance, 95000);
      expect((await account(defaultFinanceAccountId)).balance, -5000);

      final tx = (await repo.getTransactions()).single;
      expect(tx.type, FinanceTransactionType.expense.value);
      expect(tx.categoryId, FinanceCategoryIds.loans);
      expect(tx.targetAccountId, loanId);

      // Откат платежа возвращает долг.
      await repo.deleteTransaction(tx.id);
      expect((await account(loanId)).balance, 100000);
    });

    test('кредит с платежом создаёт обязательный платёж и синхронизирует его',
        () async {
      final loanId = await repo.createAccount(
        name: 'Ипотека',
        kind: FinanceAccountKind.loan,
        balance: 1000000,
        monthlyPayment: 30000,
        paymentDay: 5,
      );
      var obligation = (await repo.getObligations()).single;
      expect(obligation.loanAccountId, loanId);
      expect(obligation.amount, 30000);
      expect(obligation.dueDay, 5);

      await repo.updateAccount(
        id: loanId,
        name: 'Ипотека',
        kind: FinanceAccountKind.loan,
        balance: 1000000,
        monthlyPayment: 32000,
        paymentDay: 10,
      );
      obligation = (await repo.getObligations()).single;
      expect(obligation.amount, 32000);
      expect(obligation.dueDay, 10);

      await repo.deleteAccount(loanId);
      expect(await repo.getObligations(), isEmpty);
    });

    test('платёж по не-кредиту отклоняется', () {
      expect(
        () => repo.recordLoanPayment(
          loanId: defaultFinanceAccountId,
          fromAccountId: defaultFinanceAccountId,
          amount: 10,
        ),
        throwsArgumentError,
      );
    });
  });

  group('депозиты', () {
    test('пополнение — перевод со счёта на депозит', () async {
      final depositId = await repo.createAccount(
        name: 'Копилка',
        kind: FinanceAccountKind.deposit,
        targetAmount: 50000,
      );
      await repo.recordDepositTopUp(
        depositId: depositId,
        fromAccountId: defaultFinanceAccountId,
        amount: 3000,
      );

      expect((await account(depositId)).balance, 3000);
      expect((await account(defaultFinanceAccountId)).balance, -3000);
      final tx = (await repo.getTransactions()).single;
      expect(tx.type, FinanceTransactionType.transfer.value);

      // Переводы не считаются расходами в диаграмме.
      final breakdown = buildExpenseBreakdown(
        transactions: [tx],
        categories: await repo.getCategories(),
        month: DateTime.now(),
      );
      expect(breakdown, isEmpty);
    });
  });

  group('обязательные платежи', () {
    test('оплата меняет статус, повторная оплата за месяц отклоняется',
        () async {
      final id = await repo.createObligation(
        name: 'Аренда',
        amount: 40000,
        dueDay: 1,
        categoryId: FinanceCategoryIds.home,
      );
      final month = DateTime.now();

      Future<List<ObligationStatus>> statuses(DateTime m) async =>
          buildObligationStatuses(
            await repo.getObligations(),
            await repo.getTransactions(),
            m,
          );

      expect((await statuses(month)).single.isPaid, isFalse);

      final ok = await repo.payObligation(
        obligationId: id,
        fromAccountId: defaultFinanceAccountId,
      );
      expect(ok, isTrue);
      final again = await repo.payObligation(
        obligationId: id,
        fromAccountId: defaultFinanceAccountId,
      );
      expect(again, isFalse);

      expect((await statuses(month)).single.isPaid, isTrue);
      expect((await repo.getTransactions()).length, 1);
      expect((await account(defaultFinanceAccountId)).balance, -40000);

      // В прошлом месяце платёж не оплачен.
      final prev = DateTime(month.year, month.month - 1);
      expect((await statuses(prev)).single.isPaid, isFalse);
    });

    test('отмена оплаты удаляет операцию и возвращает баланс', () async {
      final id = await repo.createObligation(
          name: 'Интернет', amount: 800, dueDay: 10);
      await repo.payObligation(
          obligationId: id, fromAccountId: defaultFinanceAccountId);
      expect((await account(defaultFinanceAccountId)).balance, -800);

      expect(await repo.undoObligationPayment(obligationId: id), isTrue);
      expect((await account(defaultFinanceAccountId)).balance, 0);
      expect(await repo.getTransactions(), isEmpty);
      // Отменять больше нечего, а оплатить можно снова.
      expect(await repo.undoObligationPayment(obligationId: id), isFalse);
      expect(
        await repo.payObligation(
            obligationId: id, fromAccountId: defaultFinanceAccountId),
        isTrue,
      );
    });

    test('срочность: далёкий / предстоящий / сегодня / просрочен / оплачен',
        () async {
      final now = DateTime(2026, 10, 14, 15);
      final month = DateTime(2026, 10);
      Future<String> make(String name, int day) =>
          repo.createObligation(name: name, amount: 100, dueDay: day);

      await make('далёкий', 25);
      await make('предстоящий', 16);
      await make('сегодня', 14);
      await make('просрочен', 3);
      final paidId = await make('оплачен', 1);
      await repo.payObligation(
        obligationId: paidId,
        fromAccountId: defaultFinanceAccountId,
        date: DateTime(2026, 10, 2),
      );

      final statuses = buildObligationStatuses(
        await repo.getObligations(),
        await repo.getTransactions(),
        month,
        now: now,
      );
      final byName = {for (final s in statuses) s.obligation.name: s};

      expect(byName['далёкий']!.urgency, ObligationUrgency.scheduled);
      expect(byName['предстоящий']!.urgency, ObligationUrgency.upcoming);
      expect(byName['предстоящий']!.daysUntilDue, 2);
      expect(byName['сегодня']!.urgency, ObligationUrgency.dueToday);
      expect(byName['просрочен']!.urgency, ObligationUrgency.overdue);
      expect(byName['просрочен']!.daysUntilDue, -11);
      expect(byName['оплачен']!.urgency, ObligationUrgency.paid);
      expect(byName['оплачен']!.needsAttention, isFalse);

      // Неоплаченные идут по сроку, оплаченные — в конце.
      expect(statuses.map((s) => s.obligation.name), [
        'просрочен',
        'сегодня',
        'предстоящий',
        'далёкий',
        'оплачен',
      ]);
    });

    test('31-е число в коротком месяце — срок в последний день', () {
      // В апреле 30 дней: срок 31-го = 30 апреля.
      expect(
        daysUntilObligationDue(31, DateTime(2026, 4), DateTime(2026, 4, 28)),
        2,
      );
      expect(
        daysUntilObligationDue(31, DateTime(2026, 4), DateTime(2026, 4, 30)),
        0,
      );
    });

    test('оплата кредитного платежа уменьшает долг', () async {
      final loanId = await repo.createAccount(
        name: 'Кредитка',
        kind: FinanceAccountKind.loan,
        balance: 20000,
        monthlyPayment: 2000,
        paymentDay: 20,
      );
      final obligation = (await repo.getObligations()).single;
      await repo.payObligation(
        obligationId: obligation.id,
        fromAccountId: defaultFinanceAccountId,
      );
      expect((await account(loanId)).balance, 18000);
    });

    test('сводка: баланс, долги, депозиты и остаток на жизнь', () async {
      await repo.createTransaction(
        type: FinanceTransactionType.income,
        amount: 100000,
        accountId: defaultFinanceAccountId,
      );
      await repo.createAccount(
        name: 'Кредит',
        kind: FinanceAccountKind.loan,
        balance: 50000,
        monthlyPayment: 10000,
        paymentDay: 10,
      );
      final depositId = await repo.createAccount(
        name: 'Вклад',
        kind: FinanceAccountKind.deposit,
      );
      await repo.recordDepositTopUp(
        depositId: depositId,
        fromAccountId: defaultFinanceAccountId,
        amount: 20000,
      );
      final rent = await repo.createObligation(
        name: 'Аренда',
        amount: 30000,
        dueDay: 1,
      );

      Future<FinanceSummary> summary() async => buildSummary(
            accounts: await repo.getAccounts(),
            obligations: buildObligationStatuses(
              await repo.getObligations(),
              await repo.getTransactions(),
              DateTime.now(),
            ),
          );

      var s = await summary();
      expect(s.totalBalance, 80000);
      expect(s.totalDebt, 50000);
      expect(s.totalDeposits, 20000);
      expect(s.obligationsTotal, 40000);
      expect(s.obligationsPaid, 0);
      expect(s.leftToLive, 40000);

      await repo.payObligation(
        obligationId: rent,
        fromAccountId: defaultFinanceAccountId,
      );
      s = await summary();
      expect(s.totalBalance, 50000);
      expect(s.obligationsPaid, 30000);
      expect(s.obligationsProgress, closeTo(0.75, 1e-9));
      // Остаётся заплатить только кредит (10 000).
      expect(s.leftToLive, 40000);
    });
  });

  group('кредитные карты', () {
    Future<String> card({double debt = 35000}) => repo.createAccount(
          name: 'Сплит',
          kind: FinanceAccountKind.creditCard,
          balance: debt,
          targetAmount: 100000,
        );

    test('доступный лимит = лимит − долг, не выходит за [0, лимит]', () async {
      final id = await card();
      final c = await account(id);
      expect(c.isCreditCard, isTrue);
      expect(c.creditLimit, 100000);
      expect(c.currentDebt, 35000);
      expect(c.availableLimit, 65000);
      expect(c.debtRatio, closeTo(0.35, 1e-9));

      final over = await card(debt: 120000);
      expect((await account(over)).availableLimit, 0);
      // Кредитка не создаёт обязательный платёж.
      expect(await repo.getObligations(), isEmpty);
    });

    test('расход растит долг, удаление операции его откатывает', () async {
      final id = await card();
      final txId = await repo.createTransaction(
        type: FinanceTransactionType.expense,
        amount: 5000,
        accountId: id,
        categoryId: FinanceCategoryIds.food,
      );
      var c = await account(id);
      expect(c.currentDebt, 40000);
      expect(c.availableLimit, 60000);

      final breakdown = buildExpenseBreakdown(
        transactions: await repo.getTransactions(),
        categories: await repo.getCategories(),
        month: DateTime(DateTime.now().year, DateTime.now().month),
      );
      expect(breakdown.single.amount, 5000);

      await repo.deleteTransaction(txId);
      c = await account(id);
      expect(c.currentDebt, 35000);
    });

    test('погашение — перевод со счёта, уменьшает долг', () async {
      final id = await card();
      await repo.createTransaction(
        type: FinanceTransactionType.income,
        amount: 50000,
        accountId: defaultFinanceAccountId,
      );
      final txId = await repo.recordCreditCardRepayment(
        cardId: id,
        fromAccountId: defaultFinanceAccountId,
        amount: 20000,
      );
      final tx = (await repo.getTransactions()).firstWhere((t) => t.id == txId);
      expect(tx.type, FinanceTransactionType.transfer.value);
      expect((await account(id)).currentDebt, 15000);
      expect((await account(id)).availableLimit, 85000);
      expect((await account(defaultFinanceAccountId)).balance, 30000);

      expect(
        () => repo.recordCreditCardRepayment(
          cardId: defaultFinanceAccountId,
          fromAccountId: id,
          amount: 1,
        ),
        throwsArgumentError,
      );
    });

    test('долг по кредитке входит в «Долги / Кредиты»', () async {
      await card();
      await repo.createAccount(
        name: 'Ипотека',
        kind: FinanceAccountKind.loan,
        balance: 50000,
      );
      final s = buildSummary(
        accounts: await repo.getAccounts(),
        obligations: const [],
      );
      expect(s.totalDebt, 85000);
      expect(s.totalBalance, 0);
    });

    test('трата с кредитки уменьшает «Доступно сегодня», если включено',
        () async {
      final id = await card(debt: 0);
      await repo.createTransaction(
        type: FinanceTransactionType.income,
        amount: 30000,
        accountId: defaultFinanceAccountId,
      );
      Future<DailySafeBudgetState> budget(bool include) async =>
          buildDailySafeBudget(
            accounts: await repo.getAccounts(),
            obligations: const [],
            transactions: await repo.getTransactions(),
            now: DateTime.now(),
            includeCreditCards: include,
          );

      final before = await budget(true);
      await repo.createTransaction(
        type: FinanceTransactionType.expense,
        amount: 1000,
        accountId: id,
        categoryId: FinanceCategoryIds.food,
      );
      final after = await budget(true);
      expect(after.spentToday, 1000);
      expect(after.creditCardDebt, 1000);
      expect(after.dailyAllowance, closeTo(before.dailyAllowance, 1e-9));
      expect(after.remainingToday,
          closeTo(before.remainingToday - 1000, 1e-9));
      expect(after.freePoolTotal, 29000);

      // Погашение со счёта не меняет бюджет: деньги ушли, долг ушёл.
      await repo.recordCreditCardRepayment(
        cardId: id,
        fromAccountId: defaultFinanceAccountId,
        amount: 1000,
      );
      expect((await budget(true)).freePoolTotal, 29000);

      final off = await budget(false);
      expect(off.spentToday, 0);
      expect(off.creditCardDebt, 0);
    });
  });

  group('категории', () {
    test('пользовательскую категорию можно создать и удалить', () async {
      final id = await repo.createCategory(
        name: 'Кофе',
        iconKey: 'coffee',
        colorHex: '#FF6366F1',
      );
      await repo.createTransaction(
        type: FinanceTransactionType.expense,
        amount: 200,
        accountId: defaultFinanceAccountId,
        categoryId: id,
      );
      expect((await repo.getCategories()).any((c) => c.id == id), isTrue);

      expect(await repo.deleteCategory(id), isTrue);
      expect((await repo.getCategories()).any((c) => c.id == id), isFalse);
      expect((await repo.getTransactions()).single.categoryId, isNull);
    });

    test('предустановленную категорию удалить нельзя', () async {
      expect(await repo.deleteCategory(FinanceCategoryIds.food), isFalse);
      expect(
        (await repo.getCategories())
            .any((c) => c.id == FinanceCategoryIds.food),
        isTrue,
      );
    });

    test('диаграмма группирует расходы месяца по категориям', () async {
      Future<void> spend(double amount, String? category, {DateTime? date}) {
        return repo.createTransaction(
          type: FinanceTransactionType.expense,
          amount: amount,
          accountId: defaultFinanceAccountId,
          categoryId: category,
          date: date,
        );
      }

      await spend(300, FinanceCategoryIds.food);
      await spend(200, FinanceCategoryIds.food);
      await spend(700, FinanceCategoryIds.transport);
      await spend(50, null);
      final lastMonth = DateTime.now().subtract(const Duration(days: 40));
      await spend(999, FinanceCategoryIds.shopping, date: lastMonth);

      final breakdown = buildExpenseBreakdown(
        transactions: await repo.getTransactions(),
        categories: await repo.getCategories(),
        month: DateTime.now(),
      );
      expect(breakdown.map((e) => e.name),
          ['Транспорт', 'Еда / Фастфуд', 'Без категории']);
      expect(breakdown.map((e) => e.amount), [700, 500, 50]);
    });
  });

  group('фильтры', () {
    final now = DateTime(2026, 10, 14, 12); // среда

    FinanceTransactionEntity tx({
      required DateTime date,
      int type = 0,
      String? category,
      String? note,
    }) {
      return FinanceTransactionEntity(
        id: '${date.microsecondsSinceEpoch}$type$category',
        createdAt: date,
        updatedAt: date,
        date: date,
        amount: 1,
        type: type,
        accountId: 'a',
        categoryId: category,
        note: note,
      );
    }

    test('период: сегодня / неделя / месяц / всё время', () {
      final today = tx(date: now);
      final monday = tx(date: DateTime(2026, 10, 12));
      final earlier = tx(date: DateTime(2026, 10, 2));
      final old = tx(date: DateTime(2026, 9, 30));

      const todayF = TransactionFilter(period: FinancePeriod.today);
      expect(todayF.matches(today, now), isTrue);
      expect(todayF.matches(monday, now), isFalse);

      const weekF = TransactionFilter(period: FinancePeriod.week);
      expect(weekF.matches(monday, now), isTrue);
      expect(weekF.matches(earlier, now), isFalse);

      const monthF = TransactionFilter(period: FinancePeriod.month);
      expect(monthF.matches(earlier, now), isTrue);
      expect(monthF.matches(old, now), isFalse);

      const allF = TransactionFilter(period: FinancePeriod.all);
      expect(allF.matches(old, now), isTrue);
    });

    test('тип, категория и поиск по заметке', () {
      final burger = tx(date: now, category: 'c1', note: 'Бургер');
      final salary = tx(date: now, type: 1);

      const incomeF = TransactionFilter(type: FinanceTransactionType.income);
      expect(incomeF.matches(salary, now), isTrue);
      expect(incomeF.matches(burger, now), isFalse);

      const catF = TransactionFilter(categoryId: 'c1');
      expect(catF.matches(burger, now), isTrue);
      expect(catF.matches(salary, now), isFalse);

      const searchF = TransactionFilter(query: ' бург ');
      expect(searchF.matches(burger, now), isTrue);
      expect(searchF.matches(salary, now), isFalse);
    });
  });
}
