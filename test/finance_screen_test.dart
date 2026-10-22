import 'package:drift/native.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/database/app_database.dart';
import 'package:home_organizer/core/database/database_provider.dart';
import 'package:home_organizer/core/theme/app_theme.dart';
import 'package:home_organizer/features/finance/data/repositories/finance_repository.dart';
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

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey('finance_tabs')),
      matching: find.text(label),
    ));
    await settle(tester);
  }

  testWidgets('четыре вкладки и сводные карточки обзора', (tester) async {
    await openScreen(tester);

    for (final label in ['Обзор', 'Продукты', 'Операции', 'Настройки']) {
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('finance_tabs')),
          matching: find.text(label),
        ),
        findsOneWidget,
      );
    }
    expect(find.text('Общий баланс'), findsOneWidget);
    expect(find.text('Долги / Кредиты'), findsOneWidget);
    expect(find.text('Отложено в депозиты'), findsOneWidget);
    expect(find.text('Осталось на жизнь'), findsOneWidget);
    expect(find.byKey(const ValueKey('chart_empty')), findsOneWidget);

    await closeScreen(tester);
  });

  testWidgets('диаграмма расходов появляется при наличии трат',
      (tester) async {
    await tester.runAsync(() async {
      await repo.createTransaction(
        type: FinanceTransactionType.expense,
        amount: 1500,
        accountId: defaultFinanceAccountId,
        categoryId: FinanceCategoryIds.food,
      );
    });
    await openScreen(tester);

    expect(find.byType(PieChart), findsOneWidget);
    expect(find.byKey(const ValueKey('chart_empty')), findsNothing);
    expect(find.text('Еда / Фастфуд'), findsOneWidget);
    expect(find.byKey(const ValueKey('chart_total')), findsOneWidget);

    await closeScreen(tester);
  });

  testWidgets('оплата обязательного платежа меняет статус и прогресс',
      (tester) async {
    late String id;
    await tester.runAsync(() async {
      id = await repo.createObligation(
        name: 'Интернет',
        amount: 800,
        dueDay: 10,
      );
    });
    await openScreen(tester);

    expect(find.text('К оплате в этом месяце'), findsOneWidget);
    expect(find.text('Интернет'), findsOneWidget);
    // Управление шаблонами убрано с обзора.
    expect(find.byKey(const ValueKey('add_obligation')), findsNothing);
    expect(find.text('Оплатить'), findsNothing);
    expect(tester.widget<CheckboxListTile>(find.byKey(ValueKey('pay_$id'))).value,
        isFalse);

    // Клик по чекбоксу → операция в ленте, платёж отмечен оплаченным.
    await tester.tap(find.byKey(ValueKey('pay_$id')));
    await settle(tester);

    expect(tester.widget<CheckboxListTile>(find.byKey(ValueKey('pay_$id'))).value,
        isTrue);
    expect(find.textContaining('· оплачено'), findsOneWidget);
    final progress = tester.widget<Text>(
      find.byKey(const ValueKey('obligations_progress_text')),
    );
    expect(progress.data, contains('800'));
    expect(progress.data, contains('осталось 0'));

    final txs = (await tester.runAsync(repo.getTransactions))!;
    expect(txs.single.obligationId, id);
    expect(txs.single.amount, 800);
    expect(txs.single.type, FinanceTransactionType.expense.value);

    await closeScreen(tester);
  });

  testWidgets('повторный клик по оплаченному чекбоксу отменяет оплату',
      (tester) async {
    late String id;
    await tester.runAsync(() async {
      id = await repo.createObligation(name: 'ЖКХ', amount: 5000, dueDay: 20);
    });
    await openScreen(tester);

    await tester.tap(find.byKey(ValueKey('pay_$id')));
    await settle(tester);
    expect((await tester.runAsync(repo.getTransactions))!.length, 1);

    await tester.tap(find.byKey(ValueKey('pay_$id')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Отменить оплату'));
    await settle(tester);

    expect((await tester.runAsync(repo.getTransactions))!, isEmpty);
    expect(tester.widget<CheckboxListTile>(find.byKey(ValueKey('pay_$id'))).value,
        isFalse);
    final account = (await tester.runAsync(repo.getAccounts))!.single;
    expect(account.balance, 0);

    await closeScreen(tester);
  });

  testWidgets('платёж со сроком сегодня подсвечивается', (tester) async {
    final today = DateTime.now().day;
    late String dueId;
    late String farId;
    await tester.runAsync(() async {
      dueId = await repo.createObligation(
          name: 'Сегодняшний', amount: 100, dueDay: today);
      // Срок как минимум через 3 дня или в прошлом — без «предстоящего».
      farId = await repo.createObligation(
        name: 'Далёкий',
        amount: 100,
        dueDay: today <= 24 ? today + 5 : 1,
      );
    });
    await openScreen(tester);

    expect(find.text('сегодня', findRichText: true, skipOffstage: false),
        findsNothing);
    expect(find.textContaining('сегодня срок оплаты'), findsOneWidget);
    expect(find.byIcon(Icons.notifications_active_outlined), findsOneWidget);
    expect(find.byKey(ValueKey('obligation_$dueId')), findsOneWidget);
    expect(find.byKey(ValueKey('obligation_$farId')), findsOneWidget);

    await closeScreen(tester);
  });

  testWidgets('настройки: шаблоны обязательных платежей создаются и удаляются',
      (tester) async {
    await openScreen(tester);
    await openTab(tester, 'Настройки');

    expect(find.byKey(const ValueKey('obligation_templates_empty')),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('add_obligation')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
        find.byKey(const ValueKey('obligation_name')), 'Аренда');
    await tester.enterText(
        find.byKey(const ValueKey('obligation_amount')), '40000');
    await tester.enterText(find.byKey(const ValueKey('obligation_day')), '5');
    await tester.tap(find.byKey(const ValueKey('obligation_submit')));
    await settle(tester);

    final created = (await tester.runAsync(repo.getObligations))!.single;
    expect(created.name, 'Аренда');
    expect(created.amount, 40000);
    expect(created.dueDay, 5);
    expect(find.byKey(ValueKey('template_${created.id}')), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('delete_template_${created.id}')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Удалить').last);
    await settle(tester);

    expect((await tester.runAsync(repo.getObligations))!, isEmpty);
    expect(find.byKey(const ValueKey('obligation_templates_empty')),
        findsOneWidget);

    await closeScreen(tester);
  });

  testWidgets('форма операции: добавление дохода обновляет ленту и баланс',
      (tester) async {
    await openScreen(tester);
    await openTab(tester, 'Операции');

    expect(find.byKey(const ValueKey('tx_empty')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('add_transaction')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey('tx_type')),
      matching: find.text('Доход'),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byKey(const ValueKey('tx_amount')), '2500,50');
    await tester.enterText(find.byKey(const ValueKey('tx_note')), 'Аванс');
    await tester.tap(find.byKey(const ValueKey('tx_submit')));
    await settle(tester);

    expect(find.byKey(const ValueKey('tx_empty')), findsNothing);
    expect(find.text('Аванс', findRichText: true), findsWidgets);

    final accounts = (await tester.runAsync(repo.getAccounts))!;
    expect(accounts.single.balance, 2500.5);

    await closeScreen(tester);
  });

  testWidgets('форма операции: валидация пустой суммы', (tester) async {
    await openScreen(tester);
    await openTab(tester, 'Операции');

    await tester.tap(find.byKey(const ValueKey('add_transaction')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('tx_submit')));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Сумма > 0'), findsOneWidget);
    expect((await tester.runAsync(repo.getTransactions))!, isEmpty);

    await closeScreen(tester);
  });

  testWidgets('фильтры ленты: тип и поиск', (tester) async {
    await tester.runAsync(() async {
      await repo.createTransaction(
        type: FinanceTransactionType.expense,
        amount: 300,
        accountId: defaultFinanceAccountId,
        categoryId: FinanceCategoryIds.food,
        note: 'Бургер',
      );
      await repo.createTransaction(
        type: FinanceTransactionType.income,
        amount: 9000,
        accountId: defaultFinanceAccountId,
        categoryId: FinanceCategoryIds.salary,
        note: 'Зарплата октября',
      );
    });
    await openScreen(tester);
    await openTab(tester, 'Операции');

    expect(find.textContaining('Бургер'), findsOneWidget);
    expect(find.textContaining('Зарплата октября'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('type_expense')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Бургер'), findsOneWidget);
    expect(find.textContaining('Зарплата октября'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('type_all')));
    await tester.enterText(find.byKey(const ValueKey('tx_search')), 'зарплата');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Бургер'), findsNothing);
    expect(find.textContaining('Зарплата октября'), findsOneWidget);

    await closeScreen(tester);
  });

  testWidgets('продукты: создание кредита через форму', (tester) async {
    await openScreen(tester);
    await openTab(tester, 'Продукты');

    await tester.tap(find.byKey(const ValueKey('add_product')));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const ValueKey('account_kind')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Кредит').last);
    await tester.pump(const Duration(milliseconds: 400));

    await tester.enterText(find.byKey(const ValueKey('account_name')), 'Авто');
    await tester.enterText(
        find.byKey(const ValueKey('account_balance')), '300000');
    await tester.enterText(
        find.byKey(const ValueKey('account_payment')), '15000');
    await tester.enterText(find.byKey(const ValueKey('account_day')), '12');
    await tester.tap(find.byKey(const ValueKey('account_submit')));
    await settle(tester);

    final accounts = (await tester.runAsync(repo.getAccounts))!;
    final loan = accounts.firstWhere((a) => a.name == 'Авто');
    expect(loan.kind, FinanceAccountKind.loan.value);
    expect(loan.balance, 300000);
    expect(loan.monthlyPayment, 15000);
    expect(loan.paymentDay, 12);
    expect(find.byKey(ValueKey('product_${loan.id}')), findsOneWidget);

    // Связанный обязательный платёж создан автоматически.
    final obligations = (await tester.runAsync(repo.getObligations))!;
    expect(obligations.single.loanAccountId, loan.id);

    await closeScreen(tester);
  });

  testWidgets('продукты: тумблер плавающих платежей меняет поля формы',
      (tester) async {
    await openScreen(tester);
    await openTab(tester, 'Продукты');

    await tester.tap(find.byKey(const ValueKey('add_product')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('account_kind')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Кредит').last);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const ValueKey('account_day')), findsOneWidget);
    expect(find.byKey(const ValueKey('account_next_date')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('account_flexible')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('account_day')), findsNothing);
    expect(find.byKey(const ValueKey('account_payment')), findsNothing);
    expect(find.byKey(const ValueKey('account_next_date')), findsOneWidget);
    expect(find.byKey(const ValueKey('account_next_amount')), findsOneWidget);

    // Без даты ближайшего списания форма не сохраняется.
    await tester.enterText(find.byKey(const ValueKey('account_name')), 'BNPL');
    await tester.enterText(
        find.byKey(const ValueKey('account_next_amount')), '2500');
    await tester.tap(find.byKey(const ValueKey('account_submit')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Выберите дату'), findsOneWidget);

    await closeScreen(tester);
  });

  testWidgets('рассрочка: бейдж, быстрая правка и оплата со сдвигом графика',
      (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    late String loanId;
    await tester.runAsync(() async {
      loanId = await repo.createAccount(
        name: 'Долями',
        kind: FinanceAccountKind.loan,
        balance: 4000,
        isFlexibleSchedule: true,
        nextPaymentDate: today,
        nextPaymentAmount: 1000,
      );
    });
    final obligationId =
        (await tester.runAsync(repo.getObligations))!.single.id;
    await openScreen(tester);

    expect(find.byKey(ValueKey('split_badge_$obligationId')), findsOneWidget);

    // Карандаш: правим сумму ближайшего списания.
    await tester.tap(find.byKey(ValueKey('edit_next_payment_$obligationId')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Ближайшее списание'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('flex_sheet_amount')), '1200');
    await tester.tap(find.byKey(const ValueKey('flex_sheet_submit')));
    await settle(tester);
    var loan = (await tester.runAsync(repo.getAccounts))!
        .firstWhere((a) => a.id == loanId);
    expect(loan.nextPaymentAmount, 1200);

    // Оплата: шторка предлагает следующий шаг через 14 дней.
    await tester.tap(find.byKey(ValueKey('pay_$obligationId')));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Следующее списание'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('flex_sheet_submit')));
    await settle(tester);

    loan = (await tester.runAsync(repo.getAccounts))!
        .firstWhere((a) => a.id == loanId);
    expect(loan.balance, 2800);
    expect(
      DateTime(loan.nextPaymentDate!.year, loan.nextPaymentDate!.month,
          loan.nextPaymentDate!.day),
      DateTime(today.year, today.month, today.day + 14),
    );

    await closeScreen(tester);
  });

  testWidgets('настройки: добавление пользовательской категории',
      (tester) async {
    await openScreen(tester);
    await openTab(tester, 'Настройки');

    expect(find.text('Кредиты'), findsOneWidget);
    // Заголовок раздела шаблонов + одноимённая предустановленная категория.
    expect(find.text('Обязательные платежи'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('add_obligation')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('add_category')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byKey(const ValueKey('category_name')), 'Кофе');
    await tester.tap(find.byKey(const ValueKey('icon_coffee')));
    await tester.tap(find.byKey(const ValueKey('color_3')));
    await tester.tap(find.byKey(const ValueKey('category_submit')));
    await settle(tester);

    final categories = (await tester.runAsync(repo.getCategories))!;
    final coffee = categories.firstWhere((c) => c.name == 'Кофе');
    expect(coffee.icon, 'coffee');
    expect(coffee.isSystem, isFalse);
    expect(coffee.isIncome, isFalse);
    expect(find.byKey(ValueKey('category_${coffee.id}')), findsOneWidget);

    await closeScreen(tester);
  });
}
