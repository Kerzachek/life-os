import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_notifier/local_notifier.dart';

import '../../features/settings/data/repositories/settings_repository.dart';
import '../../features/settings/domain/app_module.dart';
import '../../features/settings/presentation/providers/settings_provider.dart';

/// Системные всплывающие уведомления: Toast Notifications в Windows,
/// Notification Center в macOS, шторка уведомлений в Android.
///
/// Перед отправкой проверяет настройки: глобальный переключатель
/// уведомлений и включён ли раздел-источник ([AppModule]).
class NotificationService {
  static const String appName = 'LifeOS';

  static const String _androidChannelId = 'lifeos_reminders';
  static const String _androidChannelName = 'Напоминания LifeOS';

  static bool _initialized = false;

  /// Плагин уведомлений Android; на десктопе — `null` (там local_notifier).
  static FlutterLocalNotificationsPlugin? _androidPlugin;
  static int _androidNextId = 0;

  /// Уведомления доступны: платформа Windows/macOS/Android
  /// и [initialize] прошёл успешно.
  static bool get isAvailable => _initialized;

  final SettingsRepository _settings;

  NotificationService(this._settings);

  /// Регистрирует приложение в центре уведомлений (в Windows создаёт ярлык
  /// с AppUserModelID при необходимости). Вызывается один раз в `main`.
  static Future<void> initialize() async {
    if (Platform.isAndroid) return _initializeAndroid();
    if (!Platform.isWindows && !Platform.isMacOS) return;
    try {
      await localNotifier.setup(
        appName: appName,
        shortcutPolicy: ShortcutPolicy.requireCreate,
      );
      _initialized = true;
    } catch (e) {
      debugPrint('NotificationService: инициализация не удалась: $e');
    }
  }

  /// Android: на 13+ запрашивает разрешение POST_NOTIFICATIONS. Отказ не
  /// блокирует запуск — система просто не покажет уведомления, пока
  /// пользователь не выдаст разрешение в настройках.
  static Future<void> _initializeAndroid() async {
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      await plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      _androidPlugin = plugin;
      _initialized = true;
    } catch (e) {
      debugPrint('NotificationService: инициализация не удалась: $e');
    }
  }

  /// Можно ли сейчас отправлять уведомления от [module]
  /// (`null` — системные уведомления, не привязанные к разделу).
  Future<bool> canNotify([AppModule? module]) async {
    if (!_initialized) return false;
    final settings = await _settings.readAll();
    if (!resolveNotificationsEnabled(settings)) return false;
    return module == null || resolveEnabledModules(settings).contains(module);
  }

  /// Показывает уведомление. Возвращает `false`, если оно не отправлено
  /// (уведомления выключены, раздел отключён или ошибка платформы).
  Future<bool> show({
    required String title,
    required String body,
    AppModule? module,
  }) async {
    if (!await canNotify(module)) return false;

    try {
      final androidPlugin = _androidPlugin;
      if (androidPlugin != null) {
        await androidPlugin.show(
          id: _androidNextId++,
          title: title,
          body: body,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              _androidChannelId,
              _androidChannelName,
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
        );
        return true;
      }

      final notification = LocalNotification(title: title, body: body);
      // Пакет хранит каждое уведомление в списке слушателей — освобождаем.
      notification.onClose = (_) => localNotifier.destroy(notification);
      await notification.show();
      return true;
    } catch (e) {
      debugPrint('NotificationService: не удалось показать уведомление: $e');
      return false;
    }
  }
}

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService(ref.watch(settingsRepositoryProvider));
});
