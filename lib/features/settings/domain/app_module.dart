import 'package:flutter/material.dart';

/// Функциональные разделы приложения, которые можно включать и отключать.
enum AppModule {
  tasks(
    storageKey: 'module_tasks_enabled',
    navIndex: 1,
    title: 'Задачи',
    description: 'Список дел, бытовые обязанности и приоритеты',
    icon: Icons.task_alt_rounded,
  ),
  habits(
    storageKey: 'module_habits_enabled',
    navIndex: 2,
    title: 'Привычки и челленджи',
    description: 'Ежедневные привычки, серии выполнений и челленджи',
    icon: Icons.local_fire_department_rounded,
  ),
  finance(
    storageKey: 'module_finance_enabled',
    navIndex: 3,
    title: 'Финансы',
    description: 'Счета, кредиты, депозиты, обязательные платежи и операции',
    icon: Icons.account_balance_wallet_rounded,
  ),
  routine(
    storageKey: 'module_routine_enabled',
    navIndex: 4,
    title: 'Рутина',
    description: 'Базовые ежедневные действия и чек-лист дня с автосбросом',
    icon: Icons.wb_sunny_outlined,
  );

  const AppModule({
    required this.storageKey,
    required this.navIndex,
    required this.title,
    required this.description,
    required this.icon,
  });

  /// Ключ в таблице настроек.
  final String storageKey;

  /// Индекс экрана раздела в боковом меню / IndexedStack.
  final int navIndex;
  final String title;
  final String description;
  final IconData icon;

  /// По умолчанию все разделы включены.
  static const bool defaultEnabled = true;
}
