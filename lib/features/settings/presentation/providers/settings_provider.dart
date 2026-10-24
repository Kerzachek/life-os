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

/// Ключ переключателя системного оверлея (кнопка поверх всех окон ОС).
const String systemOverlayEnabledKey = 'system_overlay_enabled';

/// Ключ чекбокса «Скрывать оверлей, когда открыто окно LifeOS».
const String systemOverlayHideWhenAppVisibleKey =
    'system_overlay_hide_when_app_visible';

/// Ключ положения системного оверлея (формат [QuickButtonPosition]).
const String systemOverlayPositionKey = 'system_overlay_position';

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

/// Включён ли системный оверлей (по умолчанию — нет: на Android нужен
/// отдельный доступ «Поверх других приложений»).
bool resolveSystemOverlayEnabled(Map<String, String> settings) {
  return _parseBool(settings[systemOverlayEnabledKey]) ?? false;
}

/// Прятать ли системный оверлей при открытом окне LifeOS (по умолчанию —
/// да: кнопка не перекрывает интерфейс самого приложения).
bool resolveSystemOverlayHideWhenAppVisible(Map<String, String> settings) {
  return _parseBool(settings[systemOverlayHideWhenAppVisibleKey]) ?? true;
}

/// Положение кнопки системного оверлея: прижата к левому или правому краю, по
/// вертикали — доля доступной высоты. Доля, а не пиксели: окно меняет
/// размер, телефон поворачивается — кнопка остаётся «на том же месте».
class QuickButtonPosition {
  final bool isLeft;
  final double verticalFraction;

  const QuickButtonPosition({
    required this.isLeft,
    required this.verticalFraction,
  });

  /// Справа, чуть выше середины — не поверх FAB-кнопок разделов.
  static const QuickButtonPosition initial =
      QuickButtonPosition(isLeft: false, verticalFraction: 0.6);

  /// Формат хранения: `left:0.4200` / `right:0.6000`.
  String encode() =>
      '${isLeft ? 'left' : 'right'}:${verticalFraction.toStringAsFixed(4)}';

  static QuickButtonPosition decode(String? raw) {
    final parts = raw?.split(':');
    if (parts == null || parts.length != 2) return initial;
    final fraction = double.tryParse(parts[1]);
    if (fraction == null || !fraction.isFinite) return initial;
    return QuickButtonPosition(
      isLeft: parts[0] == 'left',
      verticalFraction: fraction.clamp(0.0, 1.0),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is QuickButtonPosition &&
      other.isLeft == isLeft &&
      other.verticalFraction == verticalFraction;

  @override
  int get hashCode => Object.hash(isLeft, verticalFraction);
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

/// Включён ли системный оверлей.
final systemOverlayEnabledProvider = Provider<bool>((ref) {
  final settings = ref.watch(rawSettingsStreamProvider).value;
  if (settings == null) return false;
  return resolveSystemOverlayEnabled(settings);
});

/// Прятать ли системный оверлей при открытом окне LifeOS.
final systemOverlayHideWhenAppVisibleProvider = Provider<bool>((ref) {
  final settings = ref.watch(rawSettingsStreamProvider).value;
  if (settings == null) return true;
  return resolveSystemOverlayHideWhenAppVisible(settings);
});

/// Сохранённое положение системного оверлея.
final systemOverlayPositionProvider = Provider<QuickButtonPosition>((ref) {
  final settings = ref.watch(rawSettingsStreamProvider).value;
  return QuickButtonPosition.decode(settings?[systemOverlayPositionKey]);
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

  Future<void> setSystemOverlayEnabled(bool enabled) {
    return _repository.setValue(systemOverlayEnabledKey, enabled.toString());
  }

  Future<void> setSystemOverlayHideWhenAppVisible(bool hide) {
    return _repository.setValue(
        systemOverlayHideWhenAppVisibleKey, hide.toString());
  }

  Future<void> setSystemOverlayPosition(QuickButtonPosition position) {
    return _repository.setValue(systemOverlayPositionKey, position.encode());
  }

  /// Создаёт или удаляет запись автозапуска в реестре и запоминает выбор.
  Future<void> setLaunchAtStartup(bool enabled) async {
    await _autostart.setEnabled(enabled);
    await _repository.setValue(launchAtStartupKey, enabled.toString());
  }
}
