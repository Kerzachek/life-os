import 'package:flutter/material.dart';

import '../../data/repositories/finance_repository.dart' show roundMoney;
import '../../domain/finance_calculations.dart';
import 'finance_format.dart';

/// Открывает компактную шторку правки ближайшего списания рассрочки:
/// дата (календарь или быстрые сдвиги) и сумма. Возвращает `null` при отмене.
///
/// [maxAmount] — остаток долга: сумма доли не может его превышать.
Future<FlexiblePaymentStep?> showFlexiblePaymentSheet(
  BuildContext context, {
  required String title,
  String? message,
  required DateTime initialDate,
  required double initialAmount,
  double? maxAmount,
  String confirmLabel = 'Сохранить',
}) {
  return showModalBottomSheet<FlexiblePaymentStep>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _FlexiblePaymentSheet(
      title: title,
      message: message,
      initialDate: initialDate,
      initialAmount: initialAmount,
      maxAmount: maxAmount,
      confirmLabel: confirmLabel,
    ),
  );
}

class _FlexiblePaymentSheet extends StatefulWidget {
  const _FlexiblePaymentSheet({
    required this.title,
    required this.message,
    required this.initialDate,
    required this.initialAmount,
    required this.maxAmount,
    required this.confirmLabel,
  });

  final String title;
  final String? message;
  final DateTime initialDate;
  final double initialAmount;
  final double? maxAmount;
  final String confirmLabel;

  @override
  State<_FlexiblePaymentSheet> createState() => _FlexiblePaymentSheetState();
}

class _FlexiblePaymentSheetState extends State<_FlexiblePaymentSheet> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _date;
  late final TextEditingController _amount;

  /// Быстрые сдвиги даты от исходной: подпись → дней.
  static const _shifts = {'+1 нед.': 7, '+2 нед.': 14, '+1 мес.': 30};

  @override
  void initState() {
    super.initState();
    _date = dateOnly(widget.initialDate);
    _amount =
        TextEditingController(text: '${roundMoney(widget.initialAmount)}');
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      FlexiblePaymentStep(date: _date, amount: parseMoney(_amount.text)!),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final base = dateOnly(widget.initialDate);
    final max = widget.maxAmount;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + keyboard),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: theme.textTheme.titleLarge),
            if (widget.message != null) ...[
              const SizedBox(height: 4),
              Text(
                widget.message!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const ValueKey('flex_sheet_date'),
              onPressed: _pickDate,
              icon: const Icon(Icons.event, size: 18),
              label: Text('Дата списания: ${formatDate(_date)}'),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final e in _shifts.entries)
                  ActionChip(
                    label: Text(e.key),
                    onPressed: () => setState(() => _date =
                        DateTime(base.year, base.month, base.day + e.value)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('flex_sheet_amount'),
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Сумма списания',
                helperText:
                    max == null ? null : 'Остаток долга: ${formatMoney(max)}',
                border: const OutlineInputBorder(),
              ),
              validator: (v) {
                final n = parseMoney(v);
                if (n == null || n <= 0) return 'Сумма > 0';
                if (max != null && n > max + 0.005) {
                  return 'Больше остатка долга';
                }
                return null;
              },
            ),
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
                  key: const ValueKey('flex_sheet_submit'),
                  onPressed: _submit,
                  child: Text(widget.confirmLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
