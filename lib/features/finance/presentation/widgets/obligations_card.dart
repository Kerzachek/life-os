import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/repositories/finance_repository.dart';
import '../../domain/finance_calculations.dart';
import '../providers/finance_provider.dart';
import 'account_picker.dart';
import 'confirm_dialog.dart';
import 'finance_format.dart';
import 'obligation_tile.dart';

/// Операционный список «К оплате в этом месяце»: прогресс и чекбоксы оплаты.
/// Шаблоны платежей настраиваются на вкладке «Настройки».
class ObligationsCard extends ConsumerWidget {
  const ObligationsCard({super.key});

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    ObligationStatus status,
    bool paid,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(financeRepositoryProvider);
    final name = status.obligation.name;

    if (!paid) {
      final ok = await confirmAction(
        context,
        title: 'Отменить оплату «$name»?',
        message: 'Расходная операция будет удалена, сумма вернётся на счёт.',
        confirmLabel: 'Отменить оплату',
      );
      if (!ok) return;
      await repo.undoObligationPayment(obligationId: status.obligation.id);
      return;
    }

    final accounts = ref.read(financeAccountsProvider).value ?? const [];
    final accountId = await pickPayerAccount(context, accounts);
    if (accountId == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Нет счёта для списания')),
      );
      return;
    }
    final ok = await repo.payObligation(
      obligationId: status.obligation.id,
      fromAccountId: accountId,
    );
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Платёж за этот месяц уже оплачен')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final statuses = ref.watch(obligationStatusesProvider);
    final summary = ref.watch(financeSummaryProvider).value;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'К оплате в этом месяце',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (summary != null && summary.obligationsTotal > 0) ...[
              const SizedBox(height: 4),
              Text(
                'Оплачено ${formatMoney(summary.obligationsPaid)} '
                'из ${formatMoney(summary.obligationsTotal)} · '
                'осталось ${formatMoney(summary.obligationsRemaining)}',
                key: const ValueKey('obligations_progress_text'),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: summary.obligationsProgress,
                  minHeight: 8,
                  color: AppTheme.successAccent,
                  backgroundColor: AppTheme.darkBorder,
                ),
              ),
            ],
            const SizedBox(height: 8),
            statuses.when(
              data: (items) {
                if (items.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Обязательных платежей пока нет. '
                      'Добавьте их в разделе «Настройки».',
                      key: const ValueKey('obligations_empty'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final s in items)
                      ObligationTile(
                        status: s,
                        onChanged: (paid) => _toggle(context, ref, s, paid),
                      ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Ошибка: $e'),
            ),
          ],
        ),
      ),
    );
  }
}
