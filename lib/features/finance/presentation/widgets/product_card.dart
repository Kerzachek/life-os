import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/repositories/finance_repository.dart';
import '../../domain/finance_enums.dart';
import 'account_dialog.dart';
import 'confirm_dialog.dart';
import 'finance_format.dart';
import 'product_payment_dialog.dart';

/// Карточка счёта, кредита или депозита.
class ProductCard extends ConsumerWidget {
  const ProductCard({super.key, required this.product});

  final FinanceAccountEntity product;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(financeRepositoryProvider);
    final ok = await confirmAction(
      context,
      title: 'Удалить «${product.name}»?',
      message: 'Операции по этому продукту тоже будут удалены.',
    );
    if (ok) await repo.deleteAccount(product.id);
  }

  /// Доля погашения кредита / накопления депозита (0..1) или `null`.
  double? _progress(FinanceAccountKind kind) {
    final target = product.targetAmount;
    if (target == null || target <= 0) return null;
    final raw = kind == FinanceAccountKind.loan
        ? 1 - product.balance / target
        : product.balance / target;
    return raw.clamp(0.0, 1.0);
  }

  String _progressLabel(FinanceAccountKind kind, double progress) {
    final percent = (progress * 100).toStringAsFixed(0);
    final target = formatMoney(product.targetAmount!);
    return kind == FinanceAccountKind.loan
        ? 'Погашено $percent% из $target'
        : 'Накоплено $percent% от цели $target';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final kind = FinanceAccountKind.fromValue(product.kind);
    final color = switch (kind) {
      FinanceAccountKind.account => AppTheme.primaryAccent,
      FinanceAccountKind.loan => AppTheme.fireAccent,
      FinanceAccountKind.deposit => AppTheme.secondaryAccent,
    };
    final payment = product.monthlyPayment;
    final details = <String>[
      if (product.interestRate != null) '${product.interestRate}%',
      if (product.termMonths != null) '${product.termMonths} мес.',
      if (kind == FinanceAccountKind.loan && payment != null)
        'платёж ${formatMoney(payment)}'
            '${product.paymentDay != null ? ' до ${product.paymentDay} числа' : ''}',
    ];
    final progress = _progress(kind);

    return Card(
      key: ValueKey('product_${product.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(kind.icon, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    product.name,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  formatMoney(product.balance),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: color, fontWeight: FontWeight.bold),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Действия',
                  onSelected: (v) {
                    if (v == 'edit') {
                      showDialog<void>(
                        context: context,
                        builder: (_) => AccountDialog(account: product),
                      );
                    } else {
                      _delete(context, ref);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Изменить')),
                    PopupMenuItem(value: 'delete', child: Text('Удалить')),
                  ],
                ),
              ],
            ),
            if (details.isNotEmpty)
              Text(
                details.join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            if (progress != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  color: color,
                  backgroundColor: AppTheme.darkBorder,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _progressLabel(kind, progress),
                style: theme.textTheme.labelSmall?.copyWith(color: muted),
              ),
            ],
            if (kind != FinanceAccountKind.account) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  key: ValueKey('product_action_${product.id}'),
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => ProductPaymentDialog(product: product),
                  ),
                  child: Text(kind == FinanceAccountKind.loan
                      ? 'Внести платёж'
                      : 'Пополнить'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
