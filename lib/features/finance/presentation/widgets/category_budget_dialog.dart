import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/responsive.dart';
import '../../data/repositories/finance_repository.dart';
import '../../domain/category_budgets.dart';
import '../../domain/finance_icons.dart';
import '../providers/finance_provider.dart';
import 'finance_format.dart';

/// Форма месячного лимита категории: действует с месяца [month] и далее.
/// [budget] — редактирование существующего лимита (категорию не сменить).
class CategoryBudgetDialog extends ConsumerStatefulWidget {
  const CategoryBudgetDialog({super.key, required this.month, this.budget});

  final DateTime month;
  final CategoryBudgetStatus? budget;

  @override
  ConsumerState<CategoryBudgetDialog> createState() =>
      _CategoryBudgetDialogState();
}

class _CategoryBudgetDialogState extends ConsumerState<CategoryBudgetDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _limit;
  String? _categoryId;

  bool get _isEdit => widget.budget != null;

  @override
  void initState() {
    super.initState();
    final b = widget.budget;
    _categoryId = b?.category.id;
    _limit = TextEditingController(
      text: b == null ? '' : b.limit.toStringAsFixed(b.limit % 1 == 0 ? 0 : 2),
    );
  }

  @override
  void dispose() {
    _limit.dispose();
    super.dispose();
  }

  Future<void> _save({bool remove = false}) async {
    if (!remove && !(_formKey.currentState?.validate() ?? false)) return;
    final navigator = Navigator.of(context);
    await ref.read(financeRepositoryProvider).setCategoryBudget(
          categoryId: _categoryId!,
          month: widget.month,
          limit: remove ? null : parseMoney(_limit.text),
        );
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final withLimit = {
      for (final s in ref.watch(categoryBudgetsProvider).value ?? const [])
        s.category.id,
    };
    final categories = [
      for (final c in ref.watch(financeCategoriesProvider).value ?? const [])
        if (!c.isIncome && (c.id == _categoryId || !withLimit.contains(c.id)))
          c,
    ];

    return AdaptiveFormDialog(
      title: Text(_isEdit ? 'Лимит категории' : 'Новый лимит'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                key: const ValueKey('budget_category'),
                initialValue: _categoryId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Категория *',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final c in categories)
                    DropdownMenuItem(
                      value: c.id,
                      child: Row(
                        children: [
                          Icon(
                            financeIconByKey(c.icon),
                            size: 18,
                            color: financeColorFromHex(c.color),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(c.name, overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    ),
                ],
                onChanged: _isEdit
                    ? null
                    : (v) => setState(() => _categoryId = v),
                validator: (v) => v == null ? 'Выберите категорию' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('budget_limit'),
                controller: _limit,
                autofocus: _isEdit,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Лимит в месяц *',
                  suffixText: '₽',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final value = parseMoney(v);
                  return value == null || value <= 0
                      ? 'Введите сумму больше нуля'
                      : null;
                },
              ),
              const SizedBox(height: 8),
              Text(
                'Действует с месяца «${formatMonth(widget.month)}» и далее',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: muted),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (_isEdit)
          TextButton(
            key: const ValueKey('budget_remove'),
            onPressed: () => _save(remove: true),
            child: const Text('Снять лимит'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          key: const ValueKey('budget_submit'),
          onPressed: _save,
          child: Text(_isEdit ? 'Сохранить' : 'Создать'),
        ),
      ],
    );
  }
}
