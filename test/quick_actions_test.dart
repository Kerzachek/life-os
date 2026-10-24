import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/database/app_database.dart';
import 'package:home_organizer/core/database/database_provider.dart';
import 'package:home_organizer/core/services/system_overlay_service.dart';
import 'package:home_organizer/features/finance/data/repositories/finance_repository.dart';
import 'package:home_organizer/features/finance/domain/finance_enums.dart';
import 'package:home_organizer/features/notes/domain/note.dart';
import 'package:home_organizer/features/quick_actions/presentation/providers/system_overlay_provider.dart';
import 'package:home_organizer/features/routine/data/repositories/routine_repository.dart';
import 'package:home_organizer/features/routine/domain/routine_day.dart';
import 'package:home_organizer/features/settings/data/repositories/settings_repository.dart';
import 'package:home_organizer/features/settings/presentation/providers/settings_provider.dart';
import 'package:home_organizer/main.dart';

const _channel = SystemOverlayService.defaultChannel;

Future<void> _withApp(
  WidgetTester tester,
  Future<void> Function(AppDatabase db) body, {
  Size size = const Size(1600, 1000),
  Future<void> Function(AppDatabase db)? seed,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
    return switch (call.method) {
      'canDrawOverlays' || 'show' => true,
      _ => null,
    };
  });
  addTearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null));
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  await tester.runAsync(() async {
    await SettingsRepository(db).setValue(systemOverlayEnabledKey, 'true');
    if (seed != null) await seed(db);
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        systemOverlaySupportedProvider.overrideWithValue(true),
      ],
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

/// Выбор действия в системном оверлее (событие от нативной стороны).
Future<void> _openAction(WidgetTester tester, String id) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
    _channel.name,
    _channel.codec.encodeMethodCall(MethodCall('onAction', {'id': id})),
    (_) {},
  );
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
  test('повреждённое положение — положение по умолчанию', () {
    expect(QuickButtonPosition.decode(null), QuickButtonPosition.initial);
    expect(QuickButtonPosition.decode('abc'), QuickButtonPosition.initial);
    expect(QuickButtonPosition.decode('left:NaN'),
        QuickButtonPosition.initial);
    expect(QuickButtonPosition.decode('right:7').verticalFraction, 1.0);
  });

  testWidgets('в окне LifeOS нет внутренней плавающей кнопки', (tester) async {
    await _withApp(tester, (db) async {
      expect(find.byKey(const ValueKey('quick_actions_button')), findsNothing);
      await tester.tap(find.text('Настройки'));
      await tester.pumpAndSettle();
      expect(find.text('Плавающая кнопка быстрых действий'), findsNothing);
      expect(find.text('Системный оверлей быстрого доступа поверх всех окон'),
          findsOneWidget);
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
