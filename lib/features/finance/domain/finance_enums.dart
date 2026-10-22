import 'package:flutter/material.dart';

/// Тип финансового продукта. [value] хранится в `finance_accounts.kind`.
enum FinanceAccountKind {
  account(0, 'Счёт', 'Счета', Icons.account_balance_wallet_outlined),
  loan(1, 'Кредит', 'Кредиты', Icons.credit_score_outlined),
  deposit(2, 'Депозит / копилка', 'Депозиты', Icons.savings_outlined),

  /// Возобновляемая кредитная линия (кредитка, Сплит-лимит): с неё можно
  /// тратить, как со счёта, а `balance` хранит текущий долг.
  creditCard(
    3,
    'Кредитная карта / Сплит-лимит',
    'Кредитные карты',
    Icons.credit_card,
  );

  const FinanceAccountKind(this.value, this.label, this.pluralLabel, this.icon);

  final int value;
  final String label;
  final String pluralLabel;
  final IconData icon;

  static FinanceAccountKind fromValue(int value) {
    return FinanceAccountKind.values.firstWhere(
      (k) => k.value == value,
      orElse: () => FinanceAccountKind.account,
    );
  }

  /// Пассив: `balance` — долг, поступление денег его уменьшает, а списание
  /// увеличивает.
  bool get isLiability =>
      this == FinanceAccountKind.loan || this == FinanceAccountKind.creditCard;
}

/// Тип операции. [value] хранится в `finance_transactions.type`.
enum FinanceTransactionType {
  expense(0, 'Расход', Icons.arrow_upward_rounded),
  income(1, 'Доход', Icons.arrow_downward_rounded),
  transfer(2, 'Перевод', Icons.swap_horiz_rounded);

  const FinanceTransactionType(this.value, this.label, this.icon);

  final int value;
  final String label;
  final IconData icon;

  static FinanceTransactionType fromValue(int value) {
    return FinanceTransactionType.values.firstWhere(
      (t) => t.value == value,
      orElse: () => FinanceTransactionType.expense,
    );
  }
}

/// Период фильтра ленты операций.
enum FinancePeriod {
  today('Сегодня'),
  week('Неделя'),
  month('Месяц'),
  all('Всё время');

  const FinancePeriod(this.label);

  final String label;

  /// Входит ли [date] в период относительно момента [now].
  /// Неделя — с понедельника текущей недели, месяц — календарный.
  bool contains(DateTime date, DateTime now) {
    final d = date.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    switch (this) {
      case FinancePeriod.today:
        return DateTime(d.year, d.month, d.day) == today;
      case FinancePeriod.week:
        final start = today.subtract(Duration(days: today.weekday - 1));
        final end = start.add(const Duration(days: 7));
        return !d.isBefore(start) && d.isBefore(end);
      case FinancePeriod.month:
        return d.year == now.year && d.month == now.month;
      case FinancePeriod.all:
        return true;
    }
  }
}
