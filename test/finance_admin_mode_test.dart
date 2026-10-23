import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/database/app_database.dart';
import 'package:home_organizer/core/database/database_provider.dart';
import 'package:home_organizer/core/theme/app_theme.dart';
import 'package:home_organizer/core/widgets/app_sidebar.dart';
import 'package:home_organizer/features/finance/data/repositories/finance_repository.dart';
import 'package:home_organizer/features/finance/domain/finance_calculations.dart';
import 'package:home_organizer/features/finance/domain/finance_enums.dart';
import 'package:home_organizer/features/finance/presentation/providers/finance_provider.dart';
import 'package:home_organizer/features/finance/presentation/screens/finance_screen.dart';
import 'package:home_organizer/main.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late FinanceRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    repo = container.read(financeRepositoryProvider);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<ObligationEntity> obligation(String id) =>
      (db.select(db.obligations)..where((o) => o.id.equals(id))).getSingle();

  Future<FinanceAccountEntity> account(String id) =>
      (db.select(db.financeAccounts)..where((a) => a.id.equals(id)))
          .getSingle();

  Future<List<ObligationStatus>> statuses() async {
    final now = DateTime.now();
    return buildObligationStatuses(
      await repo.getObligations(),
      await repo.getTransactions(),
      DateTime(now.year, now.month),
      accounts: await repo.getAccounts(),
    );
  }

  group('skipObligation', () {
    test('ежемесячный платёж: без операции и списания, период пропущен',
        () async {
      final cash = await repo.createAccount(
        name: 'Карта',
        kind: FinanceAccountKind.account,
        balance: 5000,
      );
      final id = await repo.createObligation(
        name: 'Интернет',
        amount: 800,
        dueDay: 10,
      );

      expect(await repo.skipObligation(obligationId: id), isTrue);

      expect(await repo.getTransactions(), isEmpty);
      expect((await account(cash)).balance, 5000);
      final status = (await statuses()).single;
      expect(status.isSkipped, isTrue);
      expect(status.isPaid, isFalse);
      expect(status.isOutstanding, isFalse);
      expect(status.urgency, ObligationUrgency.skipped);
      expect(status.needsAttention, isFalse);

      // Пропущенный платёж не входит ни в план месяца, ни в остаток.
      final summary = buildSummary(
        accounts: await repo.getAccounts(),
        obligations: await statuses(),
      );
      expect(summary.obligationsTotal, 0);
      expect(summary.leftToLive, 5000);

      // Повторно пропустить тот же месяц нельзя.
      expect(await repo.skipObligation(obligationId: id), isFalse);
    });

    test('пропуск относится только к своему месяцу', () async {
      final id = await repo.createObligation(
        name: 'Аренда',
        amount: 30000,
        dueDay: 5,
      );
      final now = DateTime.now();
      await repo.skipObligation(obligationId: id);
      final o = await obligation(id);
      expect(isObligationSkipped(o, DateTime(now.year, now.month)), isTrue);
      expect(isObligationSkipped(o, DateTime(now.year, now.month + 1)), isFalse);
    });

    test('оплаченный платёж не пропускается, отмену пропуска можно вернуть',
        () async {
      final cash = await repo.createAccount(
        name: 'Карта',
        kind: FinanceAccountKind.account,
        balance: 5000,
      );
      final paidId =
          await repo.createObligation(name: 'ЖКХ', amount: 1000, dueDay: 1);
      await repo.payObligation(obligationId: paidId, fromAccountId: cash);
      expect(await repo.skipObligation(obligationId: paidId), isFalse);

      final id =
          await repo.createObligation(name: 'Связь', amount: 500, dueDay: 2);
      await repo.skipObligation(obligationId: id);
      await repo.undoSkipObligation(id);
      expect((await obligation(id)).skippedMonth, isNull);
      final status = (await statuses()).firstWhere((s) => s.obligation.id == id);
      expect(status.isOutstanding, isTrue);
    });

    test('рассрочка: ближайшее списание сдвигается на шаг, долг не меняется',
        () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final loanId = await repo.createAccount(
        name: 'Сплит',
        kind: FinanceAccountKind.loan,
        balance: 3000,
        isFlexibleSchedule: true,
        nextPaymentDate: today,
        nextPaymentAmount: 1000,
      );
      final id = (await repo.getObligations()).single.id;

      expect(await repo.skipObligation(obligationId: id), isTrue);

      final loan = await account(loanId);
      expect(loan.balance, 3000);
      expect(loan.nextPaymentAmount, 1000);
      expect(
        dateOnly(loan.nextPaymentDate!),
        DateTime(today.year, today.month,
            today.day + flexiblePaymentStepDays),
      );
      expect(await repo.getTransactions(), isEmpty);
    });
  });

  group('экран финансов', () {
    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> openPhoneScreen(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkLauncherTheme,
            home: const FinanceScreen(),
          ),
        ),
      );
      await settle(tester);
    }

    Future<void> closeScreen(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }

    testWidgets('без режима администратора кнопки «Пропустить» нет',
        (tester) async {
      late String id;
      await tester.runAsync(() async {
        id = await repo.createObligation(
            name: 'Интернет', amount: 800, dueDay: 10);
      });
      await openPhoneScreen(tester);

      expect(find.text('Интернет'), findsOneWidget);
      expect(find.byKey(ValueKey('skip_$id')), findsNothing);
      expect(find.byKey(const ValueKey('admin_mode_strip')), findsNothing);

      await closeScreen(tester);
    });

    testWidgets('долгое нажатие на щит включает режим и пропуск платежа',
        (tester) async {
      late String id;
      await tester.runAsync(() async {
        id = await repo.createObligation(
            name: 'Интернет', amount: 800, dueDay: 10);
      });
      await openPhoneScreen(tester);

      await tester.longPress(find.byKey(const ValueKey('finance_admin_shield')));
      await tester.pump();
      expect(container.read(financeAdminModeProvider), isTrue);
      expect(
        find.text('Режим администратора включен. Доступен пропуск платежей.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('admin_mode_strip')), findsOneWidget);

      await tester.ensureVisible(find.byKey(ValueKey('skip_$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('skip_$id')));
      await settle(tester);
      // Прежний SnackBar уезжает, новый показывается следом.
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Платёж пропущен без списания средств'), findsOneWidget);
      expect(find.textContaining('пропущено в этом месяце'), findsOneWidget);
      expect(find.byKey(ValueKey('skip_$id')), findsNothing);
      expect((await tester.runAsync(repo.getTransactions))!, isEmpty);

      // Повторное долгое нажатие на заголовок выключает режим.
      await tester.longPress(find.byKey(const ValueKey('finance_title')));
      await tester.pump();
      expect(container.read(financeAdminModeProvider), isFalse);
      expect(find.byKey(ValueKey('undo_skip_$id')), findsNothing);

      await closeScreen(tester);
    });
  });

  testWidgets('десктоп: профиль включает режим только в финансах, '
      'уход с раздела сбрасывает его', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final appDb = AppDatabase.forTesting(NativeDatabase.memory());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(appDb)],
        child: const HomeOrganizerApp(),
      ),
    );
    await tester.pumpAndSettle();
    final profile = find.byKey(const ValueKey('sidebar_profile'));
    final badge = find.byKey(const ValueKey('sidebar_admin_badge'));
    Future<void> open(String label) async {
      await tester.tap(find.descendant(
        of: find.byType(AppSidebar),
        matching: find.text(label),
      ));
      await tester.pumpAndSettle();
    }

    try {
      // На дашборде нажатие игнорируется.
      await tester.tap(profile);
      await tester.pumpAndSettle();
      expect(badge, findsNothing);

      await open('Финансы');
      await tester.tap(profile);
      await tester.pumpAndSettle();
      expect(badge, findsOneWidget);
      expect(find.byKey(const ValueKey('admin_mode_strip')), findsOneWidget);

      await open('Задачи');
      await open('Финансы');
      expect(badge, findsNothing);
      expect(find.byKey(const ValueKey('admin_mode_strip')), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await appDb.close();
    }
  });
}
