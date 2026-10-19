import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../data/repositories/finance_repository.dart';
import '../../domain/finance_enums.dart';
import '../providers/finance_provider.dart';
import 'finance_format.dart';

/// Форма добавления / редактирования операции.
class TransactionDialog extends ConsumerStatefulWidget {
  const TransactionDialog({super.key, this.transaction});

  final FinanceTransactionEntity? transaction;

  @override
  ConsumerState<TransactionDialog> createState() => _TransactionDialogState();
}

class _TransactionDialogState extends ConsumerState<TransactionDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late FinanceTransactionType _type;
  late DateTime _date;
  String? _accountId;
  String? _targetId;
  String? _categoryId;
  String? _error;

  bool get _isEdit => widget.transaction != null;

  @override
  void initState() {
    super.initState();
    final t = widget.transaction;
    _type = t == null
        ? FinanceTransactionType.expense
        : FinanceTransactionType.fromValue(t.type);
    _date = t?.date.toLocal() ?? DateTime.now();
    _amount = TextEditingController(text: t == null ? '' : '${t.amount}');
    _note = TextEditingController(text: t?.note ?? '');
    _accountId = t?.accountId;
    _targetId = t?.targetAccountId;
    _categoryId = t?.categoryId;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
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

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final repo = ref.read(financeRepositoryProvider);
    final navigator = Navigator.of(context);
    final amount = parseMoney(_amount.text)!;
    final isTransfer = _type == FinanceTransactionType.transfer;
    final target = _type == FinanceTransactionType.income ? null : _targetId;
    final category = isTransfer ? null : _categoryId;

    try {
      if (_isEdit) {
        await repo.updateTransaction(
          id: widget.transaction!.id,
          type: _type,
          amount: amount,
          accountId: _accountId!,
          targetAccountId: target,
          categoryId: category,
          note: _note.text,
          date: _date,
        );
      } else {
        await repo.createTransaction(
          type: _type,
          amount: amount,
          accountId: _accountId!,
          targetAccountId: target,
          categoryId: category,
          note: _note.text,
          date: _date,
        );
      }
      navigator.pop();
    } on ArgumentError catch (e) {
      setState(() => _error = '${e.message}');
    }
  }

  void _changeType(FinanceTransactionType type) {
    setState(() {
      _type = type;
      _targetId = null;
      _categoryId = null;
      _error = null;
    });
  }

  DropdownMenuItem<String> _accountItem(FinanceAccountEntity a) {
    return DropdownMenuItem(
      value: a.id,
      child: Text('${a.name} · ${formatMoney(a.balance)}',
          overflow: TextOverflow.ellipsis),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(financeAccountsProvider).value ?? const [];
    final sources =
        all.where((a) => a.kind != FinanceAccountKind.loan.value).toList();
    final isIncome = _type == FinanceTransactionType.income;
    final isTransfer = _type == FinanceTransactionType.transfer;

    // Целевой продукт: для расхода — только кредит (погашение), для перевода —
    // любой продукт кроме источника.
    final targets = all.where((a) {
      if (isTransfer) return a.id != _accountId;
      return a.kind == FinanceAccountKind.loan.value;
    }).toList();
    final categories = (ref.watch(financeCategoriesProvider).value ?? const [])
        .where((c) => c.isIncome == isIncome)
        .toList();

    String? valid(String? id, Iterable<String> ids) =>
        ids.contains(id) ? id : null;
    _accountId = valid(_accountId, sources.map((a) => a.id)) ??
        (sources.isEmpty ? null : sources.first.id);
    final targetValue = valid(_targetId, targets.map((a) => a.id));
    final categoryValue = valid(_categoryId, categories.map((c) => c.id));

    return AlertDialog(
      title: Text(_isEdit ? 'Редактировать операцию' : 'Новая операция'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _typeSelector(),
                const SizedBox(height: 12),
                _amountField(),
                const SizedBox(height: 12),
                _accountField(sources, isIncome),
                if (!isIncome && (isTransfer || targets.isNotEmpty)) ...[
                  const SizedBox(height: 12),
                  _targetField(targets, targetValue, isTransfer),
                ],
                if (!isTransfer) ...[
                  const SizedBox(height: 12),
                  _categoryField(categories, categoryValue),
                ],
                const SizedBox(height: 12),
                _dateField(),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('tx_note'),
                  controller: _note,
                  decoration: const InputDecoration(
                    labelText: 'Заметка',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
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
          key: const ValueKey('tx_submit'),
          onPressed: _submit,
          child: Text(_isEdit ? 'Сохранить' : 'Добавить'),
        ),
      ],
    );
  }

  Widget _typeSelector() {
    return SegmentedButton<FinanceTransactionType>(
      key: const ValueKey('tx_type'),
      segments: [
        for (final t in FinanceTransactionType.values)
          ButtonSegment(
            value: t,
            label: Text(t.label),
            icon: Icon(t.icon, size: 16),
          ),
      ],
      selected: {_type},
      onSelectionChanged: (s) => _changeType(s.first),
    );
  }

  Widget _amountField() {
    return TextFormField(
      key: const ValueKey('tx_amount'),
      controller: _amount,
      autofocus: true,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(
        labelText: 'Сумма *',
        border: OutlineInputBorder(),
      ),
      validator: (v) {
        final n = parseMoney(v);
        return (n == null || n <= 0) ? 'Сумма > 0' : null;
      },
    );
  }

  Widget _accountField(List<FinanceAccountEntity> sources, bool isIncome) {
    return DropdownButtonFormField<String>(
      key: ValueKey('tx_account_${_type.value}'),
      initialValue: _accountId,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: isIncome ? 'Зачислить на счёт *' : 'Со счёта *',
        border: const OutlineInputBorder(),
      ),
      items: [for (final a in sources) _accountItem(a)],
      validator: (v) => v == null ? 'Нет доступных счетов' : null,
      onChanged: (v) => setState(() => _accountId = v),
    );
  }

  Widget _targetField(
    List<FinanceAccountEntity> targets,
    String? value,
    bool isTransfer,
  ) {
    return DropdownButtonFormField<String>(
      key: ValueKey('tx_target_${_type.value}'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: isTransfer
            ? 'На счёт / продукт *'
            : 'Погашение кредита (необязательно)',
        border: const OutlineInputBorder(),
      ),
      items: [
        if (!isTransfer)
          const DropdownMenuItem<String>(
            value: null,
            child: Text('— не кредитный платёж —'),
          ),
        for (final a in targets) _accountItem(a),
      ],
      validator: (v) => isTransfer && v == null ? 'Выберите получателя' : null,
      onChanged: (v) => setState(() => _targetId = v),
    );
  }

  Widget _categoryField(
    List<FinanceCategoryEntity> categories,
    String? value,
  ) {
    return DropdownButtonFormField<String>(
      key: ValueKey('tx_category_${_type.value}'),
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Категория',
        border: OutlineInputBorder(),
      ),
      items: [
        for (final c in categories)
          DropdownMenuItem(value: c.id, child: Text(c.name)),
      ],
      onChanged: (v) => setState(() => _categoryId = v),
    );
  }

  Widget _dateField() {
    return InkWell(
      key: const ValueKey('tx_date'),
      onTap: _pickDate,
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Дата',
          border: OutlineInputBorder(),
          suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
        ),
        child: Text(formatDate(_date)),
      ),
    );
  }
}
