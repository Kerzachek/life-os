import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/settings_repository.dart';
import '../../domain/app_module.dart';

/// Ключ глобального переключателя системных уведомлений.
const String notificationsEnabledKey = 'notifications_enabled';

final rawSettingsStreamProvider = StreamProvider<Map<String, String>>((ref) {
  return ref.watch(settingsRepositoryProvider).watchAll();
});

/// Включённые разделы по карте настроек.
Set<AppModule> resolveEnabledModules(Map<String, String> settings) {
  return {
    for (final module in AppModule.values)
      if (_parseBool(settings[module.storageKey]) ?? AppModule.defaultEnabled)
        module,
  };
}

/// Включены ли системные уведомления (по умолчанию — да).
bool resolveNotificationsEnabled(Map<String, String> settings) {
  return _parseBool(settings[notificationsEnabledKey]) ?? true;
}

bool? _parseBool(String? raw) {
  if (raw == null) return null;
  return raw == 'true';
}

/// Набор включённых разделов. Пока настройки загружаются — все включены.
final enabledModulesProvider = Provider<Set<AppModule>>((ref) {
  final settings = ref.watch(rawSettingsStreamProvider).value;
  if (settings == null) return AppModule.values.toSet();
  return resolveEnabledModules(settings);
});

/// Состояние глобального переключателя уведомлений.
final notificationsEnabledProvider = Provider<bool>((ref) {
  final settings = ref.watch(rawSettingsStreamProvider).value;
  if (settings == null) return true;
  return resolveNotificationsEnabled(settings);
});

final settingsControllerProvider = Provider<SettingsController>((ref) {
  return SettingsController(ref.watch(settingsRepositoryProvider));
});

class SettingsController {
  final SettingsRepository _repository;

  SettingsController(this._repository);

  /// Включает/отключает раздел. Отключить можно все разделы:
  /// Дашборд в этом случае показывает пустое состояние.
  Future<void> setModuleEnabled(AppModule module, bool enabled) {
    return _repository.setValue(module.storageKey, enabled.toString());
  }

  Future<void> setNotificationsEnabled(bool enabled) {
    return _repository.setValue(notificationsEnabledKey, enabled.toString());
  }
}
