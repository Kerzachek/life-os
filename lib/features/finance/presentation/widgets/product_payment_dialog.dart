import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../data/repositories/finance_repository.dart';
import '../../domain/finance_enums.dart';
import '../providers/finance_provider.dart';
import 'finance_format.dart';

/// Платёж по кредиту ([FinanceAccountKind.loan]) или пополнение депозита
/// ([FinanceAccountKind.deposit]) со счёта.
class ProductPaymentDialog extends ConsumerStatefulWidget {
  const ProductPaymentDialog({super.key, required this.product});

  final FinanceAccountEntity product;

  @override
  ConsumerState<ProductPaymentDialog> createState() =>
      _ProductPaymentDialogState();
}

class _ProductPaymentDialogState extends ConsumerState<ProductPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  String? _fromId;

  bool get _isLoan =>
      widget.product.kind == FinanceAccountKind.loan.value;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    final suggested = _isLoan ? p.monthlyPayment : null;
    _amount = TextEditingController(text: suggested == null ? '' : '$suggested');
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final repo = ref.read(financeRepositoryProvider);
    final navigator = Navigator.of(context);
    final amount = parseMoney(_amount.text)!;
    final from = _fromId!;

    if (_isLoan) {
      await repo.recordLoanPayment(
        loanId: widget.product.id,
        fromAccountId: from,
        amount: amount,
      );
    } else {
      await repo.recordDepositTopUp(
        depositId: widget.product.id,
        fromAccountId: from,
        amount: amount,
      );
    }
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = (ref.watch(financeAccountsProvider).value ?? const [])
        .where((a) => a.kind == FinanceAccountKind.account.value)
        .toList();
    if (_fromId == null && accounts.isNotEmpty) _fromId = accounts.first.id;

    return AlertDialog(
      title: Text(_isLoan
          ? 'Платёж по кредиту «${widget.product.name}»'
          : 'Пополнить «${widget.product.name}»'),
      content: SizedBox(
        width: 360,
        child: accounts.isEmpty
            ? const Text('Сначала создайте счёт, с которого будут списаны деньги.')
            : Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      key: const ValueKey('payment_from'),
                      initialValue: _fromId,
                      decoration: const InputDecoration(
                        labelText: 'Со счёта',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final a in accounts)
                          DropdownMenuItem(
                            value: a.id,
                            child: Text('${a.name} · ${formatMoney(a.balance)}'),
                          ),
                      ],
                      onChanged: (v) => setState(() => _fromId = v),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('payment_amount'),
                      controller: _amount,
                      autofocus: true,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Сумма *',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final n = parseMoney(v);
                        return (n == null || n <= 0) ? 'Сумма > 0' : null;
                      },
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        if (accounts.isNotEmpty)
          FilledButton(
            key: const ValueKey('payment_submit'),
            onPressed: _submit,
            child: Text(_isLoan ? 'Внести платёж' : 'Пополнить'),
          ),
      ],
    );
  }
}
