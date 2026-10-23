import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../providers/finance_provider.dart';

/// Включает или выключает режим администратора финансов и сообщает об этом.
void toggleFinanceAdminMode(BuildContext context, WidgetRef ref) {
  final notifier = ref.read(financeAdminModeProvider.notifier)..toggle();
  final active = ref.read(financeAdminModeProvider);
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    duration: const Duration(seconds: 2),
    content: Text(active
        ? 'Режим администратора включен. Доступен пропуск платежей.'
        : 'Режим администратора выключен'),
    action: active
        ? SnackBarAction(label: 'Выключить', onPressed: notifier.disable)
        : null,
  ));
}

/// Тонкая цветная полоса-индикатор под шапкой, пока активен режим
/// администратора.
class AdminModeStrip extends ConsumerWidget {
  const AdminModeStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(financeAdminModeProvider)) return const SizedBox.shrink();
    return Container(
      key: const ValueKey('admin_mode_strip'),
      height: 3,
      color: AppTheme.adminAccent,
    );
  }
}

/// Бейдж «ADMIN».
class AdminBadge extends StatelessWidget {
  const AdminBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: AppTheme.adminAccent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        'ADMIN',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
          color: Colors.black,
        ),
      ),
    );
  }
}
