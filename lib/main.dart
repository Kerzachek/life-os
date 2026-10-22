import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/platform_info.dart';
import 'core/services/autostart_service.dart';
import 'core/services/notification_scheduler.dart';
import 'core/services/notification_service.dart';
import 'core/services/routine_reset_service.dart';
import 'core/services/tray_service.dart';
import 'core/sync/google_drive_sync_service.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/app_sidebar.dart';
import 'core/widgets/responsive.dart';
import 'features/finance/presentation/screens/finance_screen.dart';
import 'features/habits/presentation/screens/habits_screen.dart';
import 'features/overview/presentation/screens/overview_screen.dart';
import 'features/routine/presentation/screens/routine_screen.dart';
import 'features/settings/domain/app_module.dart';
import 'features/settings/presentation/providers/settings_provider.dart';
import 'features/settings/presentation/screens/settings_screen.dart';
import 'features/tasks/presentation/screens/tasks_screen.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.initialize();
  // Окно, трей и автозапуск — только десктоп: на Android этих плагинов нет.
  if (isDesktopPlatform) {
    // Автозапуск: LifeOS + Platform.resolvedExecutable, флаг --minimized.
    AutostartService.setup();
    await TrayService.initialize(args);
  }
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

  @override
  void initState() {
    super.initState();
    // Автосинхронизация при старте (если пользователь уже вошёл в Google).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Сброс рутины — до синхронизации, чтобы в облако ушёл новый день.
      ref.read(routineResetServiceProvider).start();
      ref.read(googleDriveSyncServiceProvider.notifier).start();
      ref.read(notificationSchedulerProvider).start();
      if (isDesktopPlatform) ref.read(trayServiceProvider).start();
    });
  }

  void _openSettings() {
    setState(() {
      _currentIndex = AppSidebar.settingsIndex;
    });
  }

  static final Map<int, AppModule> _moduleByIndex = {
    for (final module in AppModule.values) module.navIndex: module,
  };

  Widget _buildScreen(int index) {
    switch (index) {
      case 0:
        return OverviewScreen(onOpenSettings: _openSettings);
      case 1:
        return const TasksScreen();
      case 2:
        return const HabitsScreen();
      case 3:
        return const FinanceScreen();
      case 4:
        return const RoutineScreen();
      default:
        return const SettingsScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabledModules = ref.watch(enabledModulesProvider);
    // Держит планировщик уведомлений (и его подписки на данные) активным.
    ref.watch(notificationSchedulerProvider);

    bool isVisible(int index) {
      final module = _moduleByIndex[index];
      return module == null || enabledModules.contains(module);
    }

    // Если текущий раздел отключён — возвращаемся на дашборд.
    final effectiveIndex =
        isVisible(_currentIndex) ? _currentIndex : AppSidebar.dashboardIndex;

    void select(int index) {
      setState(() {
        _currentIndex = index;
      });
    }

    final screens = IndexedStack(
      index: effectiveIndex,
      children: [
        for (var i = 0; i < AppSidebar.screenCount; i++)
          isVisible(i) ? _buildScreen(i) : const SizedBox.shrink(),
      ],
    );

    // Узкий экран (телефон): боковое меню скрыто, разделы — в нижней панели.
    if (isMobileLayout(context)) {
      final items = AppSidebar.visibleNavItems(enabledModules);
      final selected = items.indexWhere((item) => item.index == effectiveIndex);
      return Scaffold(
        body: SafeArea(bottom: false, child: screens),
        // До 6 пунктов на ~360dp: мелкий шрифт без системного увеличения,
        // иначе «Настройки» переносится на две строки.
        bottomNavigationBar: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.0,
          child: NavigationBarTheme(
            data: NavigationBarTheme.of(context).copyWith(
              labelTextStyle: const WidgetStatePropertyAll(
                TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
            child: NavigationBar(
              selectedIndex: selected < 0 ? 0 : selected,
              labelBehavior:
                  NavigationDestinationLabelBehavior.onlyShowSelected,
              onDestinationSelected: (i) => select(items[i].index),
              destinations: [
                for (final item in items)
                  NavigationDestination(
                      icon: Icon(item.icon), label: item.label),
              ],
            ),
          ),
        ),
      );
    }

    // SafeArea: телефон в горизонтальной ориентации шире 600dp и получает
    // десктопную раскладку — без отступа меню уходит под строку состояния.
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            AppSidebar(
              selectedIndex: effectiveIndex,
              onDestinationSelected: select,
            ),
            Expanded(child: screens),
          ],
        ),
      ),
    );
  }
}

