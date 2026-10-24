import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/database/app_database.dart';
import 'package:home_organizer/core/database/database_provider.dart';
import 'package:home_organizer/features/finance/data/repositories/finance_repository.dart';
import 'package:home_organizer/features/finance/domain/finance_category_presets.dart';
import 'package:home_organizer/features/finance/domain/finance_enums.dart';
import 'package:home_organizer/features/finance/domain/transactions_csv.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late FinanceRepository repo;
  final now = DateTime(2026, 3, 15, 12);

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

  Future<String> export(CsvExportRange range) async => buildTransactionsCsv(
    transactions: await repo.getTransactions(),
    accounts: {for (final a in await repo.getAllAccounts()) a.id: a},
    categories: {for (final c in await repo.getAllCategories()) c.id: c},
    range: range,
    now: now,
  );

  List<String> lines(String csv) =>
      csv.split('\r\n').where((l) => l.isNotEmpty).toList();

  test('BOM, заголовок и строки по возрастанию даты', () async {
    final card = await repo.createAccount(
      name: 'Кредитка',
      kind: FinanceAccountKind.creditCard,
    );
    await repo.createTransaction(
      type: FinanceTransactionType.income,
      amount: 50000,
      accountId: defaultFinanceAccountId,
      categoryId: FinanceCategoryIds.salary,
      date: DateTime(2026, 3, 10, 9, 30),
    );
    await repo.createTransaction(
      type: FinanceTransactionType.expense,
      amount: 1234.5,
      accountId: defaultFinanceAccountId,
      categoryId: FinanceCategoryIds.food,
      note: 'Кофе; "латте"',
      date: DateTime(2026, 3, 1, 8, 5),
    );
    await repo.createTransaction(
      type: FinanceTransactionType.transfer,
      amount: 100,
      accountId: defaultFinanceAccountId,
      targetAccountId: card,
      date: DateTime(2026, 3, 12, 18),
    );

    final csv = await export(CsvExportRange.all);

    expect(
      csv.startsWith(
        '\uFEFFДата и время;Тип;Сумма;Валюта;'
        'Счёт списания;Счёт зачисления;Категория;Описание/Заметка\r\n',
      ),
      isTrue,
    );
    final rows = lines(csv).skip(1).toList();
    final main = (await repo.getAccounts())
        .firstWhere((a) => a.id == defaultFinanceAccountId)
        .name;
    final food = (await repo.getCategories())
        .firstWhere((c) => c.id == FinanceCategoryIds.food)
        .name;
    final salary = (await repo.getCategories())
        .firstWhere((c) => c.id == FinanceCategoryIds.salary)
        .name;
    expect(rows, [
      '01.03.2026 08:05;Расход;1234,50;RUB;$main;;$food;"Кофе; ""латте"""',
      '10.03.2026 09:30;Доход;50000,00;RUB;;$main;$salary;',
      '12.03.2026 18:00;Перевод;100,00;RUB;$main;Кредитка;;',
    ]);
  });

  test('диапазоны: этот месяц и прошлый месяц', () async {
    for (final date in [
      DateTime(2026, 1, 31, 23, 59),
      DateTime(2026, 2, 1),
      DateTime(2026, 2, 28, 23, 59),
      DateTime(2026, 3, 1),
    ]) {
      await repo.createTransaction(
        type: FinanceTransactionType.expense,
        amount: 1,
        accountId: defaultFinanceAccountId,
        date: date,
      );
    }

    List<String> dates(String csv) => [
      for (final l in lines(csv).skip(1)) l.substring(0, 10),
    ];

    expect(dates(await export(CsvExportRange.thisMonth)), ['01.03.2026']);
    expect(dates(await export(CsvExportRange.lastMonth)), [
      '01.02.2026',
      '28.02.2026',
    ]);
    expect(lines(await export(CsvExportRange.all)), hasLength(5));
  });

  test('прошлый месяц в январе — декабрь прошлого года', () {
    expect(
      CsvExportRange.lastMonth.contains(
        DateTime(2025, 12, 31),
        DateTime(2026, 1, 10),
      ),
      isTrue,
    );
    expect(
      CsvExportRange.lastMonth.contains(
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 10),
      ),
      isFalse,
    );
  });

  test('удалённые операции не выгружаются', () async {
    await repo.createTransaction(
      type: FinanceTransactionType.expense,
      amount: 10,
      accountId: defaultFinanceAccountId,
      date: DateTime(2026, 3, 2),
    );
    final removed = await repo.createTransaction(
      type: FinanceTransactionType.expense,
      amount: 20,
      accountId: defaultFinanceAccountId,
      date: DateTime(2026, 3, 3),
    );
    await repo.deleteTransaction(removed);

    final rows = lines(await export(CsvExportRange.all)).skip(1).toList();

    expect(rows, hasLength(1));
    expect(rows.single, startsWith('02.03.2026 00:00;Расход;10,00;'));
  });

  test('счёт, удалённый на другом устройстве, остаётся в названии', () async {
    final wallet = await repo.createAccount(
      name: 'Наличные',
      kind: FinanceAccountKind.account,
      balance: 500,
    );
    await repo.createTransaction(
      type: FinanceTransactionType.expense,
      amount: 10,
      accountId: wallet,
      date: DateTime(2026, 3, 2),
    );
    // Как после слияния: счёт помечен удалённым, операция — нет.
    await (db.update(db.financeAccounts)..where((a) => a.id.equals(wallet)))
        .write(FinanceAccountsCompanion(deletedAt: Value(DateTime.now())));

    final rows = lines(await export(CsvExportRange.all)).skip(1).toList();

    expect(
      rows.single,
      startsWith('02.03.2026 00:00;Расход;10,00;RUB;Наличные;'),
    );
  });

  test('имя файла', () {
    expect(
      transactionsCsvFileName(CsvExportRange.lastMonth, now),
      'LifeOS_Transactions_last-month_2026-03-15.csv',
    );
  });
}
