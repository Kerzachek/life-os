import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../domain/habit_frequency.dart';

final habitsRepositoryProvider = Provider<HabitsRepository>((ref) {
  return HabitsRepository(ref.watch(appDatabaseProvider));
});

class HabitsRepository {
  final AppDatabase _db;
  final _uuid = const Uuid();

  HabitsRepository(this._db);

  /// Поток активных привычек
  Stream<List<HabitEntity>> watchHabits() {
    return (_db.select(_db.habits)
          ..where((h) => h.deletedAt.isNull() & h.isArchived.equals(false))
          ..orderBy([
            (h) =>
                OrderingTerm(expression: h.createdAt, mode: OrderingMode.asc),
          ]))
        .watch();
  }

  /// Поток всех логов привычек
  Stream<List<HabitLogEntity>> watchAllHabitLogs() {
    return (_db.select(_db.habitLogs)
          ..where((l) => l.deletedAt.isNull())
          ..orderBy([
            (l) => OrderingTerm(
              expression: l.completedAt,
              mode: OrderingMode.desc,
            ),
          ]))
        .watch();
  }

  /// Создание новой привычки
  Future<void> createHabit({
    required String title,
    String? description,
    HabitFrequencyType frequencyType = HabitFrequencyType.daily,
    int targetValue = 1,
    String? unit,
    String? color,
    String? icon,
  }) async {
    final now = DateTime.now().toUtc();
    final companion = HabitsCompanion.insert(
      id: _uuid.v4(),
      createdAt: now,
      updatedAt: now,
      title: title,
      description: Value(description),
      frequencyType: Value(frequencyType.value),
      targetValue: Value(targetValue),
      unit: Value(unit),
      color: Value(color),
      icon: Value(icon),
    );
    await _db.into(_db.habits).insert(companion);
  }

  /// Обновление параметров привычки. Логи выполнения (а значит, история и
  /// серии) привязаны к id привычки и не затрагиваются.
  Future<void> updateHabit({
    required String id,
    required String title,
    String? description,
    HabitFrequencyType frequencyType = HabitFrequencyType.daily,
    int targetValue = 1,
    String? unit,
    String? color,
    String? icon,
  }) async {
    await (_db.update(_db.habits)..where((h) => h.id.equals(id))).write(
      HabitsCompanion(
        title: Value(title),
        description: Value(description),
        frequencyType: Value(frequencyType.value),
        targetValue: Value(targetValue),
        unit: Value(unit),
        color: Value(color),
        icon: Value(icon),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  /// Переключение выполнения привычки за дату (check-in / toggle)
  Future<void> toggleHabitCheckIn({
    required String habitId,
    required DateTime date,
    int targetValue = 1,
  }) async {
    final now = DateTime.now().toUtc();
    final dateLocal = DateTime(date.year, date.month, date.day);

    final existingLogs = await (_db.select(
      _db.habitLogs,
    )..where((l) => l.habitId.equals(habitId) & l.deletedAt.isNull())).get();

    HabitLogEntity? todayLog;
    for (final log in existingLogs) {
      final logDate = log.completedAt.toLocal();
      if (logDate.year == dateLocal.year &&
          logDate.month == dateLocal.month &&
          logDate.day == dateLocal.day) {
        todayLog = log;
        break;
      }
    }

    if (todayLog != null) {
      // Отменяем запись
      await (_db.update(
        _db.habitLogs,
      )..where((l) => l.id.equals(todayLog!.id))).write(
        HabitLogsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
    } else {
      // Добавляем запись о выполнении
      final companion = HabitLogsCompanion.insert(
        id: _uuid.v4(),
        createdAt: now,
        updatedAt: now,
        habitId: habitId,
        completedAt: date.toUtc(),
        value: Value(targetValue),
      );
      await _db.into(_db.habitLogs).insert(companion);
    }
  }

  /// Мягкое удаление привычки
  Future<void> deleteHabit(String id) async {
    final now = DateTime.now().toUtc();
    await (_db.update(_db.habits)..where((h) => h.id.equals(id))).write(
      HabitsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }

  /// Поток активных челленджей
  Stream<List<ChallengeEntity>> watchActiveChallenges() {
    return (_db.select(_db.challenges)
          ..where((c) => c.deletedAt.isNull())
          ..orderBy([
            (c) =>
                OrderingTerm(expression: c.startDate, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  /// Создание челленджа
  Future<void> createChallenge({
    required String title,
    String? description,
    required DateTime startDate,
    required DateTime endDate,
    List<String>? habitIds,
  }) async {
    final now = DateTime.now().toUtc();
    final challengeId = _uuid.v4();

    final companion = ChallengesCompanion.insert(
      id: challengeId,
      createdAt: now,
      updatedAt: now,
      title: title,
      description: Value(description),
      startDate: startDate.toUtc(),
      endDate: endDate.toUtc(),
      status: const Value(1), // 1 = active
    );

    await _db.into(_db.challenges).insert(companion);

    if (habitIds != null && habitIds.isNotEmpty) {
      for (final habitId in habitIds) {
        final linkCompanion = ChallengeHabitsCompanion.insert(
          id: _uuid.v4(),
          createdAt: now,
          updatedAt: now,
          challengeId: challengeId,
          habitId: habitId,
        );
        await _db.into(_db.challengeHabits).insert(linkCompanion);
      }
    }
  }
}
