import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/database/app_database.dart';
import 'package:home_organizer/core/database/database_provider.dart';
import 'package:home_organizer/features/finance/data/repositories/finance_repository.dart';
import 'package:home_organizer/features/finance/domain/finance_enums.dart';
import 'package:home_organizer/features/notes/domain/note.dart';
import 'package:home_organizer/features/quick_actions/presentation/widgets/quick_actions_overlay.dart';
import 'package:home_organizer/features/routine/data/repositories/routine_repository.dart';
import 'package:home_organizer/features/routine/domain/routine_day.dart';
import 'package:home_organizer/features/settings/data/repositories/settings_repository.dart';
import 'package:home_organizer/features/settings/domain/app_module.dart';
import 'package:home_organizer/features/settings/presentation/providers/settings_provider.dart';
import 'package:home_organizer/main.dart';

const _button = ValueKey('quick_actions_button');

Future<void> _withApp(
  WidgetTester tester,
  Future<void> Function(AppDatabase db) body, {
  Size size = const Size(1600, 1000),
  Future<void> Function(AppDatabase db)? seed,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  if (seed != null) await tester.runAsync(() => seed(db));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: const HomeOrganizerApp(),
    ),
  );
  await tester.pumpAndSettle();
  try {
    await body(db);
  } finally {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await db.close();
  }
}

Future<void> _openAction(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(_button));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('quick_action_$id')));
  await tester.pumpAndSettle();
}

/// Выбор пункта выпадающего списка по началу подписи.
Future<void> _pick(WidgetTester tester, String key, String label) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining(label).last);
  await tester.pumpAndSettle();
}

void main() {
  group('настройки', () {
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('кнопка по умолчанию показана, выбор сохраняется', () async {
      final repo = container.read(settingsRepositoryProvider);
      final controller = container.read(settingsControllerProvider);
      expect(resolveShowQuickActionsWidget(await repo.readAll()), isTrue);

      await controller.setShowQuickActionsWidget(false);
      expect(resolveShowQuickActionsWidget(await repo.readAll()), isFalse);

      await controller.setShowQuickActionsWidget(true);
      expect(resolveShowQuickActionsWidget(await repo.readAll()), isTrue);
    });

    test('положение кнопки сохраняется и разбирается', () async {
      const position =
          QuickButtonPosition(isLeft: true, verticalFraction: 0.25);
      await container
          .read(settingsControllerProvider)
          .setQuickButtonPosition(position);
      final raw = (await container.read(settingsRepositoryProvider).readAll())[
          quickActionsPositionKey];
      expect(QuickButtonPosition.decode(raw), position);
    });

    test('повреждённое положение — положение по умолчанию', () {
      expect(QuickButtonPosition.decode(null), QuickButtonPosition.initial);
      expect(QuickButtonPosition.decode('abc'), QuickButtonPosition.initial);
      expect(QuickButtonPosition.decode('left:NaN'),
          QuickButtonPosition.initial);
      expect(QuickButtonPosition.decode('right:7').verticalFraction, 1.0);
    });
  });

  testWidgets('переключатель в Настройках сразу скрывает и возвращает кнопку',
      (tester) async {
    await _withApp(tester, (db) async {
      expect(find.byKey(_button), findsOneWidget);

      await tester.tap(find.text('Настройки'));
      await tester.pumpAndSettle();
      final toggle = find.byKey(const ValueKey('quick_actions_widget_switch'));
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      expect(find.text('Плавающая кнопка быстрых действий'), findsOneWidget);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.byType(QuickActionsOverlay), findsNothing);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.byKey(_button), findsOneWidget);
    });
  });

  testWidgets('меню показывает пункты только включённых разделов',
      (tester) async {
    await _withApp(
      tester,
      seed: (db) => SettingsRepository(db)
          .setValue(AppModule.finance.storageKey, 'false'),
      (db) async {
        await tester.tap(find.byKey(_button));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('quick_action_expense')), findsNothing);
        expect(find.byKey(const ValueKey('quick_action_note')), findsOneWidget);
        expect(
            find.byKey(const ValueKey('quick_action_check_in')), findsOneWidget);

        // Тап мимо меню закрывает его.
        await tester.tapAt(const Offset(800, 100));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('quick_action_note')), findsNothing);
      },
    );
  });

  testWidgets('перетаскивание примагничивает кнопку к краю и запоминает его',
      (tester) async {
    await _withApp(tester, (db) async {
      final start = tester.getCenter(find.byKey(_button));
      expect(start.dx, greaterThan(800));

      await tester.drag(find.byKey(_button), const Offset(-900, -200));
      await tester.pumpAndSettle();
      final end = tester.getCenter(find.byKey(_button));
      // Кнопка у левого края области разделов (правее бокового меню).
      expect(end.dx, lessThan(800));
      expect(end.dy, lessThan(start.dy));

      final raw = (await tester.runAsync(SettingsRepository(db).readAll))![
          quickActionsPositionKey];
      expect(QuickButtonPosition.decode(raw).isLeft, isTrue);
    });
  });

  testWidgets('Ctrl+Shift+Q открывает меню, цифра запускает действие',
      (tester) async {
    await _withApp(tester, (db) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('quick_action_note')), findsOneWidget);

      // «4» — «Заметка».
      await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
      await tester.pumpAndSettle();
      expect(find.text('Быстрая заметка'), findsOneWidget);
    });
  });

  testWidgets('быстрый расход списывает со счёта и пишет операцию',
      (tester) async {
    late String accountId;
    await _withApp(
      tester,
      seed: (db) async {
        accountId = await FinanceRepository(db).createAccount(
          name: 'Карта',
          kind: FinanceAccountKind.account,
          balance: 1000,
        );
      },
      (db) async {
        await _openAction(tester, 'expense');
        expect(find.text('Расход'), findsWidgets);
        expect(find.byKey(const ValueKey('tx_type')), findsNothing);
        await _pick(tester, 'tx_account_0', 'Карта');

        await tester.enterText(
            find.byKey(const ValueKey('tx_amount')), '250');
        await tester.enterText(find.byKey(const ValueKey('tx_note')), 'Кофе');
        await tester.tap(find.byKey(const ValueKey('tx_submit')));
        await tester.pumpAndSettle();

        final repo = FinanceRepository(db);
        final account = (await tester.runAsync(repo.getAccounts))!
            .firstWhere((a) => a.id == accountId);
        expect(account.balance, 750);
        final tx = (await tester.runAsync(repo.getTransactions))!.single;
        expect(tx.type, FinanceTransactionType.expense.value);
        expect(tx.note, 'Кофе');
      },
    );
  });

  testWidgets('быстрое пополнение кредитки уменьшает долг', (tester) async {
    await _withApp(
      tester,
      seed: (db) => FinanceRepository(db).createAccount(
        name: 'Кредитка',
        kind: FinanceAccountKind.creditCard,
        balance: 400,
        targetAmount: 1000,
      ),
      (db) async {
        await _openAction(tester, 'income');
        await _pick(tester, 'tx_account_1', 'Кредитка');
        await tester.enterText(
            find.byKey(const ValueKey('tx_amount')), '100');
        await tester.tap(find.byKey(const ValueKey('tx_submit')));
        await tester.pumpAndSettle();

        final card = (await tester.runAsync(FinanceRepository(db).getAccounts))!
            .firstWhere((a) => a.name == 'Кредитка');
        expect(card.balance, 300);
      },
    );
  });

  testWidgets('быстрый перевод пересчитывает оба счёта', (tester) async {
    await _withApp(
      tester,
      seed: (db) async {
        final repo = FinanceRepository(db);
        await repo.createAccount(
            name: 'Зарплатная', kind: FinanceAccountKind.account, balance: 500);
        await repo.createAccount(
            name: 'Наличные', kind: FinanceAccountKind.account, balance: 0);
      },
      (db) async {
        await _openAction(tester, 'transfer');
        await _pick(tester, 'tx_account_2', 'Зарплатная');
        await tester.enterText(
            find.byKey(const ValueKey('tx_amount')), '200');
        await _pick(tester, 'tx_target_2', 'Наличные');
        await tester.tap(find.byKey(const ValueKey('tx_submit')));
        await tester.pumpAndSettle();

        final repo = FinanceRepository(db);
        final accounts = (await tester.runAsync(repo.getAccounts))!;
        double balance(String name) =>
            accounts.firstWhere((a) => a.name == name).balance;
        expect(balance('Зарплатная'), 300);
        expect(balance('Наличные'), 200);
        final tx = (await tester.runAsync(repo.getTransactions))!.single;
        expect(tx.type, FinanceTransactionType.transfer.value);
      },
    );
  });

  testWidgets('быстрая заметка-чек-лист сохраняется в «Заметки»',
      (tester) async {
    await _withApp(tester, (db) async {
      await _openAction(tester, 'note');
      await tester.enterText(
          find.byKey(const ValueKey('quick_note_title')), 'Покупки');
      await tester.enterText(
          find.byKey(const ValueKey('quick_note_text')), 'Хлеб\n\nМолоко\n');
      await tester.tap(find.byKey(const ValueKey('quick_note_checklist')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('quick_note_submit')));
      await tester.pumpAndSettle();

      final rows = (await tester.runAsync(() => db.select(db.notes).get()))!;
      final note = Note.fromEntity(rows.single);
      expect(note.title, 'Покупки');
      expect(note.content, isEmpty);
      expect(note.checklist.map((i) => i.text), ['Хлеб', 'Молоко']);
    });
  });

  testWidgets('пустая быстрая заметка не сохраняется', (tester) async {
    await _withApp(tester, (db) async {
      await _openAction(tester, 'note');
      await tester.tap(find.byKey(const ValueKey('quick_note_submit')));
      await tester.pumpAndSettle();
      expect(find.text('Введите заголовок или текст'), findsOneWidget);
      final rows = (await tester.runAsync(() => db.select(db.notes).get()))!;
      expect(rows, isEmpty);
    });
  });

  testWidgets('чек-ин рутины отмечает действие в один тап', (tester) async {
    await _withApp(
      tester,
      seed: (db) async {
        final repo = RoutineRepository(db);
        await repo.createItem(title: 'Зарядка');
        await repo.createItem(title: 'Витамины');
      },
      (db) async {
        await _openAction(tester, 'check_in');
        expect(find.text('Выполнено 0 из 2'), findsOneWidget);
        final dialog = find.byType(AlertDialog);

        await tester.tap(
            find.descendant(of: dialog, matching: find.text('Зарядка')));
        await tester.pumpAndSettle();
        expect(find.text('Выполнено 1 из 2'), findsOneWidget);
        // Отмеченный пункт остаётся в окне — отметку можно снять.
        expect(find.descendant(of: dialog, matching: find.text('Зарядка')),
            findsOneWidget);

        final items =
            (await tester.runAsync(() => db.select(db.routineItems).get()))!;
        final done = items.where((i) => isRoutineDoneToday(i, DateTime.now()));
        expect(done.map((i) => i.title), ['Зарядка']);
      },
    );
  });

  testWidgets('телефон: формы открываются шторкой снизу', (tester) async {
    await _withApp(
      tester,
      size: const Size(400, 800),
      (db) async {
        await _openAction(tester, 'note');
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(find.text('Быстрая заметка'), findsOneWidget);
      },
    );
  });
}
