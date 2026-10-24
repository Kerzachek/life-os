import 'dart:async';

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
import 'features/finance/presentation/providers/finance_provider.dart';
import 'features/finance/presentation/screens/finance_screen.dart';
import 'features/habits/presentation/screens/habits_screen.dart';
import 'features/notes/presentation/screens/notes_screen.dart';
import 'features/overview/presentation/screens/overview_screen.dart';
import 'features/quick_actions/presentation/providers/system_overlay_provider.dart';
import 'features/quick_actions/presentation/widgets/quick_actions_overlay.dart';
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
  StreamSubscription<String>? _overlayActions;

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
      _startSystemOverlay();
    });
  }

  @override
  void dispose() {
    _overlayActions?.cancel();
    super.dispose();
  }

  /// Системный оверлей (кнопка поверх всех окон ОС): синхронизация с
  /// настройками и запуск выбранных в нём действий.
  Future<void> _startSystemOverlay() async {
    if (!ref.read(systemOverlaySupportedProvider)) return;
    ref.read(systemOverlayControllerProvider).start();
    final service = ref.read(systemOverlayServiceProvider);
    _overlayActions = service.actions.listen(_runOverlayAction);
    // Android: приложение было закрыто и запущено самим оверлеем.
    final pending = await service.takePendingAction();
    if (pending != null) _runOverlayAction(pending);
  }

  /// Открывает форму действия, выбранного в оверлее. Окно LifeOS к этому
  /// моменту уже выведено на передний план нативной стороной.
  void _runOverlayAction(String id) {
    if (!mounted) return;
    final enabled = ref.read(enabledModulesProvider);
    final action = quickMenuActions
        .where((a) => a.id == id && enabled.contains(a.module))
        .firstOrNull;
    if (action == null) return;
    showFormSheet<void>(context: context, builder: action.builder);
  }

  void _openSettings() => _select(AppSidebar.settingsIndex);

  /// Переход между разделами. Уход с «Финансов» выключает режим
  /// администратора.
  void _select(int index) {
    if (index != AppSidebar.financeIndex) {
      ref.read(financeAdminModeProvider.notifier).disable();
    }
    setState(() {
      _currentIndex = index;
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
      case 5:
        return const NotesScreen();
      default:
        return const SettingsScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabledModules = ref.watch(enabledModulesProvider);
    // Держит планировщик уведомлений (и его подписки на данные) активным.
    ref.watch(notificationSchedulerProvider);
    // Раздел «Финансы» отключили (в т.ч. синхронизацией) — режим не нужен.
    ref.listen(enabledModulesProvider, (_, modules) {
      if (!modules.contains(AppModule.finance)) {
        ref.read(financeAdminModeProvider.notifier).disable();
      }
    });

    bool isVisible(int index) {
      final module = _moduleByIndex[index];
      return module == null || enabledModules.contains(module);
    }

    // Если текущий раздел отключён — возвращаемся на дашборд.
    final effectiveIndex =
        isVisible(_currentIndex) ? _currentIndex : AppSidebar.dashboardIndex;

    // Все разделы живут в одном маршруте, и их FAB-кнопки делят hero-тег
    // по умолчанию: без HeroMode переход на полноэкранную страницу
    // (редактор заметки на телефоне) падает на дубликате тега.
    // Плавающая кнопка быстрых действий — поверх области разделов (не меню):
    // отступы навигации, выреза и клавиатуры уже сняты SafeArea и Scaffold.
    final screens = Stack(
      fit: StackFit.expand,
      children: [
        HeroMode(
          enabled: false,
          child: IndexedStack(
            index: effectiveIndex,
            children: [
              for (var i = 0; i < AppSidebar.screenCount; i++)
                isVisible(i) ? _buildScreen(i) : const SizedBox.shrink(),
            ],
          ),
        ),
        if (ref.watch(showQuickActionsWidgetProvider))
          const QuickActionsOverlay(),
      ],
    );

    final items = AppSidebar.visibleNavItems(enabledModules);
    final selected = items.indexWhere((item) => item.index == effectiveIndex);
    final selectedPosition = selected < 0 ? 0 : selected;

    // Телефон горизонтально: нижняя панель съела бы и без того малую высоту,
    // поэтому разделы — в узкой ленте иконок слева.
    if (isCompactLandscape(context)) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: selectedPosition,
              onDestinationSelected: (i) => _select(items[i].index),
              labelType: NavigationRailLabelType.none,
              minWidth: 56,
              scrollable: true,
              groupAlignment: 0,
              destinations: [
                for (final item in items)
                  NavigationRailDestination(
                    icon: Tooltip(message: item.label, child: Icon(item.icon)),
                    label: Text(item.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: SafeArea(left: false, child: screens)),
          ],
        ),
      );
    }

    // Узкий экран (телефон): боковое меню скрыто, разделы — в нижней панели.
    // Шесть подписей на ~360dp не помещаются («Настройк/и»), поэтому только
    // иконки с индикатором-«пилюлей»; название — во всплывающей подсказке.
    // Отступ под жест «Домой» NavigationBar добавляет сам (внутренний SafeArea).
    if (isMobileLayout(context)) {
      return Scaffold(
        body: SafeArea(bottom: false, child: screens),
        bottomNavigationBar: NavigationBar(
          height: 64,
          selectedIndex: selectedPosition,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
          onDestinationSelected: (i) => _select(items[i].index),
          destinations: [
            for (final item in items)
              NavigationDestination(icon: Icon(item.icon), label: item.label),
          ],
        ),
      );
    }

    // SafeArea: планшет или окно с системными панелями и вырезами.
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            AppSidebar(
              selectedIndex: effectiveIndex,
              onDestinationSelected: _select,
            ),
            Expanded(child: screens),
          ],
        ),
      ),
    );
  }
}

