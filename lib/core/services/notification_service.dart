import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_notifier/local_notifier.dart';

import '../../features/settings/data/repositories/settings_repository.dart';
import '../../features/settings/domain/app_module.dart';
import '../../features/settings/presentation/providers/settings_provider.dart';

/// Системные всплывающие уведомления Windows (Toast Notifications).
///
/// Перед отправкой проверяет настройки: глобальный переключатель
/// уведомлений и включён ли раздел-источник ([AppModule]).
class NotificationService {
  static const String appName = 'LifeOS';

  static bool _initialized = false;

  /// Уведомления доступны: платформа Windows и [initialize] прошёл успешно.
  static bool get isAvailable => _initialized;

  final SettingsRepository _settings;

  NotificationService(this._settings);

  /// Регистрирует приложение в центре уведомлений Windows (создаёт ярлык
  /// с AppUserModelID при необходимости). Вызывается один раз в `main`.
  static Future<void> initialize() async {
    if (!Platform.isWindows) return;
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

    final notification = LocalNotification(title: title, body: body);
    // Пакет хранит каждое уведомление в списке слушателей — освобождаем.
    notification.onClose = (_) => localNotifier.destroy(notification);
    try {
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
