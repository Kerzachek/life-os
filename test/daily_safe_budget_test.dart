import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/database/app_database.dart';
import 'package:home_organizer/core/theme/app_theme.dart';
import 'package:home_organizer/features/finance/domain/finance_calculations.dart';
import 'package:home_organizer/features/finance/domain/finance_category_presets.dart';
import 'package:home_organizer/features/finance/domain/finance_enums.dart';
import 'package:home_organizer/features/finance/presentation/widgets/safe_to_spend_card.dart';

void main() {
  final stamp = DateTime(2026, 1, 1);

  FinanceAccountEntity acc(
    String id,
    double balance, {
    FinanceAccountKind kind = FinanceAccountKind.account,
  }) {
    return FinanceAccountEntity(
      id: id,
      createdAt: stamp,
      updatedAt: stamp,
      name: id,
      kind: kind.value,
      balance: balance,
      isFlexibleSchedule: false,
    );
  }

  ObligationStatus obligation(String id, double amount, {bool paid = false}) {
    return ObligationStatus(
      obligation: ObligationEntity(
        id: id,
        createdAt: stamp,
        updatedAt: stamp,
        name: id,
        amount: amount,
        dueDay: 20,
      ),
      isPaid: paid,
    );
  }

  FinanceTransactionEntity tx(
    double amount,
    DateTime date, {
    FinanceTransactionType type = FinanceTransactionType.expense,
    String? categoryId,
    String? targetAccountId,
    String? obligationId,
  }) {
    return FinanceTransactionEntity(
      id: 'tx_${amount}_${date.microsecondsSinceEpoch}_$categoryId',
      createdAt: stamp,
      updatedAt: stamp,
      date: date,
      amount: amount,
      type: type.value,
      accountId: 'main',
      targetAccountId: targetAccountId,
      categoryId: categoryId,
      obligationId: obligationId,
    );
  }

  group('buildDailySafeBudget', () {
    test('обычный день: норма делится на оставшиеся дни', () {
      // 20 октября 2026: до конца месяца 12 дней (включая сегодня).
      final now = DateTime(2026, 10, 20, 12);
      final state = buildDailySafeBudget(
        accounts: [
          acc('main', 50000),
          acc('card', 10000),
          acc('piggy', 99999, kind: FinanceAccountKind.deposit),
          acc('loan', 300000, kind: FinanceAccountKind.loan),
        ],
        obligations: [
          obligation('rent', 20000),
          obligation('paid', 5000, paid: true),
        ],
        transactions: [
          tx(600, now, categoryId: FinanceCategoryIds.food),
          // Вчерашняя трата не учитывается.
          tx(900, DateTime(2026, 10, 19, 15)),
        ],
        now: now,
      );

      expect(state.liquidBalance, 60000);
      expect(state.unpaidObligations, 20000);
      expect(state.spentToday, 600);
      expect(state.daysRemaining, 12);
      expect(state.freePoolAtStartOfDay, 40600);
      expect(state.dailyAllowance, closeTo(40600 / 12, 1e-9));
      expect(state.remainingToday, closeTo(40600 / 12 - 600, 1e-9));
      expect(state.freePoolTotal, 40000);
      expect(state.isOverspent, isFalse);
    });

    test('перерасход за сегодня даёт отрицательный остаток', () {
      final now = DateTime(2026, 10, 20, 12);
      final state = buildDailySafeBudget(
        accounts: [acc('main', 1000)],
        obligations: const [],
        // Баланс 1000 уже после траты 2400: стартовый пул 3400 / 12 дней.
        transactions: [tx(2400, now, categoryId: FinanceCategoryIds.shopping)],
        now: now,
      );

      expect(state.freePoolAtStartOfDay, 3400);
      expect(state.dailyAllowance, closeTo(3400 / 12, 1e-9));
      expect(state.remainingToday, closeTo(3400 / 12 - 2400, 1e-9));
      expect(state.remainingToday, lessThan(0));
      expect(state.isOverspent, isTrue);
      expect(state.spentRatio, greaterThan(1));
      expect(safeToSpendColor(state), AppTheme.fireAccent);
    });

    test('норма не бывает отрицательной, если обязательств больше денег', () {
      final state = buildDailySafeBudget(
        accounts: [acc('main', 5000)],
        obligations: [obligation('rent', 20000)],
        transactions: const [],
        now: DateTime(2026, 10, 20),
      );

      expect(state.freePoolTotal, -15000);
      expect(state.dailyAllowance, 0);
      expect(state.remainingToday, 0);
      expect(state.spentRatio, 0);
    });

    test('оплата обязательного платежа не ломает дневную норму', () {
      final now = DateTime(2026, 10, 20, 12);

      // До оплаты: на счёте 30000, аренда 20000 не оплачена.
      final before = buildDailySafeBudget(
        accounts: [acc('main', 30000)],
        obligations: [obligation('rent', 20000)],
        transactions: const [],
        now: now,
      );

      // После оплаты: счёт 10000, платёж оплачен; сегодня есть расход-оплата
      // (с obligationId), платёж по кредиту и перевод на копилку.
      final after = buildDailySafeBudget(
        accounts: [acc('main', 10000)],
        obligations: [obligation('rent', 20000, paid: true)],
        transactions: [
          tx(20000, now,
              categoryId: FinanceCategoryIds.obligations,
              obligationId: 'rent'),
          tx(15000, now,
              categoryId: FinanceCategoryIds.loans, targetAccountId: 'loan'),
          tx(3000, now,
              type: FinanceTransactionType.transfer, targetAccountId: 'piggy'),
        ],
        now: now,
      );

      expect(after.spentToday, 0);
      expect(after.dailyAllowance, before.dailyAllowance);
      expect(after.remainingToday, before.remainingToday);
      expect(after.freePoolTotal, before.freePoolTotal);
    });

    test('последний день месяца: остаётся один день', () {
      final now = DateTime(2026, 10, 31, 9);
      final state = buildDailySafeBudget(
        accounts: [acc('main', 3000)],
        obligations: [obligation('net', 500)],
        transactions: [tx(400, now)],
        now: now,
      );

      expect(state.daysRemaining, 1);
      expect(state.freePoolAtStartOfDay, 3000 + 400 - 500);
      expect(state.dailyAllowance, 2900);
      expect(state.remainingToday, 2500);
    });

    test('количество дней до конца месяца', () {
      expect(daysRemainingInMonth(DateTime(2026, 10, 1)), 31);
      expect(daysRemainingInMonth(DateTime(2026, 10, 31)), 1);
      expect(daysRemainingInMonth(DateTime(2028, 2, 15)), 15); // високосный
      expect(daysRemainingInMonth(DateTime(2026, 12, 31)), 1);
    });

    test('доходы, удалённые операции и чужие дни не считаются тратами', () {
      final now = DateTime(2026, 10, 20, 12);
      final deleted = FinanceTransactionEntity(
        id: 'del',
        createdAt: stamp,
        updatedAt: stamp,
        deletedAt: stamp,
        date: now,
        amount: 700,
        type: FinanceTransactionType.expense.value,
        accountId: 'main',
      );
      final state = buildDailySafeBudget(
        accounts: [acc('main', 1000)],
        obligations: const [],
        transactions: [
          tx(5000, now, type: FinanceTransactionType.income),
          deleted,
          tx(300, DateTime(2026, 9, 20, 12)),
        ],
        now: now,
      );

      expect(state.spentToday, 0);
    });
  });

  group('цвет прогресс-бара', () {
    // Норма = 100 ₽ (1200 ₽ на 12 дней при нулевых тратах до сегодняшних).
    DailySafeBudgetState state(double spent) => DailySafeBudgetState(
          liquidBalance: 1200 - spent,
          unpaidObligations: 0,
          spentToday: spent,
          daysRemaining: 12,
        );

    test('зелёный < 70%, оранжевый 70–100%, коралловый при перерасходе', () {
      expect(safeToSpendColor(state(0)), AppTheme.successAccent);
      expect(safeToSpendColor(state(69)), AppTheme.successAccent);
      expect(safeToSpendColor(state(70)), const Color(0xFFFF9F43));
      expect(safeToSpendColor(state(100)), const Color(0xFFFF9F43));
      expect(safeToSpendColor(state(150)), AppTheme.fireAccent);
    });
  });
}
