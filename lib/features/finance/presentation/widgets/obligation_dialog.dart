import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../data/repositories/finance_repository.dart';
import '../../domain/finance_category_presets.dart';
import '../providers/finance_provider.dart';
import 'finance_format.dart';

/// Форма добавления / редактирования обязательного платежа.
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
  String? _categoryId;

  bool get _isEdit => widget.obligation != null;

  @override
  void initState() {
    super.initState();
    final o = widget.obligation;
    _name = TextEditingController(text: o?.name ?? '');
    _amount = TextEditingController(text: o == null ? '' : '${o.amount}');
    _day = TextEditingController(text: '${o?.dueDay ?? 1}');
    _categoryId = o?.categoryId ?? FinanceCategoryIds.obligations;
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _day.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final repo = ref.read(financeRepositoryProvider);
    final amount = parseMoney(_amount.text)!;
    final day = int.parse(_day.text.trim());
    final navigator = Navigator.of(context);

    if (_isEdit) {
      await repo.updateObligation(
        id: widget.obligation!.id,
        name: _name.text.trim(),
        amount: amount,
        dueDay: day,
        categoryId: _categoryId,
        loanAccountId: widget.obligation!.loanAccountId,
      );
    } else {
      await repo.createObligation(
        name: _name.text.trim(),
        amount: amount,
        dueDay: day,
        categoryId: _categoryId,
      );
    }
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final categories = (ref.watch(financeCategoriesProvider).value ?? const [])
        .where((c) => !c.isIncome)
        .toList();
    final validCategory = categories.any((c) => c.id == _categoryId);

    return AlertDialog(
      title: Text(_isEdit ? 'Редактировать платёж' : 'Новый обязательный платёж'),
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
                  autofocus: true,
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
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const ValueKey('obligation_amount'),
                        controller: _amount,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Сумма *',
                          border: OutlineInputBorder(),
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
                          return (n == null || n < 1 || n > 31)
                              ? '1–31'
                              : null;
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
