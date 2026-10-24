import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../features/finance/domain/finance_category_presets.dart';
import '../../features/finance/domain/finance_enums.dart';
import '../../features/tasks/domain/task_category.dart';
import 'tables/app_settings_table.dart';
import 'tables/categories_table.dart';
import 'tables/challenge_habits_table.dart';
import 'tables/challenges_table.dart';
import 'tables/finance_accounts_table.dart';
import 'tables/finance_categories_table.dart';
import 'tables/finance_transactions_table.dart';
import 'tables/habit_logs_table.dart';
import 'tables/habits_table.dart';
import 'tables/notes_table.dart';
import 'tables/obligations_table.dart';
import 'tables/routine_daily_logs_table.dart';
import 'tables/routine_items_table.dart';
import 'tables/tasks_table.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [
  Categories,
  Tasks,
  Habits,
  HabitLogs,
  Challenges,
  ChallengeHabits,
  AppSettings,
  FinanceAccounts,
  FinanceCategories,
  FinanceTransactions,
  Obligations,
  RoutineItems,
  RoutineDailyLogs,
  Notes,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 11;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (m) async {
        await m.createAll();
        await _seedCategories();
        await _seedFinance();
      },
      onUpgrade: (m, from, to) async {
        if (from < 2) {
          await m.createTable(appSettings);
        }
        if (from < 3) {
          // Флаг is_chore заменён категориями задач.
          await _seedCategories();
          await customStatement(
            "UPDATE tasks SET category_id = '${TaskCategory.home.id}' "
            'WHERE is_chore = 1 AND category_id IS NULL',
          );
          // Пересоздание таблицы без колонки is_chore.
          // Колонки напоминания (v6) в старой таблице ещё отсутствуют.
          await m.alterTable(TableMigration(
            tasks,
            newColumns: [tasks.reminderAt, tasks.isReminderSent],
          ));
        }
        if (from < 4) {
          await m.createTable(financeAccounts);
          await m.createTable(financeCategories);
          await m.createTable(obligations);
          await m.createTable(financeTransactions);
          await _seedFinance();
        }
        if (from < 5) {
          await m.createTable(routineItems);
          await m.createTable(routineDailyLogs);
        }
        if (from < 6) {
          // Пересоздание таблицы на шаге v3 уже могло добавить колонки.
          await _addMissingColumns(
              m, tasks, [tasks.reminderAt, tasks.isReminderSent]);
        }
        if (from < 7) {
          // Таблица, созданная на шаге v4, уже содержит эти колонки.
          await _addMissingColumns(m, financeAccounts, [
            financeAccounts.isFlexibleSchedule,
            financeAccounts.nextPaymentDate,
            financeAccounts.nextPaymentAmount,
          ]);
        }
        if (from < 8) {
          await m.createTable(notes);
        }
        if (from < 9) {
          // Таблица, созданная на шаге v4, уже содержит эту колонку.
          await _addMissingColumns(m, obligations, [obligations.skippedMonth]);
        }
        if (from < 10) {
          await _addMissingColumns(m, obligations, [
            obligations.isVariableAmount,
            obligations.estimatedAmount,
            obligations.accountId,
          ]);
        }
        if (from < 11) {
          // Таблица, созданная на шаге v4, уже содержит эту колонку.
          await _addMissingColumns(
              m, financeAccounts, [financeAccounts.initialBalance]);
          await _deriveInitialBalances();
        }
      },
    );
  }

  /// Добавляет в [table] те из [columns], которых в ней ещё нет.
  Future<void> _addMissingColumns(
    Migrator m,
    TableInfo table,
    List<GeneratedColumn> columns,
  ) async {
    final existing =
        (await customSelect('PRAGMA table_info(${table.actualTableName})')
                .get())
            .map((row) => row.read<String>('name'))
            .toSet();
    for (final column in columns) {
      if (!existing.contains(column.name)) {
        await m.addColumn(table, column);
      }
    }
  }

  /// Подбирает `initial_balance` так, чтобы баланс, пересчитанный по
  /// операциям, совпал с накопленным до v11 `balance`
  /// (та же формула, что `initialBalanceFor`).
  Future<void> _deriveInitialBalances() {
    final income = FinanceTransactionType.income.value;
    final liabilities = [
      for (final k in FinanceAccountKind.values)
        if (k.isLiability) k.value,
    ].join(', ');
    return customStatement('''
      UPDATE finance_accounts SET initial_balance = ROUND(
        balance - (CASE WHEN kind IN ($liabilities) THEN -1 ELSE 1 END) *
        COALESCE((
          SELECT SUM(
            CASE WHEN t.account_id = finance_accounts.id
              THEN (CASE WHEN t.type = $income THEN t.amount ELSE -t.amount END)
              ELSE 0 END +
            CASE WHEN t.type <> $income
                AND t.target_account_id = finance_accounts.id
              THEN t.amount ELSE 0 END)
          FROM finance_transactions t
          WHERE t.deleted_at IS NULL
        ), 0), 2)
    ''');
  }

  /// Предустановленные категории финансов и счёт по умолчанию (идемпотентно).
  Future<void> _seedFinance() async {
    final now = DateTime.now().toUtc();
    await batch((b) {
      b.insertAll(
        financeCategories,
        [
          for (final c in financeCategoryPresets)
            FinanceCategoriesCompanion.insert(
              id: c.id,
              createdAt: now,
              updatedAt: now,
              name: c.name,
              color: c.colorHex,
              icon: Value(c.iconKey),
              isIncome: Value(c.isIncome),
              isSystem: const Value(true),
            ),
        ],
        mode: InsertMode.insertOrIgnore,
      );
      b.insert(
        financeAccounts,
        FinanceAccountsCompanion.insert(
          id: defaultFinanceAccountId,
          createdAt: now,
          updatedAt: now,
          name: 'Основной счёт',
        ),
        mode: InsertMode.insertOrIgnore,
      );
    });
  }

  /// Заполняет `categories` предустановленными категориями (идемпотентно).
  Future<void> _seedCategories() async {
    final now = DateTime.now().toUtc();
    await batch((b) {
      b.insertAll(
        categories,
        [
          for (final c in TaskCategory.values)
            CategoriesCompanion.insert(
              id: c.id,
              createdAt: now,
              updatedAt: now,
              name: c.label,
              color: Value(c.colorHex),
              icon: Value(c.icon.codePoint.toString()),
            ),
        ],
        mode: InsertMode.insertOrIgnore,
      );
    });
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'home_organizer.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
