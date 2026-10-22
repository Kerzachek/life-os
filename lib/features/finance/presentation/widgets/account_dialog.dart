import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/widgets/responsive.dart';
import '../../data/repositories/finance_repository.dart';
import '../../domain/finance_enums.dart';
import 'finance_format.dart';

/// Форма создания / редактирования счёта, кредита или депозита.
class AccountDialog extends ConsumerStatefulWidget {
  const AccountDialog({super.key, this.account, this.initialKind});

  final FinanceAccountEntity? account;
  final FinanceAccountKind? initialKind;

  @override
  ConsumerState<AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends ConsumerState<AccountDialog> {
  final _formKey = GlobalKey<FormState>();
  late FinanceAccountKind _kind;
  late final TextEditingController _name;
  late final TextEditingController _balance;
  late final TextEditingController _target;
  late final TextEditingController _rate;
  late final TextEditingController _term;
  late final TextEditingController _payment;
  late final TextEditingController _day;
  late final TextEditingController _nextAmount;

  /// Плавающий график (Сплит / Долями): дата и сумма ближайшего списания
  /// вместо ежемесячного платежа.
  late bool _flexible;
  DateTime? _nextDate;

  bool get _isEdit => widget.account != null;

  static String _text(num? v) => v == null ? '' : '$v';

  @override
  void initState() {
    super.initState();
    final a = widget.account;
    _kind = a != null
        ? FinanceAccountKind.fromValue(a.kind)
        : (widget.initialKind ?? FinanceAccountKind.account);
    _name = TextEditingController(text: a?.name ?? '');
    _balance = TextEditingController(text: a == null ? '0' : '${a.balance}');
    _target = TextEditingController(text: _text(a?.targetAmount));
    _rate = TextEditingController(text: _text(a?.interestRate));
    _term = TextEditingController(text: _text(a?.termMonths));
    _payment = TextEditingController(text: _text(a?.monthlyPayment));
    _day = TextEditingController(text: _text(a?.paymentDay));
    _nextAmount = TextEditingController(text: _text(a?.nextPaymentAmount));
    _flexible = a?.isFlexibleSchedule ?? false;
    _nextDate = a?.nextPaymentDate?.toLocal();
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _balance,
      _target,
      _rate,
      _term,
      _payment,
      _day,
      _nextAmount,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickNextDate(FormFieldState<DateTime> field) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _nextDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => _nextDate = picked);
    field.didChange(picked);
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final repo = ref.read(financeRepositoryProvider);
    final navigator = Navigator.of(context);
    final isLoan = _kind == FinanceAccountKind.loan;
    final isDeposit = _kind == FinanceAccountKind.deposit;

    final name = _name.text.trim();
    final balance = parseMoney(_balance.text) ?? 0;
    final target = isLoan || isDeposit ? parseMoney(_target.text) : null;
    final rate = isLoan || isDeposit ? parseMoney(_rate.text) : null;
    final term = isDeposit ? int.tryParse(_term.text.trim()) : null;
    final flexible = isLoan && _flexible;
    final payment = isLoan && !flexible ? parseMoney(_payment.text) : null;
    final day = isLoan && !flexible ? int.tryParse(_day.text.trim()) : null;
    final nextDate = flexible ? _nextDate : null;
    final nextAmount = flexible ? parseMoney(_nextAmount.text) : null;

    if (_isEdit) {
      await repo.updateAccount(
        id: widget.account!.id,
        name: name,
        kind: _kind,
        balance: balance,
        targetAmount: target,
        interestRate: rate,
        termMonths: term,
        monthlyPayment: payment,
        paymentDay: day,
        isFlexibleSchedule: flexible,
        nextPaymentDate: nextDate,
        nextPaymentAmount: nextAmount,
      );
    } else {
      await repo.createAccount(
        name: name,
        kind: _kind,
        balance: balance,
        targetAmount: target,
        interestRate: rate,
        termMonths: term,
        monthlyPayment: payment,
        paymentDay: day,
        isFlexibleSchedule: flexible,
        nextPaymentDate: nextDate,
        nextPaymentAmount: nextAmount,
      );
    }
    navigator.pop();
  }

  String? _optionalMoney(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final n = parseMoney(v);
    return (n == null || n < 0) ? 'Число ≥ 0' : null;
  }

  String? _requiredPositive(String? v) {
    final n = parseMoney(v);
    return (n == null || n <= 0) ? 'Сумма > 0' : null;
  }

  String? _requiredDay(String? v) {
    final n = int.tryParse(v?.trim() ?? '');
    return (n == null || n < 1 || n > 31) ? '1–31' : null;
  }

  Widget _moneyField(
    Key key,
    TextEditingController controller,
    String label,
    String? Function(String?) validator,
  ) {
    return TextFormField(
      key: key,
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      validator: validator,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLoan = _kind == FinanceAccountKind.loan;
    final isDeposit = _kind == FinanceAccountKind.deposit;
    const gap = SizedBox(height: 12);

    return AdaptiveFormDialog(
      title: Text(_isEdit ? 'Редактировать продукт' : 'Новый продукт'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<FinanceAccountKind>(
                  key: const ValueKey('account_kind'),
                  initialValue: _kind,
                  decoration: const InputDecoration(
                    labelText: 'Тип',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final k in FinanceAccountKind.values)
                      DropdownMenuItem(value: k, child: Text(k.label)),
                  ],
                  onChanged: _isEdit
                      ? null
                      : (v) => setState(() => _kind = v ?? _kind),
                ),
                gap,
                TextFormField(
                  key: const ValueKey('account_name'),
                  controller: _name,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Название *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Введите название'
                      : null,
                ),
                gap,
                _moneyField(
                  const ValueKey('account_balance'),
                  _balance,
                  isLoan ? 'Остаток долга *' : 'Баланс *',
                  (v) {
                    final n = parseMoney(v);
                    if (n == null) return 'Число';
                    if (isLoan && n < 0) return 'Долг не может быть < 0';
                    return null;
                  },
                ),
                if (isLoan || isDeposit) ...[
                  gap,
                  _moneyField(
                    const ValueKey('account_target'),
                    _target,
                    isLoan ? 'Общая сумма задолженности' : 'Цель накопления',
                    _optionalMoney,
                  ),
                  gap,
                  _moneyField(
                    const ValueKey('account_rate'),
                    _rate,
                    'Процентная ставка, % годовых',
                    _optionalMoney,
                  ),
                ],
                if (isDeposit) ...[
                  gap,
                  TextFormField(
                    key: const ValueKey('account_term'),
                    controller: _term,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Срок, месяцев',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      final n = int.tryParse(v.trim());
                      return (n == null || n <= 0) ? 'Целое > 0' : null;
                    },
                  ),
                ],
                if (isLoan) ...[
                  gap,
                  SwitchListTile(
                    key: const ValueKey('account_flexible'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Плавающие платежи (Сплит / Долями)'),
                    subtitle: const Text(
                      'Дата и сумма каждого списания задаются отдельно',
                    ),
                    value: _flexible,
                    onChanged: (v) => setState(() => _flexible = v),
                  ),
                ],
                if (isLoan && _flexible) ...[
                  gap,
                  FormField<DateTime>(
                    key: const ValueKey('account_next_date'),
                    initialValue: _nextDate,
                    validator: (_) =>
                        _nextDate == null ? 'Выберите дату' : null,
                    builder: (field) => InkWell(
                      onTap: () => _pickNextDate(field),
                      borderRadius: BorderRadius.circular(4),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Дата ближайшего списания *',
                          border: const OutlineInputBorder(),
                          suffixIcon: const Icon(Icons.event),
                          errorText: field.errorText,
                        ),
                        child: Text(
                          _nextDate == null ? '' : formatDate(_nextDate!),
                        ),
                      ),
                    ),
                  ),
                  gap,
                  _moneyField(
                    const ValueKey('account_next_amount'),
                    _nextAmount,
                    'Сумма ближайшего списания *',
                    _requiredPositive,
                  ),
                ],
                if (isLoan && !_flexible) ...[
                  gap,
                  Row(
                    children: [
                      Expanded(
                        child: _moneyField(
                          const ValueKey('account_payment'),
                          _payment,
                          'Платёж в месяц *',
                          _requiredPositive,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          key: const ValueKey('account_day'),
                          controller: _day,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'День списания *',
                            border: OutlineInputBorder(),
                          ),
                          validator: _requiredDay,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          key: const ValueKey('account_submit'),
          onPressed: _submit,
          child: Text(_isEdit ? 'Сохранить' : 'Создать'),
        ),
      ],
    );
  }
}
