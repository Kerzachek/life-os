import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/domain/app_module.dart';
import '../services/update_service.dart';
import '../../features/settings/presentation/providers/settings_provider.dart';

class NavigationItemData {
  final int index;
  final String label;
  final IconData icon;

  /// Раздел, который можно отключить в настройках. `null` — пункт всегда виден.
  final AppModule? module;

  const NavigationItemData({
    required this.index,
    required this.label,
    required this.icon,
    this.module,
  });
}

class AppSidebar extends ConsumerWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const AppSidebar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  static const int dashboardIndex = 0;
  static const int settingsIndex = 4;

  static const List<NavigationItemData> _navItems = [
    NavigationItemData(index: dashboardIndex, label: 'Дашборд', icon: Icons.grid_view_rounded),
    NavigationItemData(index: 1, label: 'Задачи', icon: Icons.task_alt_rounded, module: AppModule.tasks),
    NavigationItemData(index: 2, label: 'Привычки', icon: Icons.local_fire_department_rounded, module: AppModule.habits),
    NavigationItemData(index: 3, label: 'Финансы', icon: Icons.account_balance_wallet_rounded, module: AppModule.finance),
    NavigationItemData(index: settingsIndex, label: 'Настройки', icon: Icons.settings_rounded),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final enabledModules = ref.watch(enabledModulesProvider);
    final appVersion = ref.watch(currentAppVersionProvider).value;
    final visibleItems = _navItems
        .where((item) => item.module == null || enabledModules.contains(item.module))
        .toList();

    return Container(
      width: 200,
      decoration: BoxDecoration(
        color: const Color(0xFF0A0D12),
        border: Border(right: BorderSide(color: colorScheme.outline, width: 1)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colorScheme.primary.withValues(alpha: 0.6)),
                  ),
                  child: Icon(Icons.space_dashboard_rounded, color: colorScheme.primary, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('LIFE OS', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900, letterSpacing: 1.5, color: Colors.white)),
                      Text('PERSONAL ERP', style: theme.textTheme.labelSmall?.copyWith(fontSize: 9, letterSpacing: 1.2, color: colorScheme.onSurfaceVariant)),
                      if (appVersion != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text('v$appVersion', style: theme.textTheme.labelSmall?.copyWith(fontSize: 9, letterSpacing: 0.8, color: colorScheme.primary.withValues(alpha: 0.8))),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: visibleItems.length,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemBuilder: (context, idx) {
                final item = visibleItems[idx];
                final isSelected = item.index == selectedIndex;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => onDestinationSelected(item.index),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected ? colorScheme.primary.withValues(alpha: 0.15) : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: isSelected ? Border.all(color: colorScheme.primary.withValues(alpha: 0.4)) : null,
                        ),
                        child: Row(
                          children: [
                            Icon(item.icon, size: 20, color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant),
                            const SizedBox(width: 10),
                            Text(item.label, style: TextStyle(fontSize: 13, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500, color: isSelected ? Colors.white : colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colorScheme.outline),
              ),
              child: Row(
                children: [
                  CircleAvatar(radius: 12, backgroundColor: colorScheme.primary.withValues(alpha: 0.2), child: Text('E', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.primary))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('EGO', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                        Text('Оператор', style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
