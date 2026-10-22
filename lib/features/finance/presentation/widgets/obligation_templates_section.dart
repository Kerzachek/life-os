import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/widgets/responsive.dart';
import '../../data/repositories/finance_repository.dart';
import '../providers/finance_provider.dart';
import 'confirm_dialog.dart';
import 'finance_format.dart';
import 'obligation_dialog.dart';

/// Раздел «Обязательные платежи» в настройках: управление шаблонами
/// (название, сумма, число месяца, категория).
class ObligationTemplatesSection extends ConsumerWidget {
  const ObligationTemplatesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final obligations = ref.watch(financeObligationsProvider);
    final categories = ref.watch(financeCategoryMapProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Обязательные платежи',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            FilledButton.icon(
              key: const ValueKey('add_obligation'),
              onPressed: () => showFormSheet<void>(
                context: context,
                builder: (_) => const ObligationDialog(),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Платёж'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Шаблоны повторяются каждый месяц и появляются на обзоре '
          'в списке «К оплате в этом месяце».',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        obligations.when(
          data: (items) {
            if (items.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Шаблонов пока нет',
                  key: const ValueKey('obligation_templates_empty'),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              );
            }
            return Column(
              children: [
                for (final o in items)
                  _TemplateTile(
                    obligation: o,
                    categoryName: categories[o.categoryId]?.name,
                  ),
              ],
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text('Ошибка: $e'),
        ),
      ],
    );
  }
}

class _TemplateTile extends ConsumerWidget {
  const _TemplateTile({required this.obligation, this.categoryName});

  final ObligationEntity obligation;
  final String? categoryName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = obligation;
    final isLoan = o.loanAccountId != null;
    final parts = [
      formatMoney(o.amount),
      'каждое ${o.dueDay} число',
      ?categoryName,
    ];

    return Card(
      key: ValueKey('template_${o.id}'),
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: Icon(isLoan ? Icons.account_balance : Icons.event_repeat),
        title: Text(o.name),
        subtitle: Text(
          isLoan
              ? '${parts.join(' · ')} · управляется кредитом'
              : parts.join(' · '),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isLoan)
              IconButton(
                key: ValueKey('edit_template_${o.id}'),
                tooltip: 'Изменить',
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: () => showFormSheet<void>(
                  context: context,
                  builder: (_) => ObligationDialog(obligation: o),
                ),
              ),
            IconButton(
              key: ValueKey('delete_template_${o.id}'),
              tooltip: 'Удалить',
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () async {
                final repo = ref.read(financeRepositoryProvider);
                final ok = await confirmAction(
                  context,
                  title: 'Удалить «${o.name}»?',
                  message: 'Уже созданные операции останутся в ленте.',
                );
                if (ok) await repo.deleteObligation(o.id);
              },
            ),
          ],
        ),
      ),
    );
  }
}
