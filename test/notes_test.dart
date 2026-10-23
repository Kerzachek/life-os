import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/database/app_database.dart';
import 'package:home_organizer/core/database/database_provider.dart';
import 'package:home_organizer/core/widgets/app_sidebar.dart';
import 'package:home_organizer/core/widgets/responsive.dart';
import 'package:home_organizer/features/notes/data/repositories/notes_repository.dart';
import 'package:home_organizer/features/notes/domain/note.dart';
import 'package:home_organizer/features/notes/presentation/widgets/note_editor.dart';
import 'package:home_organizer/main.dart';

import 'helpers/sync_harness.dart';

Note _note(
  String id, {
  String title = '',
  String content = '',
  List<NoteChecklistItem> checklist = const [],
  bool isPinned = false,
  String? colorTag,
  DateTime? updatedAt,
}) {
  return Note(
    id: id,
    title: title,
    content: content,
    checklist: checklist,
    createdAt: at(0),
    updatedAt: updatedAt ?? at(1),
    isPinned: isPinned,
    colorTag: colorTag,
  );
}

Future<void> _withApp(
  WidgetTester tester,
  Size size,
  Future<void> Function(AppDatabase db) body,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final testDb = AppDatabase.forTesting(NativeDatabase.memory());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(testDb)],
      child: const HomeOrganizerApp(),
    ),
  );
  await tester.pumpAndSettle();
  try {
    await body(testDb);
  } finally {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await testDb.close();
  }
}

Future<List<Note>> _storedNotes(WidgetTester tester, AppDatabase db) async {
  final rows = await tester.runAsync(
    () => (db.select(db.notes)..where((n) => n.deletedAt.isNull())).get(),
  );
  return [for (final row in rows!) Note.fromEntity(row)];
}

void main() {
  group('модель', () {
    test('toJson / fromJson без потерь', () {
      final note = _note(
        'n1',
        title: 'Покупки',
        content: 'К ужину',
        isPinned: true,
        colorTag: 'green',
        checklist: const [
          NoteChecklistItem(id: 'i1', text: 'Хлеб', isCompleted: true),
          NoteChecklistItem(id: 'i2', text: 'Молоко'),
        ],
      );

      final restored = Note.fromJson(note.toJson());

      expect(restored.sameContentAs(note), isTrue);
      expect(restored.createdAt, note.createdAt);
      expect(restored.updatedAt, note.updatedAt);
      expect(restored.completedCount, 1);
    });

    test('повреждённый чек-лист читается как пустой', () {
      expect(Note.decodeChecklist('не json'), isEmpty);
      expect(Note.decodeChecklist('{"a": 1}'), isEmpty);
      expect(
        Note.decodeChecklist('[{"text": "без id"}, {"id": "x", "text": "ok"}]'),
        [const NoteChecklistItem(id: 'x', text: 'ok')],
      );
    });

    test('пустая заметка — без текста и пунктов', () {
      expect(_note('n').isEmpty, isTrue);
      expect(
        _note(
          'n',
          checklist: const [NoteChecklistItem(id: 'i', text: ' ')],
        ).isEmpty,
        isTrue,
      );
      expect(_note('n', content: 'x').isEmpty, isFalse);
    });
  });

  group('репозиторий', () {
    late AppDatabase db;
    late NotesRepository repo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = NotesRepository(db);
    });
    tearDown(() => db.close());

    test('закреплённые сверху, затем по времени изменения', () async {
      await repo.saveNote(_note('old', title: 'Старая', updatedAt: at(1)));
      await repo.saveNote(_note('new', title: 'Новая', updatedAt: at(5)));
      await repo.saveNote(
        _note('pin', title: 'Важное', isPinned: true, updatedAt: at(0)),
      );

      final notes = await repo.watchNotes().first;

      expect([for (final n in notes) n.id], ['pin', 'new', 'old']);
    });

    test('сохранение перезаписывает чек-лист, удаление — мягкое', () async {
      await repo.saveNote(
        _note(
          'n',
          checklist: const [NoteChecklistItem(id: 'i1', text: 'Раз')],
        ),
      );
      await repo.saveNote(
        _note(
          'n',
          checklist: const [
            NoteChecklistItem(id: 'i1', text: 'Раз', isCompleted: true),
            NoteChecklistItem(id: 'i2', text: 'Два'),
          ],
        ),
      );

      final saved = (await repo.getNote('n'))!;
      expect(saved.checklist, hasLength(2));
      expect(saved.checklist.first.isCompleted, isTrue);

      await repo.deleteNote('n');
      expect(await repo.getNote('n'), isNull);
      expect(await repo.watchNotes().first, isEmpty);
      final row = await db.select(db.notes).getSingle();
      expect(row.deletedAt, isNotNull);
    });
  });

  group('синхронизация', () {
    final h = useSyncHarness();

    test('заметка с чек-листом переносится на другое устройство', () async {
      await NotesRepository(h().dbA).saveNote(
        _note(
          'n1',
          title: 'Отпуск',
          isPinned: true,
          colorTag: 'blue',
          checklist: const [
            NoteChecklistItem(id: 'i1', text: 'Паспорт', isCompleted: true),
            NoteChecklistItem(id: 'i2', text: 'Зарядка'),
          ],
        ),
      );

      final result = await h().pushAtoB();

      expect(result.inserted, greaterThanOrEqualTo(1));
      final merged = (await NotesRepository(h().dbB).getNote('n1'))!;
      expect(merged.title, 'Отпуск');
      expect(merged.isPinned, isTrue);
      expect(merged.colorTag, 'blue');
      expect(merged.checklist.map((i) => i.text), ['Паспорт', 'Зарядка']);
      expect(merged.completedCount, 1);
    });

    test('более поздняя правка побеждает, удаление доезжает', () async {
      final repoA = NotesRepository(h().dbA);
      final repoB = NotesRepository(h().dbB);
      await repoA.saveNote(_note('n1', title: 'A', updatedAt: at(1)));
      await h().pushAtoB();
      await repoB.saveNote(_note('n1', title: 'B', updatedAt: at(5)));

      await h().pushBtoA();
      expect((await repoA.getNote('n1'))!.title, 'B');

      await repoA.deleteNote('n1');
      await h().pushAtoB();
      expect(await repoB.getNote('n1'), isNull);
    });
  });

  group('интерфейс', () {
    testWidgets('десктоп: заметка с чек-листом создаётся в центр. редакторе', (
      tester,
    ) async {
      await _withApp(tester, const Size(1280, 800), (db) async {
        await tester.tap(
          find.descendant(
            of: find.byType(AppSidebar),
            matching: find.text('Заметки'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Заметок пока нет'), findsOneWidget);

        await tester.tap(find.text('Новая заметка'));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsOneWidget);
        expect(
          tester.getSize(find.byType(NoteEditor)).width,
          lessThanOrEqualTo(maxEditorWidth),
        );

        await tester.enterText(
          find.byKey(const ValueKey('note_title')),
          'Покупки',
        );
        await tester.tap(find.byKey(const ValueKey('note_add_item')));
        await tester.pumpAndSettle();
        await tester.enterText(find.widgetWithText(TextField, 'Пункт'), 'Хлеб');
        await tester.tap(find.byKey(const ValueKey('note_add_item')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Пункт').last,
          'Молоко',
        );
        await tester.tap(find.byType(Checkbox).first);
        await tester.pumpAndSettle();

        final done = tester.widget<TextField>(
          find.widgetWithText(TextField, 'Хлеб'),
        );
        expect(done.style?.decoration, TextDecoration.lineThrough);
        final open = tester.widget<TextField>(
          find.widgetWithText(TextField, 'Молоко'),
        );
        expect(open.style?.decoration, isNot(TextDecoration.lineThrough));

        await tester.tap(find.byKey(const ValueKey('note_pin')));
        await tester.tap(find.byTooltip('Закрыть'));
        await tester.pumpAndSettle();

        final notes = await _storedNotes(tester, db);
        expect(notes, hasLength(1));
        expect(notes.single.title, 'Покупки');
        expect(notes.single.isPinned, isTrue);
        expect(notes.single.checklist.map((i) => i.text), ['Хлеб', 'Молоко']);
        expect(notes.single.completedCount, 1);

        await tester.pumpAndSettle();
        expect(find.text('1/2 выполнено'), findsOneWidget);
        expect(find.text('ЗАКРЕПЛЁННЫЕ'), findsOneWidget);
      });
    });

    testWidgets('пустая новая заметка не сохраняется', (tester) async {
      await _withApp(tester, const Size(1280, 800), (db) async {
        await tester.tap(
          find.descendant(
            of: find.byType(AppSidebar),
            matching: find.text('Заметки'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Новая заметка'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Закрыть'));
        await tester.pumpAndSettle();

        expect(await _storedNotes(tester, db), isEmpty);
      });
    });

    testWidgets('телефон: редактор во весь экран, раздел в нижней панели', (
      tester,
    ) async {
      await _withApp(tester, const Size(360, 780), (db) async {
        final nav = find.byType(NavigationBar);
        await tester.tap(
          find.descendant(
            of: nav,
            matching: find.byIcon(Icons.sticky_note_2_outlined),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();

        expect(find.byType(NoteEditor), findsOneWidget);
        expect(find.byType(Dialog), findsNothing);
        expect(tester.getSize(find.byType(NoteEditor)), const Size(360, 780));

        await tester.enterText(
          find.byKey(const ValueKey('note_content')),
          'Позвонить маме',
        );
        await tester.tap(find.byTooltip('Закрыть'));
        await tester.pumpAndSettle();

        expect(find.text('Позвонить маме'), findsOneWidget);
        expect(
          (await _storedNotes(tester, db)).single.content,
          'Позвонить маме',
        );
      });
    });

    testWidgets('форма задачи не расширяется при вводе длинного текста', (
      tester,
    ) async {
      await _withApp(tester, const Size(1280, 800), (db) async {
        await tester.tap(
          find.descendant(
            of: find.byType(AppSidebar),
            matching: find.text('Задачи'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Новая задача'));
        await tester.pumpAndSettle();

        // Ширина формы = ширина её полей (AlertDialog сам занимает экран).
        final field = find.byType(TextFormField).first;
        final before = tester.getSize(field).width;
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Название *'),
          'Очень длинное название задачи ' * 20,
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Описание'),
          'Длинное описание без переносов ' * 30,
        );
        await tester.pumpAndSettle();

        expect(tester.getSize(field).width, before);
        expect(before, lessThan(1280 - 100));
      });
    });
  });
}
