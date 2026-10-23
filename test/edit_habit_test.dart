import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/database/app_database.dart';
import 'package:home_organizer/core/database/database_provider.dart';
import 'package:home_organizer/core/theme/app_theme.dart';
import 'package:home_organizer/features/habits/data/repositories/habits_repository.dart';
import 'package:home_organizer/features/habits/domain/habit_appearance.dart';
import 'package:home_organizer/features/habits/domain/habit_frequency.dart';
import 'package:home_organizer/features/habits/presentation/screens/habits_screen.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late HabitsRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    repo = container.read(habitsRepositoryProvider);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<HabitEntity> singleHabit() async =>
      (await db.select(db.habits).get()).single;

  test('updateHabit меняет параметры и не трогает логи', () async {
    await repo.createHabit(title: 'Зарядка', targetValue: 1, unit: 'раз');
    final habit = await singleHabit();
    final today = DateTime.now();
    await repo.toggleHabitCheckIn(habitId: habit.id, date: today);
    await repo.toggleHabitCheckIn(
      habitId: habit.id,
      date: today.subtract(const Duration(days: 1)),
    );

    await repo.updateHabit(
      id: habit.id,
      title: 'Утренняя зарядка',
      description: '10 минут',
      frequencyType: HabitFrequencyType.weekly,
      targetValue: 15,
      unit: 'мин',
      color: '#FF54A0FF',
      icon: 'run',
    );

    final updated = await singleHabit();
    expect(updated.id, habit.id);
    expect(updated.title, 'Утренняя зарядка');
    expect(updated.description, '10 минут');
    expect(updated.frequencyType, HabitFrequencyType.weekly.value);
    expect(updated.targetValue, 15);
    expect(updated.unit, 'мин');
    expect(updated.color, '#FF54A0FF');
    expect(updated.icon, 'run');
    expect(updated.createdAt, habit.createdAt);

    final logs = await (db.select(db.habitLogs)
          ..where((l) => l.deletedAt.isNull()))
        .get();
    expect(logs, hasLength(2));
    expect(logs.every((l) => l.habitId == habit.id), isTrue);
  });

  testWidgets('карточка открывает предзаполненную форму редактирования',
      (tester) async {
    late String id;
    await tester.runAsync(() async {
      await repo.createHabit(
        title: 'Чтение',
        description: 'Перед сном',
        targetValue: 20,
        unit: 'стр',
      );
      id = (await singleHabit()).id;
      await repo.toggleHabitCheckIn(habitId: id, date: DateTime.now());
    });

    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkLauncherTheme,
          home: const HabitsScreen(),
        ),
      ),
    );
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey('habit_edit_$id')));
    await tester.pumpAndSettle();

    expect(find.text('Редактировать привычку'), findsOneWidget);
    expect(find.text('Сохранить'), findsOneWidget);
    final title = tester.widget<TextField>(find.descendant(
      of: find.byKey(const ValueKey('habit_title')),
      matching: find.byType(TextField),
    ));
    expect(title.controller!.text, 'Чтение');
    expect(find.text('Перед сном'), findsWidgets);

    await tester.enterText(find.byKey(const ValueKey('habit_title')), 'Книги');
    await tester.enterText(find.byKey(const ValueKey('habit_target')), '30');
    await tester.tap(find.byKey(const ValueKey('habit_icon_book')));
    await tester.tap(find.byKey(const ValueKey('habit_color_3')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('habit_submit')));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pumpAndSettle();

    final habit = (await tester.runAsync(singleHabit))!;
    expect(habit.id, id);
    expect(habit.title, 'Книги');
    expect(habit.targetValue, 30);
    expect(habit.icon, 'book');
    expect(habit.color, habitColorToHex(habitColorPalette[3]));
    final logs = (await tester.runAsync(() => db.select(db.habitLogs).get()))!;
    expect(logs.where((l) => l.deletedAt == null), hasLength(1));
    expect(find.text('Книги'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
