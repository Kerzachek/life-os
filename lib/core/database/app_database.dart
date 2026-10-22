import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../features/finance/domain/finance_category_presets.dart';
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
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 7;

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
