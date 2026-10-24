import 'package:flutter/material.dart';

import '../../finance/domain/finance_enums.dart';
import '../../finance/presentation/widgets/transaction_dialog.dart';
import '../../settings/domain/app_module.dart';
import 'widgets/quick_note_sheet.dart';
import 'widgets/routine_check_in_sheet.dart';

/// Пункт меню системного оверлея быстрых действий. Пункты отключённых
/// разделов скрываются; выбор открывает форму [builder] в окне LifeOS.
class QuickMenuAction {
  final String id;
  final AppModule module;
  final IconData icon;
  final String label;
  final Color color;
  final WidgetBuilder builder;

  const QuickMenuAction({
    required this.id,
    required this.module,
    required this.icon,
    required this.label,
    required this.color,
    required this.builder,
  });
}

final List<QuickMenuAction> quickMenuActions = [
  QuickMenuAction(
    id: 'expense',
    module: AppModule.finance,
    icon: Icons.remove_shopping_cart_rounded,
    label: 'Расход',
    color: const Color(0xFFFF7675),
    builder: (_) => const TransactionDialog(
      initialType: FinanceTransactionType.expense,
      quick: true,
    ),
  ),
  QuickMenuAction(
    id: 'income',
    module: AppModule.finance,
    icon: Icons.account_balance_wallet_rounded,
    label: 'Пополнение',
    color: const Color(0xFF00B894),
    builder: (_) => const TransactionDialog(
      initialType: FinanceTransactionType.income,
      quick: true,
    ),
  ),
  QuickMenuAction(
    id: 'transfer',
    module: AppModule.finance,
    icon: Icons.swap_horiz_rounded,
    label: 'Перевод',
    color: const Color(0xFF74B9FF),
    builder: (_) => const TransactionDialog(
      initialType: FinanceTransactionType.transfer,
      quick: true,
    ),
  ),
  QuickMenuAction(
    id: 'note',
    module: AppModule.notes,
    icon: Icons.edit_note_rounded,
    label: 'Заметка',
    color: const Color(0xFFFDCB6E),
    builder: (_) => const QuickNoteSheet(),
  ),
  QuickMenuAction(
    id: 'check_in',
    module: AppModule.routine,
    icon: Icons.wb_sunny_rounded,
    label: 'Чек-ин рутины',
    color: const Color(0xFFA29BFE),
    builder: (_) => const RoutineCheckInSheet(),
  ),
];
