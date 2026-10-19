import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/task_category.dart';

/// Выпадающий список категорий в стиле тёмной темы: тёмный фон меню,
/// аккуратный бордер, неоновая подсветка выбранного пункта.
class CategoryDropdownField extends StatelessWidget {
  final TaskCategory value;
  final ValueChanged<TaskCategory> onChanged;

  const CategoryDropdownField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(12);
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide(color: color, width: width),
        );

    return DropdownButtonFormField<TaskCategory>(
      key: const ValueKey('task-category-dropdown'),
      initialValue: value,
      isExpanded: true,
      dropdownColor: AppTheme.darkSurface,
      borderRadius: borderRadius,
      icon: Icon(Icons.expand_more_rounded, color: value.color),
      decoration: InputDecoration(
        labelText: 'Категория',
        filled: true,
        fillColor: AppTheme.darkSurface,
        border: border(AppTheme.darkBorder),
        enabledBorder: border(AppTheme.darkBorder),
        focusedBorder: border(value.color, 1.5),
      ),
      // В закрытом поле — иконка и название выбранной категории.
      selectedItemBuilder: (context) => [
        for (final c in TaskCategory.values) _CategoryRow(category: c),
      ],
      items: [
        for (final c in TaskCategory.values)
          DropdownMenuItem<TaskCategory>(
            value: c,
            child: _CategoryMenuItem(category: c, selected: c == value),
          ),
      ],
      onChanged: (val) {
        if (val != null) onChanged(val);
      },
    );
  }
}

class _CategoryRow extends StatelessWidget {
  final TaskCategory category;

  const _CategoryRow({required this.category});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(category.icon, size: 18, color: category.color),
        const SizedBox(width: 10),
        Flexible(
          child: Text(category.label, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

class _CategoryMenuItem extends StatelessWidget {
  final TaskCategory category;
  final bool selected;

  const _CategoryMenuItem({required this.category, required this.selected});

  @override
  Widget build(BuildContext context) {
    final color = category.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: selected ? color.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? color : Colors.transparent,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.45),
                  blurRadius: 8,
                  spreadRadius: -1,
                ),
              ]
            : null,
      ),
      child: _CategoryRow(category: category),
    );
  }
}
