import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../../features/settings/data/repositories/settings_repository.dart';
import '../../features/settings/presentation/providers/settings_provider.dart';
import 'autostart_service.dart';
import 'notification_service.dart';
import 'routine_reset_service.dart';

/// Фоновый режим: значок в системном трее и перехват закрытия окна.
///
/// Если включена «Работа в фоне», крестик скрывает окно в трей,
/// иначе — завершает приложение. Выход из меню трея закрывает всегда.
class TrayService with WindowListener {
  static const String tooltip = 'LifeOS';
  static const String windowsIconAsset = 'assets/app_icon.ico';
  static const String macosIconAsset = 'assets/tray_icon.png';

  /// Windows ждёт .ico, строка меню macOS — PNG.
  static String get iconAsset =>
      Platform.isMacOS ? macosIconAsset : windowsIconAsset;

  static bool _initialized = false;
  static bool _launchedMinimized = false;

  /// Значок держим в статическом поле: собранный GC объект убирает его из трея.
  static TrayIcon? _trayIcon;

  /// Фоновый режим доступен: платформа Windows/macOS и [initialize] прошёл успешно.
  static bool get isAvailable => _initialized;

  final SettingsRepository _settings;
  final NotificationService _notifications;

  /// Вызывается, когда окно показано из трея или получило фокус
  /// (например, для проверки смены суток в рутине).
  final VoidCallback? onWindowShown;

  final List<MenuItem> _menuItems = [];
  bool _started = false;
  bool _quitting = false;
  bool _backgroundHintShown = false;

  TrayService(this._settings, this._notifications, {this.onWindowShown});

  /// Подключает window_manager и включает перехват крестика.
  /// Вызывается один раз в `main` с аргументами командной строки.
  static Future<void> initialize(List<String> args) async {
    if (!Platform.isWindows && !Platform.isMacOS) return;
    try {
      await windowManager.ensureInitialized();
      await windowManager.setPreventClose(true);
      _launchedMinimized = args.contains(launchMinimizedArg);
      _initialized = true;
    } catch (e) {
      debugPrint('TrayService: инициализация не удалась: $e');
    }
  }

  /// Убирает значок из трея. Вызывать перед `exit`, иначе значок
  /// остаётся «призраком» до наведения курсора.
  static void removeTrayIcon() {
    final icon = _trayIcon;
    _trayIcon = null;
    if (icon == null) return;
    try {
      icon.setVisible(false);
      icon.dispose();
    } catch (e) {
      debugPrint('TrayService: не удалось убрать значок: $e');
    }
  }

  /// Создаёт значок в трее и подписывается на события окна.
  Future<void> start() async {
    if (!_initialized || _started) return;
    _started = true;
    windowManager.addListener(this);
    _createTrayIcon();

    // Автозапуск стартует со скрытым окном; показываем его,
    // если фоновый режим выключен (иначе окно было бы недоступно).
    if (_launchedMinimized && !await _backgroundModeEnabled()) {
      await showWindow();
    }
  }

  void _createTrayIcon() {
    try {
      final icon = TrayIcon.create();
      if (icon == null) {
        debugPrint('TrayService: не удалось создать значок в трее');
        return;
      }
      final image = ImageAsset.fromAsset(iconAsset);
      if (image != null) icon.icon = image;
      icon.setTooltip(tooltip);

      final menu = Menu.create();
      if (menu != null) {
        _addMenuItem(menu, 'Открыть LifeOS', showWindow);
        menu.addSeparator();
        _addMenuItem(menu, 'Выход', quit);
        icon.setContextMenu(menu);
      }
      // В строке меню macOS меню принято открывать обычным кликом.
      icon.setContextMenuTrigger(Platform.isMacOS
          ? ContextMenuTrigger.clicked
          : ContextMenuTrigger.rightClicked);
      if (!Platform.isMacOS) {
        icon.addListener((event) {
          if (event is TrayIconClickedEvent ||
              event is TrayIconDoubleClickedEvent) {
            unawaited(showWindow());
          }
        });
      }
      icon.setVisible(true);
      _trayIcon = icon;
    } catch (e) {
      debugPrint('TrayService: ошибка создания значка в трее: $e');
    }
  }

  void _addMenuItem(Menu menu, String label, Future<void> Function() onClick) {
    final item = MenuItem.createWithLabelAndType(label, MenuItemType.normal);
    if (item == null) return;
    item.addListener((event) {
      if (event is MenuItemClickedEvent) unawaited(onClick());
    });
    menu.addItem(item);
    _menuItems.add(item);
  }

  Future<bool> _backgroundModeEnabled() async {
    try {
      return resolveBackgroundModeEnabled(await _settings.readAll());
    } catch (e) {
      debugPrint('TrayService: не удалось прочитать настройки: $e');
      return false;
    }
  }

  /// Показывает окно из трея (или из свёрнутого состояния) и даёт ему фокус.
  Future<void> showWindow() async {
    if (!_initialized) return;
    await windowManager.show();
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.focus();
    onWindowShown?.call();
  }

  /// Полностью завершает приложение, минуя сворачивание в трей.
  Future<void> quit() async {
    if (_quitting) return;
    _quitting = true;
    removeTrayIcon();
    try {
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    } catch (e) {
      debugPrint('TrayService: закрытие окна не удалось: $e');
      exit(0);
    }
  }

  @override
  void onWindowFocus() {
    onWindowShown?.call();
  }

  @override
  void onWindowClose() {
    unawaited(_handleClose());
  }

  Future<void> _handleClose() async {
    if (_quitting) return;
    if (!await _backgroundModeEnabled()) {
      await quit();
      return;
    }

    await windowManager.hide();
    if (_backgroundHintShown) return;
    _backgroundHintShown = true;
    await _notifications.show(
      title: 'LifeOS продолжает работу в фоне',
      body: 'Открыть приложение или выйти можно через значок '
          '${Platform.isMacOS ? 'в строке меню' : 'в системном трее'}.',
    );
  }

  void dispose() {
    if (_started) windowManager.removeListener(this);
  }
}

final trayServiceProvider = Provider<TrayService>((ref) {
  final service = TrayService(
    ref.watch(settingsRepositoryProvider),
    ref.watch(notificationServiceProvider),
    onWindowShown: () =>
        unawaited(ref.read(routineResetServiceProvider).checkNow()),
  );
  ref.onDispose(service.dispose);
  return service;
});
