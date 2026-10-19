import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../data/repositories/finance_repository.dart';
import '../../domain/finance_icons.dart';
import 'choice_tile.dart';

/// Форма добавления / редактирования категории (название, иконка, цвет).
class CategoryDialog extends ConsumerStatefulWidget {
  const CategoryDialog({super.key, this.category});

  final FinanceCategoryEntity? category;

  @override
  ConsumerState<CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends ConsumerState<CategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late String _iconKey;
  late Color _color;
  bool _isIncome = false;

  bool get _isEdit => widget.category != null;

  @override
  void initState() {
    super.initState();
    final c = widget.category;
    _name = TextEditingController(text: c?.name ?? '');
    _iconKey = financeIcons.containsKey(c?.icon) ? c!.icon! : defaultFinanceIconKey;
    _color = c == null ? financeColorPalette.first : financeColorFromHex(c.color);
    _isIncome = c?.isIncome ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final repo = ref.read(financeRepositoryProvider);
    final navigator = Navigator.of(context);
    if (_isEdit) {
      await repo.updateCategory(
        id: widget.category!.id,
        name: _name.text.trim(),
        iconKey: _iconKey,
        colorHex: financeColorToHex(_color),
      );
    } else {
      await repo.createCategory(
        name: _name.text.trim(),
        iconKey: _iconKey,
        colorHex: financeColorToHex(_color),
        isIncome: _isIncome,
      );
    }
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final label = Theme.of(context).textTheme.labelMedium;
    return AlertDialog(
      title: Text(_isEdit ? 'Редактировать категорию' : 'Новая категория'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  key: const ValueKey('category_name'),
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
                if (!_isEdit) ...[
                  const SizedBox(height: 12),
                  SegmentedButton<bool>(
                    key: const ValueKey('category_kind'),
                    segments: const [
                      ButtonSegment(value: false, label: Text('Расход')),
                      ButtonSegment(value: true, label: Text('Доход')),
                    ],
                    selected: {_isIncome},
                    onSelectionChanged: (s) =>
                        setState(() => _isIncome = s.first),
                  ),
                ],
                const SizedBox(height: 16),
                Text('Иконка', style: label),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final e in financeIcons.entries)
                      ChoiceTile(
                        key: ValueKey('icon_${e.key}'),
                        selected: e.key == _iconKey,
                        color: _color,
                        onTap: () => setState(() => _iconKey = e.key),
                        child: Icon(e.value, size: 20),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Цвет', style: label),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var i = 0; i < financeColorPalette.length; i++)
                      ChoiceTile(
                        key: ValueKey('color_$i'),
                        selected: financeColorPalette[i] == _color,
                        color: financeColorPalette[i],
                        onTap: () =>
                            setState(() => _color = financeColorPalette[i]),
                        child: CircleAvatar(
                          radius: 10,
                          backgroundColor: financeColorPalette[i],
                        ),
                      ),
                  ],
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
          key: const ValueKey('category_submit'),
          onPressed: _submit,
          child: Text(_isEdit ? 'Сохранить' : 'Создать'),
        ),
      ],
    );
  }
}
