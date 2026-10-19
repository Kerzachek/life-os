import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/settings_repository.dart';
import '../../domain/app_module.dart';

final rawSettingsStreamProvider = StreamProvider<Map<String, String>>((ref) {
  return ref.watch(settingsRepositoryProvider).watchAll();
});

Set<AppModule> _resolveEnabled(Map<String, String> settings) {
  return {
    for (final module in AppModule.values)
      if (_parseBool(settings[module.storageKey]) ?? AppModule.defaultEnabled)
        module,
  };
}

bool? _parseBool(String? raw) {
  if (raw == null) return null;
  return raw == 'true';
}

/// Набор включённых разделов. Пока настройки загружаются — все включены.
final enabledModulesProvider = Provider<Set<AppModule>>((ref) {
  final settings = ref.watch(rawSettingsStreamProvider).value;
  if (settings == null) return AppModule.values.toSet();
  return _resolveEnabled(settings);
});

final settingsControllerProvider = Provider<SettingsController>((ref) {
  return SettingsController(ref.watch(settingsRepositoryProvider));
});

class SettingsController {
  final SettingsRepository _repository;

  SettingsController(this._repository);

  /// Включает/отключает раздел.
  ///
  /// Возвращает `false`, если действие отклонено: нельзя отключить
  /// последний активный раздел.
  Future<bool> setModuleEnabled(AppModule module, bool enabled) async {
    if (!enabled) {
      final current = _resolveEnabled(await _repository.readAll());
      final remaining = current.where((m) => m != module);
      if (remaining.isEmpty) {
        return false;
      }
    }
    await _repository.setValue(module.storageKey, enabled.toString());
    return true;
  }
}
