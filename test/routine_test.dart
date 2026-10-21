import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/database/app_database.dart';
import 'package:home_organizer/core/sync/sync_engine.dart';
import 'package:home_organizer/core/sync/sync_payload.dart';
import 'package:home_organizer/features/overview/domain/life_score.dart';
import 'package:home_organizer/features/routine/data/repositories/routine_repository.dart';
import 'package:home_organizer/features/routine/domain/routine_category.dart';
import 'package:home_organizer/features/routine/domain/routine_day.dart';

void main() {
  late AppDatabase db;
  late RoutineRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = RoutineRepository(db);
  });
  tearDown(() => db.close());

  Future<List<RoutineItemEntity>> items() => db.select(db.routineItems).get();
  Future<List<RoutineDailyLogEntity>> logs() =>
      db.select(db.routineDailyLogs).get();

  /// Вставляет пункт, созданный и (опционально) отмеченный в прошлом.
  Future<void> insertItem(
    String id, {
    required DateTime createdAt,
    DateTime? completedAt,
  }) {
    return db.into(db.routineItems).insert(
          RoutineItemsCompanion.insert(
            id: id,
            createdAt: createdAt.toUtc(),
            updatedAt: (completedAt ?? createdAt).toUtc(),
            title: 'Пункт $id',
            isCompleted: Value(completedAt != null),
            completedAt: Value(completedAt?.toUtc()),
          ),
        );
  }

  test('первый запуск только запоминает дату, без записи истории', () async {
    final now = DateTime(2026, 10, 21, 9);
    await insertItem('a', createdAt: DateTime(2026, 10, 20, 8));

    expect(await repo.performDailyReset(now: now), isTrue);
    expect(await logs(), isEmpty);
    expect(await repo.performDailyReset(now: now), isFalse);
  });

  test('смена суток пишет итог вчерашнего дня и снимает отметки', () async {
    final yesterday = DateTime(2026, 10, 20, 7);
    await repo.performDailyReset(now: yesterday);
    await insertItem('a', createdAt: yesterday, completedAt: DateTime(2026, 10, 20, 8));
    await insertItem('b', createdAt: yesterday, completedAt: DateTime(2026, 10, 20, 9));
    await insertItem('c', createdAt: yesterday);
    // Создан и отмечен уже сегодня — не входит во вчерашний итог.
    await insertItem('d',
        createdAt: DateTime(2026, 10, 21, 0, 0, 30),
        completedAt: DateTime(2026, 10, 21, 0, 0, 40));

    final midnight = DateTime(2026, 10, 21, 0, 1);
    expect(await repo.performDailyReset(now: midnight), isTrue);

    final log = (await logs()).single;
    expect(log.id, 'routine-2026-10-20');
    expect(log.date, '2026-10-20');
    expect(log.completedCount, 2);
    expect(log.totalCount, 3);
    expect(log.completionRate, closeTo(2 / 3, 1e-9));

    final byId = {for (final i in await items()) i.id: i};
    expect(byId['a']!.isCompleted, isFalse);
    expect(byId['b']!.isCompleted, isFalse);
    expect(byId['a']!.completedAt, isNull);
    expect(byId['d']!.isCompleted, isTrue,
        reason: 'сегодняшняя отметка не сбрасывается');
    expect(isRoutineDoneToday(byId['d']!, midnight), isTrue);

    // Повторная проверка в те же сутки ничего не меняет.
    expect(await repo.performDailyReset(now: midnight), isFalse);
  });

  test('при отключённом разделе отметки сбрасываются без истории', () async {
    final yesterday = DateTime(2026, 10, 20, 7);
    await repo.performDailyReset(now: yesterday);
    await insertItem('a', createdAt: yesterday, completedAt: yesterday);

    await repo.performDailyReset(
        now: DateTime(2026, 10, 21, 10), writeLog: false);
    expect(await logs(), isEmpty);
    expect((await items()).single.isCompleted, isFalse);
  });

  test('отметка прошлого дня не считается выполненной сегодня', () async {
    await insertItem('a',
        createdAt: DateTime(2026, 10, 19), completedAt: DateTime(2026, 10, 20, 23));
    final item = (await items()).single;
    expect(isRoutineDoneToday(item, DateTime(2026, 10, 20, 23, 30)), isTrue);
    expect(isRoutineDoneToday(item, DateTime(2026, 10, 21, 0, 0, 1)), isFalse);
  });

  test('CRUD и порядок пунктов', () async {
    await repo.createItem(title: 'Зарядка', category: RoutineCategory.morning);
    await repo.createItem(title: 'Вода');
    var list = await repo.watchItems().first;
    expect(list.map((i) => i.title), ['Зарядка', 'Вода']);
    expect(list.first.category, RoutineCategory.morning.value);

    await repo.reorder([list[1].id, list[0].id]);
    await repo.updateItem(
      id: list[1].id,
      title: 'Пить воду',
      category: RoutineCategory.day,
    );
    list = await repo.watchItems().first;
    expect(list.map((i) => i.title), ['Пить воду', 'Зарядка']);

    await repo.setCompleted(list.first.id, true);
    expect(
      isRoutineDoneToday(
          (await repo.watchItems().first).first, DateTime.now()),
      isTrue,
    );

    await repo.deleteItem(list.first.id);
    expect((await repo.watchItems().first).map((i) => i.title), ['Зарядка']);
  });

  test('история для диаграммы: пропуски и сегодняшний день', () {
    final now = DateTime(2026, 10, 21, 15);
    final history = buildRoutineHistory(
      logs: [
        RoutineDailyLogEntity(
          id: 'routine-2026-10-19',
          createdAt: now,
          updatedAt: now,
          date: '2026-10-19',
          completedCount: 3,
          totalCount: 4,
          completionRate: 0.75,
        ),
      ],
      todayCompleted: 1,
      todayTotal: 2,
      now: now,
      days: 7,
    );
    expect(history, hasLength(7));
    expect(history.last.rate, 0.5);
    expect(history[history.length - 2].hasData, isFalse); // 20.10 — пропуск
    expect(history[history.length - 3].rate, 0.75);
  });

  test('рутина и история входят в облачную синхронизацию', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final other = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(other.close);

    await insertItem('a', createdAt: DateTime(2026, 10, 20, 6));
    await repo.performDailyReset(now: DateTime(2026, 10, 20, 7));
    await repo.performDailyReset(now: DateTime(2026, 10, 21, 7));

    final payload = SyncPayload.decode(
        (await SyncEngine(db).exportToSyncPayload()).encode());
    expect(payload.tables.keys,
        containsAll(['routine_items', 'routine_daily_logs']));

    await SyncEngine(other).mergeFromSyncPayload(payload);
    expect((await other.select(other.routineItems).get()).single.title,
        'Пункт a');
    expect((await other.select(other.routineDailyLogs).get()).single.date,
        '2026-10-20');
  });

  test('Life Score учитывает рутину и нормирует веса', () {
    expect(LifeScore.calculate(routineRatio: 0.5).score, 50);
    final s = LifeScore.calculate(taskRatio: 1.0, routineRatio: 0.0);
    expect(s.score, (0.6 / 0.8 * 100).round());
  });
}
