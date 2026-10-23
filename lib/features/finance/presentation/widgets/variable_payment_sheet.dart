import 'package:flutter/material.dart';

import '../../../../core/database/app_database.dart';
import '../../data/repositories/finance_repository.dart' show roundMoney;
import 'finance_format.dart';

/// Подтверждённая оплата плавающего платежа.
class VariablePayment {
  const VariablePayment({required this.amount, required this.accountId});

  /// Фактическая сумма списания (по квитанции).
  final double amount;
  final String accountId;
}

/// Шторка оплаты плавающего платежа (ЖКХ, свет): фактическая сумма
/// (предзаполнена оценкой [estimate]) и счёт списания. Возвращает `null`
/// при отмене.
///
/// [accounts] — обычные счета; [initialAccountId] — счёт по умолчанию.
/// [nextDueDate] — срок в следующем месяце, на который сдвинется платёж.
Future<VariablePayment?> showVariablePaymentSheet(
  BuildContext context, {
  required String title,
  required double estimate,
  required List<FinanceAccountEntity> accounts,
  String? initialAccountId,
  DateTime? nextDueDate,
}) {
  return showModalBottomSheet<VariablePayment>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _VariablePaymentSheet(
      title: title,
      estimate: estimate,
      accounts: accounts,
      initialAccountId: initialAccountId,
      nextDueDate: nextDueDate,
    ),
  );
}

class _VariablePaymentSheet extends StatefulWidget {
  const _VariablePaymentSheet({
    required this.title,
    required this.estimate,
    required this.accounts,
    required this.initialAccountId,
    required this.nextDueDate,
  });

  final String title;
  final double estimate;
  final List<FinanceAccountEntity> accounts;
  final String? initialAccountId;
  final DateTime? nextDueDate;

  @override
  State<_VariablePaymentSheet> createState() => _VariablePaymentSheetState();
}

class _VariablePaymentSheetState extends State<_VariablePaymentSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late String _accountId;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(text: '${roundMoney(widget.estimate)}');
    final initial = widget.initialAccountId;
    _accountId = widget.accounts.any((a) => a.id == initial)
        ? initial!
        : widget.accounts.first.id;
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      VariablePayment(amount: parseMoney(_amount.text)!, accountId: _accountId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final next = widget.nextDueDate;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + keyboard),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Плавающий платёж: укажите точную сумму по квитанции.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('variable_sheet_amount'),
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Фактическая сумма списания',
                helperText: 'Ориентир: ${formatMoney(widget.estimate)}',
                border: const OutlineInputBorder(),
              ),
              validator: (v) {
                final n = parseMoney(v);
                return (n == null || n <= 0) ? 'Сумма > 0' : null;
              },
            ),
            if (widget.accounts.length > 1) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const ValueKey('variable_sheet_account'),
                initialValue: _accountId,
                decoration: const InputDecoration(
                  labelText: 'Списать со счёта',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final a in widget.accounts)
                    DropdownMenuItem(
                      value: a.id,
                      child: Text('${a.name} · ${formatMoney(a.balance)}'),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _accountId = v);
                },
              ),
            ],
            if (next != null) ...[
              const SizedBox(height: 12),
              Text(
                'Следующий платёж: ${formatDate(next)}',
                key: const ValueKey('variable_sheet_next'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 16),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Отмена'),
                ),
                FilledButton(
                  key: const ValueKey('variable_sheet_submit'),
                  onPressed: _submit,
                  child: const Text('Оплатить'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
