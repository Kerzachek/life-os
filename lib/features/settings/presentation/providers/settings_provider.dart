import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/autostart_service.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/app_module.dart';

/// Ключ глобального переключателя системных уведомлений.
const String notificationsEnabledKey = 'notifications_enabled';

/// Ключ переключателя «Работа в фоне» (сворачивание в трей при закрытии окна).
const String backgroundModeKey = 'background_mode_enabled';

/// Ключ переключателя «Автозапуск с Windows». Источник истины — реестр,
/// здесь хранится последний выбор пользователя.
const String launchAtStartupKey = 'launch_at_startup';

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

/// Сворачивать ли окно в трей при закрытии (по умолчанию — да,
/// чтобы напоминания приходили и при закрытом окне).
bool resolveBackgroundModeEnabled(Map<String, String> settings) {
  return _parseBool(settings[backgroundModeKey]) ?? true;
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

/// Состояние переключателя «Работа в фоне».
final backgroundModeEnabledProvider = Provider<bool>((ref) {
  final settings = ref.watch(rawSettingsStreamProvider).value;
  if (settings == null) return true;
  return resolveBackgroundModeEnabled(settings);
});

/// Фактическое состояние автозапуска по записи в реестре Windows.
/// Перечитывается при каждом изменении настроек.
final launchAtStartupEnabledProvider = FutureProvider<bool>((ref) {
  ref.watch(rawSettingsStreamProvider);
  return ref.watch(autostartServiceProvider).isEnabled();
});

final settingsControllerProvider = Provider<SettingsController>((ref) {
  return SettingsController(
    ref.watch(settingsRepositoryProvider),
    ref.watch(autostartServiceProvider),
  );
});

class SettingsController {
  final SettingsRepository _repository;
  final AutostartService _autostart;

  SettingsController(this._repository, this._autostart);

  /// Включает/отключает раздел. Отключить можно все разделы:
  /// Дашборд в этом случае показывает пустое состояние.
  Future<void> setModuleEnabled(AppModule module, bool enabled) {
    return _repository.setValue(module.storageKey, enabled.toString());
  }

  Future<void> setNotificationsEnabled(bool enabled) {
    return _repository.setValue(notificationsEnabledKey, enabled.toString());
  }

  Future<void> setBackgroundModeEnabled(bool enabled) {
    return _repository.setValue(backgroundModeKey, enabled.toString());
  }

  /// Создаёт или удаляет запись автозапуска в реестре и запоминает выбор.
  Future<void> setLaunchAtStartup(bool enabled) async {
    await _autostart.setEnabled(enabled);
    await _repository.setValue(launchAtStartupKey, enabled.toString());
  }
}
