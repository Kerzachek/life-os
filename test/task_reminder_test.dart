import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/database/app_database.dart';
import 'package:home_organizer/core/services/notification_scheduler.dart';
import 'package:home_organizer/core/sync/sync_engine.dart';
import 'package:home_organizer/core/sync/sync_payload.dart';
import 'package:home_organizer/features/tasks/data/repositories/tasks_repository.dart';
import 'package:home_organizer/features/tasks/domain/task_priority.dart';
import 'package:home_organizer/features/tasks/domain/task_category.dart';
import 'package:home_organizer/features/tasks/domain/task_reminder.dart';
import 'package:home_organizer/features/tasks/domain/task_status.dart';

final _created = DateTime.utc(2026, 1, 1);

TaskEntity _task(
  String title, {
  DateTime? due,
  DateTime? reminderAt,
  bool sent = false,
  int status = 0,
}) =>
    TaskEntity(
      id: title,
      createdAt: _created,
      updatedAt: _created,
      title: title,
      dueDate: due,
      reminderAt: reminderAt,
      isReminderSent: sent,
      priority: 1,
      status: status,
    );

void main() {
  group('пресеты напоминания', () {
    final due = DateTime(2026, 10, 24);

    test('вычисляются от срока задачи', () {
      expect(ReminderPreset.dayOf.resolve(due), DateTime(2026, 10, 24, 9));
      expect(ReminderPreset.dayBefore.resolve(due), DateTime(2026, 10, 23, 9));
      // Срок без времени — дедлайн в конце дня.
      expect(ReminderPreset.twoHoursBefore.resolve(due),
          DateTime(2026, 10, 24, 22));
      expect(ReminderPreset.twoHoursBefore.resolve(DateTime(2026, 10, 24, 15)),
          DateTime(2026, 10, 24, 13));
      expect(ReminderPreset.none.resolve(due), isNull);
    });

    test('определяются по сохранённому времени', () {
      expect(ReminderPreset.detect(null, due), ReminderPreset.none);
      expect(ReminderPreset.detect(DateTime(2026, 10, 23, 9), due),
          ReminderPreset.dayBefore);
      expect(ReminderPreset.detect(DateTime(2026, 10, 23, 9, 30), due),
          ReminderPreset.custom);
      expect(ReminderPreset.detect(DateTime(2026, 10, 24, 9), null),
          ReminderPreset.custom);
    });
  });

  group('срабатывание напоминаний', () {
    final now = DateTime(2026, 10, 22, 12);

    test('только наступившие, неотправленные, у невыполненных задач', () {
      final due = dueTaskReminders([
        _task('Пора', reminderAt: now.subtract(const Duration(minutes: 1))),
        _task('Ровно сейчас', reminderAt: now),
        _task('Позже', reminderAt: now.add(const Duration(minutes: 1))),
        _task('Уже отправлено',
            reminderAt: now.subtract(const Duration(hours: 1)), sent: true),
        _task('Выполнено',
            reminderAt: now.subtract(const Duration(hours: 1)),
            status: TaskStatus.completed.value),
        _task('Отменено',
            reminderAt: now.subtract(const Duration(hours: 1)),
            status: TaskStatus.cancelled.value),
        _task('Без напоминания'),
      ], now);
      expect(due.map((t) => t.title), ['Пора', 'Ровно сейчас']);
    });

    test('текст уведомления: название и срок', () {
      final message = buildTaskReminder(
          _task('Оплатить счёт', due: DateTime(2026, 10, 24)));
      expect(message.title, 'Напоминание о задаче');
      expect(message.body, contains('Оплатить счёт'));
      expect(message.body, contains('24.10.2026'));
      expect(buildTaskReminder(_task('Без срока')).body, 'Без срока');
    });
  });

  group('хранение', () {
    late AppDatabase db;
    late TasksRepository repo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = TasksRepository(db);
    });
    tearDown(() => db.close());

    Future<TaskEntity> single() async =>
        (await db.select(db.tasks).get()).single;

    test('новое время напоминания сбрасывает isReminderSent', () async {
      final first = DateTime(2026, 10, 22, 9);
      await repo.createTask(title: 'T', reminderAt: first);
      final task = await single();
      expect(task.reminderAt, first);
      expect(task.isReminderSent, isFalse);

      await repo.markReminderSent(task.id);
      expect((await single()).isReminderSent, isTrue);

      Future<void> update(DateTime? reminderAt) => repo.updateTask(
            id: task.id,
            title: 'T2',
            reminderAt: reminderAt,
            priority: TaskPriority.medium,
            category: TaskCategory.defaultCategory,
          );

      // То же время — флаг сохраняется (напоминание не повторяется).
      await update(first);
      expect((await single()).isReminderSent, isTrue);

      await update(DateTime(2026, 10, 25, 9));
      expect((await single()).isReminderSent, isFalse);
    });

    test('watchPendingReminders не включает отправленные', () async {
      await repo.createTask(title: 'A', reminderAt: DateTime(2026, 10, 22));
      await repo.createTask(title: 'B');
      final pending = await repo.watchPendingReminders().first;
      expect(pending.map((t) => t.title), ['A']);
      await repo.markReminderSent(pending.single.id);
      expect(await repo.watchPendingReminders().first, isEmpty);
    });

    test('облачный снимок старой версии без полей напоминания', () async {
      final legacy = _task('legacy').toJson(serializer: syncValueSerializer)
        ..remove('reminderAt')
        ..remove('isReminderSent');
      await SyncEngine(db).mergeFromSyncPayload(SyncPayload(
        lastSyncTimestamp: _created,
        deviceId: 'old-device',
        tables: {
          'tasks': [legacy],
        },
      ));
      final task = await single();
      expect(task.reminderAt, isNull);
      expect(task.isReminderSent, isFalse);
    });

    test('поля напоминания переживают синхронизацию', () async {
      final reminder = DateTime.utc(2026, 10, 23, 6);
      final source = _task('synced', reminderAt: reminder, sent: true);
      await SyncEngine(db).mergeFromSyncPayload(SyncPayload(
        lastSyncTimestamp: _created,
        deviceId: 'other',
        tables: {
          'tasks': [source.toJson(serializer: syncValueSerializer)],
        },
      ));
      final task = await single();
      expect(task.reminderAt!.isAtSameMomentAs(reminder), isTrue);
      expect(task.isReminderSent, isTrue);
    });
  });

  test('миграция v5 → v6 добавляет поля напоминания', () async {
    final dir = Directory.systemTemp.createTempSync('reminder_migration');
    final file = File('${dir.path}/test.sqlite');

    // Имитируем базу версии 5: таблица задач без колонок напоминания.
    final old = AppDatabase.forTesting(NativeDatabase(file));
    await old.customSelect('SELECT 1').get();
    await old.customStatement(
        "INSERT INTO tasks (id, created_at, updated_at, title) "
        "VALUES ('t1', 0, 0, 'Старая')");
    await old.customStatement('ALTER TABLE tasks DROP COLUMN reminder_at');
    await old.customStatement('ALTER TABLE tasks DROP COLUMN is_reminder_sent');
    await old.customStatement('PRAGMA user_version = 5');
    await old.close();

    final db = AppDatabase.forTesting(NativeDatabase(file));
    try {
      final task = (await db.select(db.tasks).get()).single;
      expect(task.title, 'Старая');
      expect(task.reminderAt, isNull);
      expect(task.isReminderSent, isFalse);
    } finally {
      await db.close();
      dir.deleteSync(recursive: true);
    }
  });
}
