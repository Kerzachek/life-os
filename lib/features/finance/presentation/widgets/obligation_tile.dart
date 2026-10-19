import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/finance_calculations.dart';
import 'finance_format.dart';

/// Строка обязательного платежа в карточке «К оплате в этом месяце»:
/// чекбокс оплаты, подсветка по срочности и подпись со сроком.
class ObligationTile extends StatelessWidget {
  const ObligationTile({
    super.key,
    required this.status,
    required this.onChanged,
  });

  final ObligationStatus status;

  /// `true` — отметили оплату, `false` — сняли отметку (отмена оплаты).
  final ValueChanged<bool> onChanged;

  static const Color _warning = Color(0xFFFF9F43);
  static const Color _danger = Color(0xFFFF6B6B);

  Color _color(ThemeData theme) {
    switch (status.urgency) {
      case ObligationUrgency.paid:
        return AppTheme.successAccent;
      case ObligationUrgency.overdue:
        return _danger;
      case ObligationUrgency.dueToday:
      case ObligationUrgency.upcoming:
        return _warning;
      case ObligationUrgency.scheduled:
        return theme.colorScheme.onSurfaceVariant;
    }
  }

  String _caption() {
    final o = status.obligation;
    final amount = formatMoney(o.amount);
    final days = status.daysUntilDue;
    switch (status.urgency) {
      case ObligationUrgency.paid:
        return '$amount · оплачено';
      case ObligationUrgency.overdue:
        return '$amount · просрочено на ${_days(-days)}';
      case ObligationUrgency.dueToday:
        return '$amount · сегодня срок оплаты';
      case ObligationUrgency.upcoming:
        return '$amount · через ${_days(days)} (${o.dueDay} числа)';
      case ObligationUrgency.scheduled:
        return '$amount · до ${o.dueDay} числа';
    }
  }

  static String _days(int n) {
    final mod100 = n % 100;
    final mod10 = n % 10;
    if (mod100 >= 11 && mod100 <= 14) return '$n дней';
    if (mod10 == 1) return '$n день';
    if (mod10 >= 2 && mod10 <= 4) return '$n дня';
    return '$n дней';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final o = status.obligation;
    final paid = status.isPaid;
    final color = _color(theme);
    final highlighted = status.needsAttention;

    return Padding(
      key: ValueKey('obligation_${o.id}'),
      padding: const EdgeInsets.only(bottom: 6),
      // Material, а не DecoratedBox: иначе ListTile не отрисует отклик на нажатие.
      child: Material(
        color: highlighted
            ? color.withValues(alpha: 0.10)
            : Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: highlighted
              ? BorderSide(color: color.withValues(alpha: 0.55))
              : BorderSide.none,
        ),
        child: CheckboxListTile(
          key: ValueKey('pay_${o.id}'),
          dense: true,
          value: paid,
          activeColor: AppTheme.successAccent,
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
          title: Text(
            o.name,
            style: TextStyle(
              fontWeight: highlighted ? FontWeight.w600 : null,
              decoration: paid ? TextDecoration.lineThrough : null,
              color: paid ? theme.colorScheme.onSurfaceVariant : null,
            ),
          ),
          subtitle: Text(
            _caption(),
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
          secondary: highlighted
              ? Icon(
                  status.urgency == ObligationUrgency.overdue
                      ? Icons.error_outline
                      : Icons.notifications_active_outlined,
                  color: color,
                  size: 20,
                )
              : null,
        ),
      ),
    );
  }
}
