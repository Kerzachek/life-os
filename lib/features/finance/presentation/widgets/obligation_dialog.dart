import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/widgets/responsive.dart';
import '../../data/repositories/finance_repository.dart';
import '../../domain/finance_calculations.dart';
import '../../domain/finance_category_presets.dart';
import '../../domain/finance_enums.dart';
import '../providers/finance_provider.dart';
import 'finance_format.dart';

/// Форма добавления / редактирования обязательного платежа: название,
/// сумма, день списания, категория, счёт списания и признак плавающей суммы
/// (с ручным ориентиром или медианой прошлых оплат).
class ObligationDialog extends ConsumerStatefulWidget {
  const ObligationDialog({super.key, this.obligation});

  final ObligationEntity? obligation;

  @override
  ConsumerState<ObligationDialog> createState() => _ObligationDialogState();
}

class _ObligationDialogState extends ConsumerState<ObligationDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late final TextEditingController _day;
  late final TextEditingController _estimate;
  String? _categoryId;
  String? _accountId;
  late bool _isVariable;
  late bool _manualEstimate;

  bool get _isEdit => widget.obligation != null;

  @override
  void initState() {
    super.initState();
    final o = widget.obligation;
    _name = TextEditingController(text: o?.name ?? '');
    _amount = TextEditingController(text: o == null ? '' : '${o.amount}');
    _day = TextEditingController(text: '${o?.dueDay ?? 1}');
    _estimate = TextEditingController(
      text: o?.estimatedAmount == null ? '' : '${o!.estimatedAmount}',
    );
    _categoryId = o?.categoryId ?? FinanceCategoryIds.obligations;
    _accountId = o?.accountId;
    _isVariable = o?.isVariableAmount ?? false;
    _manualEstimate = o?.estimatedAmount != null;
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _day.dispose();
    _estimate.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final repo = ref.read(financeRepositoryProvider);
    final amount = parseMoney(_amount.text)!;
    final day = int.parse(_day.text.trim());
    final estimate = _isVariable && _manualEstimate
        ? parseMoney(_estimate.text)
        : null;
    final navigator = Navigator.of(context);

    if (_isEdit) {
      await repo.updateObligation(
        id: widget.obligation!.id,
        name: _name.text.trim(),
        amount: amount,
        dueDay: day,
        categoryId: _categoryId,
        loanAccountId: widget.obligation!.loanAccountId,
        accountId: _accountId,
        isVariableAmount: _isVariable,
        estimatedAmount: estimate,
      );
    } else {
      await repo.createObligation(
        name: _name.text.trim(),
        amount: amount,
        dueDay: day,
        categoryId: _categoryId,
        accountId: _accountId,
        isVariableAmount: _isVariable,
        estimatedAmount: estimate,
      );
    }
    navigator.pop();
  }

  /// Подпись к автоматической оценке: медиана прошлых оплат или базовая сумма.
  String _medianHint() {
    final o = widget.obligation;
    final transactions = ref.watch(financeTransactionsProvider).value;
    if (o == null || transactions == null) {
      return 'Пока нет оплат — для бюджета берётся базовая сумма';
    }
    final history = obligationPaymentHistory(o, transactions);
    final value = obligationMedianPayment(o, transactions);
    if (value == null) {
      return 'Пока нет оплат — для бюджета берётся базовая сумма';
    }
    final count = history.length.clamp(0, variableEstimateWindow);
    return 'Медиана последних оплат ($count): ${formatMoney(value)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = (ref.watch(financeCategoriesProvider).value ?? const [])
        .where((c) => !c.isIncome)
        .toList();
    final validCategory = categories.any((c) => c.id == _categoryId);
    final accounts = (ref.watch(financeAccountsProvider).value ?? const [])
        .where((a) => a.kind == FinanceAccountKind.account.value)
        .toList();
    final validAccount = accounts.any((a) => a.id == _accountId);

    return AdaptiveFormDialog(
      title: Text(
        _isEdit ? 'Редактировать платёж' : 'Новый обязательный платёж',
      ),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const ValueKey('obligation_name'),
                  controller: _name,
                  autofocus: !_isEdit,
                  decoration: const InputDecoration(
                    labelText: 'Название *',
                    hintText: 'Аренда, ЖКХ, интернет...',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Введите название'
                      : null,
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const ValueKey('obligation_amount'),
                        controller: _amount,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: _isVariable
                              ? 'Базовая сумма *'
                              : 'Сумма *',
                          border: const OutlineInputBorder(),
                        ),
                        validator: (v) {
                          final n = parseMoney(v);
                          return (n == null || n <= 0) ? 'Сумма > 0' : null;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        key: const ValueKey('obligation_day'),
                        controller: _day,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'День месяца *',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          final n = int.tryParse(v?.trim() ?? '');
                          return (n == null || n < 1 || n > 31) ? '1–31' : null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: validCategory ? _categoryId : null,
                  decoration: const InputDecoration(
                    labelText: 'Категория',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final c in categories)
                      DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (v) => setState(() => _categoryId = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  key: const ValueKey('obligation_account'),
                  initialValue: validAccount ? _accountId : null,
                  decoration: const InputDecoration(
                    labelText: 'Счёт списания',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Выбирать при оплате'),
                    ),
                    for (final a in accounts)
                      DropdownMenuItem<String?>(
                        value: a.id,
                        child: Text(a.name),
                      ),
                  ],
                  onChanged: (v) => setState(() => _accountId = v),
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  key: const ValueKey('obligation_variable'),
                  contentPadding: EdgeInsets.zero,
                  value: _isVariable,
                  onChanged: (v) => setState(() => _isVariable = v),
                  title: const Text('Плавающая сумма'),
                  subtitle: const Text(
                    'ЖКХ, свет, счётчики: точная сумма вводится при оплате',
                  ),
                ),
                if (_isVariable) ...[
                  SwitchListTile(
                    key: const ValueKey('obligation_manual_estimate'),
                    contentPadding: EdgeInsets.zero,
                    value: _manualEstimate,
                    onChanged: (v) => setState(() => _manualEstimate = v),
                    title: const Text('Задать ориентир вручную'),
                    subtitle: Text(
                      _manualEstimate
                          ? 'Бюджет планируется по указанной сумме'
                          : _medianHint(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (_manualEstimate)
                    TextFormField(
                      key: const ValueKey('obligation_estimate'),
                      controller: _estimate,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Ориентир для бюджета *',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final n = parseMoney(v);
                        return (n == null || n <= 0) ? 'Сумма > 0' : null;
                      },
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
          key: const ValueKey('obligation_submit'),
          onPressed: _submit,
          child: Text(_isEdit ? 'Сохранить' : 'Создать'),
        ),
      ],
    );
  }
}
