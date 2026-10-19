import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/database/app_database.dart';
import 'package:home_organizer/features/finance/domain/finance_category_presets.dart';

import 'helpers/sync_harness.dart';

void main() {
  final h = useSyncHarness();

  group('слияние новых записей', () {
    test('запись с другого устройства вставляется локально', () async {
      await h().insertTask(h().dbA, 'task-1',
          title: 'С телефона', updatedAt: at(5));

      final result = await h().pushAtoB();

      expect(result.inserted, greaterThanOrEqualTo(1));
      final merged = await h().task(h().dbB, 'task-1');
      expect(merged, isNotNull);
      expect(merged!.title, 'С телефона');
      expect(merged.updatedAt.toUtc(), at(5));
    });

    test('зависимые записи (привычка + лог, финансы) переносятся целиком',
        () async {
      final dbA = h().dbA;
      final dbB = h().dbB;
      final now = at(1);
      await dbA.into(dbA.habits).insert(HabitsCompanion.insert(
            id: 'habit-1',
            createdAt: now,
            updatedAt: now,
            title: 'Бег',
          ));
      await dbA.into(dbA.habitLogs).insert(HabitLogsCompanion.insert(
            id: 'log-1',
            createdAt: now,
            updatedAt: now,
            habitId: 'habit-1',
            completedAt: now,
          ));
      await dbA.into(dbA.financeTransactions).insert(
            FinanceTransactionsCompanion.insert(
              id: 'tx-1',
              createdAt: now,
              updatedAt: now,
              date: now,
              amount: 150.5,
              accountId: defaultFinanceAccountId,
              note: const Value('Кофе'),
            ),
          );

      await h().pushAtoB();

      expect(await dbB.select(dbB.habits).get(), hasLength(1));
      expect((await dbB.select(dbB.habitLogs).get()).single.habitId, 'habit-1');
      final tx = (await dbB.select(dbB.financeTransactions).get()).single;
      expect(tx.amount, 150.5);
      expect(tx.note, 'Кофе');
      expect(tx.accountId, defaultFinanceAccountId);
    });

    test('повторное слияние идемпотентно', () async {
      await h().insertTask(h().dbA, 'task-1', updatedAt: at(5));

      await h().pushAtoB();
      final second = await h().pushAtoB();

      expect(second.changed, 0);
      expect(await h().dbB.select(h().dbB.tasks).get(), hasLength(1));
    });
  });

  group('конфликт версий (Last-Write-Wins)', () {
    test('более свежая облачная запись обновляет локальную', () async {
      await h().insertTask(h().dbB, 'task-1',
          title: 'Старая', updatedAt: at(10));
      await h().insertTask(h().dbA, 'task-1',
          title: 'Новая', updatedAt: at(20));

      final result = await h().pushAtoB();

      expect(result.updated, greaterThanOrEqualTo(1));
      expect((await h().task(h().dbB, 'task-1'))!.title, 'Новая');
    });

    test('более свежая локальная запись не перезатирается облаком', () async {
      await h().insertTask(h().dbB, 'task-1',
          title: 'Локальная', updatedAt: at(30));
      await h().insertTask(h().dbA, 'task-1',
          title: 'Облачная', updatedAt: at(20));

      await h().pushAtoB();

      final local = await h().task(h().dbB, 'task-1');
      expect(local!.title, 'Локальная');
      expect(local.updatedAt.toUtc(), at(30));

      // Локальная версия уходит в облако при следующем экспорте.
      final exported = await h().engineB.exportToSyncPayload();
      expect(exported.tables['tasks']!.single['title'], 'Локальная');
    });

    test('очищенное в облаке nullable-поле очищается и локально', () async {
      await h().insertTask(h().dbB, 'task-1',
          updatedAt: at(10), description: 'Есть описание');
      await h().insertTask(h().dbA, 'task-1', updatedAt: at(20));

      await h().pushAtoB();

      expect((await h().task(h().dbB, 'task-1'))!.description, isNull);
    });

    test('двустороннее слияние сходится к одному состоянию', () async {
      await h().insertTask(h().dbA, 'task-a', title: 'A1', updatedAt: at(10));
      await h().insertTask(h().dbB, 'task-a', title: 'B1', updatedAt: at(20));
      await h().insertTask(h().dbA, 'task-only-a', updatedAt: at(5));
      await h().insertTask(h().dbB, 'task-only-b', updatedAt: at(6));

      await h().pushAtoB();
      await h().pushBtoA();

      for (final db in [h().dbA, h().dbB]) {
        expect((await h().task(db, 'task-a'))!.title, 'B1');
        expect(await h().task(db, 'task-only-a'), isNotNull);
        expect(await h().task(db, 'task-only-b'), isNotNull);
      }
    });
  });
}
