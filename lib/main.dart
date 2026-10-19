import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'core/widgets/app_sidebar.dart';
import 'features/finance/presentation/screens/finance_screen.dart';
import 'features/habits/presentation/screens/habits_screen.dart';
import 'features/overview/presentation/screens/overview_screen.dart';
import 'features/settings/domain/app_module.dart';
import 'features/settings/presentation/providers/settings_provider.dart';
import 'features/settings/presentation/screens/settings_screen.dart';
import 'features/tasks/presentation/screens/tasks_screen.dart';

void main() {
  runApp(const HomeOrganizerApp());
}

class HomeOrganizerApp extends StatelessWidget {
  const HomeOrganizerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: MaterialApp(
        title: 'Life OS Dashboard',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkLauncherTheme,
        darkTheme: AppTheme.darkLauncherTheme,
        themeMode: ThemeMode.dark,
        home: const MainScreen(),
      ),
    );
  }
}

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  int _currentIndex = AppSidebar.dashboardIndex;

  static const Map<int, AppModule> _moduleByIndex = {
    1: AppModule.tasks,
    2: AppModule.habits,
    3: AppModule.finance,
  };

  Widget _buildScreen(int index) {
    switch (index) {
      case 0:
        return const OverviewScreen();
      case 1:
        return const TasksScreen();
      case 2:
        return const HabitsScreen();
      case 3:
        return const FinanceScreen();
      default:
        return const SettingsScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabledModules = ref.watch(enabledModulesProvider);

    bool isVisible(int index) {
      final module = _moduleByIndex[index];
      return module == null || enabledModules.contains(module);
    }

    // Если текущий раздел отключён — возвращаемся на дашборд.
    final effectiveIndex =
        isVisible(_currentIndex) ? _currentIndex : AppSidebar.dashboardIndex;

    return Scaffold(
      body: Row(
        children: [
          AppSidebar(
            selectedIndex: effectiveIndex,
            onDestinationSelected: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
          ),
          Expanded(
            child: IndexedStack(
              index: effectiveIndex,
              children: [
                for (var i = 0; i < 5; i++)
                  isVisible(i) ? _buildScreen(i) : const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

