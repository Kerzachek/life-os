import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../data/repositories/finance_repository.dart';
import '../../domain/finance_icons.dart';
import '../providers/finance_provider.dart';
import 'category_dialog.dart';
import 'confirm_dialog.dart';
import 'obligation_templates_section.dart';

/// Вкладка «Настройки финансов»: шаблоны обязательных платежей и категории.
class FinanceSettingsTab extends ConsumerWidget {
  const FinanceSettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(financeCategoriesProvider);

    return categories.when(
      data: (items) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          const ObligationTemplatesSection(),
          const SizedBox(height: 24),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Категории',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              FilledButton.icon(
                key: const ValueKey('add_category'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const CategoryDialog(),
                ),
                icon: const Icon(Icons.add),
                label: const Text('Категория'),
              ),
            ],
          ),
          _Section(
            title: 'РАСХОДЫ',
            items: items.where((c) => !c.isIncome).toList(),
          ),
          _Section(
            title: 'ДОХОДЫ',
            items: items.where((c) => c.isIncome).toList(),
          ),
        ],
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Ошибка: $e')),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.items});

  final String title;
  final List<FinanceCategoryEntity> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 16, 0, 8),
          child: Text(
            title,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 1.2,
            ),
          ),
        ),
        for (final c in items) _CategoryTile(category: c),
      ],
    );
  }
}

class _CategoryTile extends ConsumerWidget {
  const _CategoryTile({required this.category});

  final FinanceCategoryEntity category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = financeColorFromHex(category.color);
    return Card(
      key: ValueKey('category_${category.id}'),
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: color.withValues(alpha: 0.18),
          child: Icon(financeIconByKey(category.icon), color: color, size: 18),
        ),
        title: Text(category.name),
        subtitle: category.isSystem ? const Text('Предустановленная') : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Изменить',
              icon: const Icon(Icons.edit_outlined, size: 18),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => CategoryDialog(category: category),
              ),
            ),
            if (!category.isSystem)
              IconButton(
                key: ValueKey('delete_category_${category.id}'),
                tooltip: 'Удалить',
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () async {
                  final repo = ref.read(financeRepositoryProvider);
                  final ok = await confirmAction(
                    context,
                    title: 'Удалить «${category.name}»?',
                    message: 'Операции останутся без категории.',
                  );
                  if (ok) await repo.deleteCategory(category.id);
                },
              ),
          ],
        ),
      ),
    );
  }
}
